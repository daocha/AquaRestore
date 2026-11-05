import Foundation
import Combine
import UIKit
import Security

struct ReferralState: Decodable {
    struct Unlocks: Decodable { let batchPhoto: Bool; let batchVideo: Bool }
    let referralCode: String?
    let referralCount: Int
    let referredByCode: String?
    let unlocked: Unlocks
}

enum ReferralFailure: Error { case unavailable, api(String) }
private struct ReferralApiFailure: Decodable { let error: String }

@MainActor
final class ReferralCampaign: ObservableObject {
    static let shared = ReferralCampaign()
    @Published private(set) var referredBy = UserDefaults.standard.string(forKey: "referredByCode")
    @Published private(set) var count = UserDefaults.standard.integer(forKey: "referralCount")
    var active: Bool { BatchAccess.shared.referralActive }
    private let package = Bundle.main.bundleIdentifier ?? "com.aquarestore.app"
    // Cache a vendor-derived identity in Keychain, outside the app's ordinary preferences.
    // iOS provides no hardware identifier guaranteed to survive reinstall or device erase.
    lazy var deviceID: String? = {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: package + ".referral-identity-v1",
                                   kSecAttrAccount as String: "device"]
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, let saved = String(data: data, encoding: .utf8) { return saved }
        guard status == errSecItemNotFound, let vendor = UIDevice.current.identifierForVendor else { return nil }
        let identity = ReferralIdentity.deviceID(package: package, deviceID: vendor.uuidString.lowercased())
        var insert = query
        insert[kSecValueData as String] = Data(identity.utf8)
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { return nil }
        return identity
    }()
    var code: String? {
        guard let identity = deviceID else { return nil }
        let saved = UserDefaults.standard
        let registered = saved.string(forKey: "referralRegistration") == registration(identity)
        return ReferralIdentity.ownCode(deviceID: identity, issued: registered ? saved.string(forKey: "referralCode") : nil)
    }
    // Tied to the backend and identity: a new backend or device has not seen this registration.
    private func registration(_ identity: String) -> String { BatchAccess.shared.backendURL + "\n" + identity }
    private var registering = false
    private func deviceURL(_ identity: String) -> String { BatchAccess.shared.backendURL + "/v1/apps/\(package)/devices/\(identity)" }

    /// Registers this device once so friends can use its code. The response also restores any referrer and grants
    /// after cleared app data. Silent: a failure leaves the device unregistered, so the next launch tries again.
    func registerIfNeeded() async {
        guard active, !registering, let identity = deviceID else { return }
        let registration = registration(identity)
        // An install registered before codes were saved registers once more to learn its code.
        guard UserDefaults.standard.string(forKey: "referralRegistration") != registration
                || UserDefaults.standard.string(forKey: "referralCode") == nil else { return }
        registering = true
        defer { registering = false }
        do {
            let (data, _) = try await exchange(url: deviceURL(identity) + "/register", payload: [:])
            try save(JSONDecoder().decode(ReferralState.self, from: data))
            UserDefaults.standard.set(registration, forKey: "referralRegistration")
        } catch { NSLog("AquaRestore: referral registration deferred: \(type(of: error))") }
    }
    private func save(_ state: ReferralState) throws {
        guard state.referralCount >= 0, state.referralCode.map({ ReferralIdentity.acceptable($0, ownCode: "") }) ?? true else { throw ReferralFailure.unavailable }
        if let issued = state.referralCode { UserDefaults.standard.set(issued, forKey: "referralCode") }
        count = state.referralCount
        UserDefaults.standard.set(count, forKey: "referralCount")
        if let code = state.referredByCode {
            referredBy = code
            UserDefaults.standard.set(code, forKey: "referredByCode")
        }
        BatchAccess.shared.applyReferralUnlocks(photo: state.unlocked.batchPhoto, video: state.unlocked.batchVideo)
    }

    // Only locked batch actions read; only explicit code submission writes.
    @discardableResult func request(referralCode: String? = nil, unlockCode: String? = nil) async throws -> Bool {
        guard referralCode == nil || unlockCode == nil else { throw ReferralFailure.unavailable }
        guard active, let identity = deviceID else { throw ReferralFailure.unavailable }
        let base = deviceURL(identity)
        var payload: [String: Any]?
        if let submittedCode = unlockCode ?? referralCode {
            let verifier = ReferralProof()
            var keyID = try await verifier.keyID(identity: identity)
            func challenge(_ key: String) async throws -> [String: Any] {
                let (data, _) = try await exchange(url: base + "/challenge", payload:
                    ["action": unlockCode == nil ? "referral" : "unlock",
                     (unlockCode == nil ? "referralCode" : "unlockCode"): submittedCode,
                     "platform": verifier.platform, "keyId": key])
                guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ReferralFailure.unavailable }
                return result
            }
            var response = try await challenge(keyID)
            if verifier.platform == "ios", response["attestationRequired"] as? Bool == true, verifier.alreadyAttested {
                verifier.rotate()
                keyID = try await verifier.keyID(identity: identity)
                response = try await challenge(keyID)
            }
            guard let id = response["challengeId"] as? String, let clientData = response["clientData"] as? String,
                  let required = response["attestationRequired"] as? Bool else { throw ReferralFailure.unavailable }
            let proof = try await verifier.proof(keyID: keyID, clientData: clientData, attestationRequired: required)
            payload = ["challengeId": id, "proof": proof]
        }
        let (data, status) = try await exchange(url: base + (payload == nil ? "" : (unlockCode == nil ? "/referral" : "/unlock")), payload: payload)
        let state = try JSONDecoder().decode(ReferralState.self, from: data)
        guard referralCode == nil || state.referredByCode != nil else { throw ReferralFailure.unavailable }
        try save(state)
        return status == 200
    }
    private func exchange(url: String, payload: [String: Any]?) async throws -> (Data, Int) {
        guard let url = URL(string: url) else { throw ReferralFailure.unavailable }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: payload == nil ? 8 : 30)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let payload {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: NoReferralRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, data.count <= 65536 else { throw ReferralFailure.unavailable }
        if let failure = try? JSONDecoder().decode(ReferralApiFailure.self, from: data) {
            throw ReferralFailure.api(failure.error)
        }
        guard response.statusCode == 200 || (payload != nil && response.statusCode == 409) else { throw ReferralFailure.unavailable }
        return (data, response.statusCode)
    }
}

private final class NoReferralRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
