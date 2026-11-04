import Foundation
import CryptoKit
import DeviceCheck

@MainActor
final class ReferralProof {
    private let service = DCAppAttestService.shared
    private let prefs = UserDefaults.standard
    private var usesDebugToken: Bool {
        #if DEBUG
        let values = Bundle.main.url(forResource: "BatchGate", withExtension: "plist")
            .flatMap { NSDictionary(contentsOf: $0) as? [String: String] }
        return values?["referralDebugVerification"] != "platform"
        #else
        return false
        #endif
    }
    var platform: String { usesDebugToken ? "debug" : "ios" }
    func keyID(identity: String) async throws -> String {
        if usesDebugToken { return identity }
        guard service.isSupported else { throw ReferralFailure.unavailable }
        if let saved = prefs.string(forKey: "referralAttestKey"),
           prefs.string(forKey: "referralAttestIdentity") == identity { return saved }
        // Restored preferences can contain a key ID belonging to another device.
        // Generate a new credential instead of repeatedly submitting the stale ID.
        rotate()
        let key: String = try await withCheckedThrowingContinuation { continuation in
            service.generateKey { key, error in
                if let key { continuation.resume(returning: key) }
                else { continuation.resume(throwing: error ?? ReferralFailure.unavailable) }
            }
        }
        prefs.set(key, forKey: "referralAttestKey")
        prefs.set(identity, forKey: "referralAttestIdentity")
        return key
    }
    var alreadyAttested: Bool { prefs.bool(forKey: "referralKeyAttested") }
    func rotate() {
        prefs.removeObject(forKey: "referralAttestKey")
        prefs.removeObject(forKey: "referralAttestIdentity")
        prefs.removeObject(forKey: "referralKeyAttested")
    }
    func proof(keyID: String, clientData: String, attestationRequired: Bool) async throws -> [String: String] {
        if usesDebugToken {
            let token = Bundle.main.url(forResource: "BatchGate", withExtension: "plist")
                .flatMap { NSDictionary(contentsOf: $0) as? [String: String] }?["referralDebugToken"] ?? ""
            guard token.count >= 32 else { throw ReferralFailure.unavailable }
            return ["token": token]
        }
        var encoded = clientData.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded) else { throw ReferralFailure.unavailable }
        let hash = Data(SHA256.hash(data: data))
        var proof: [String: String] = [:]
        if attestationRequired {
            let attestation: Data
            do {
                attestation = try await withCheckedThrowingContinuation { continuation in
                    service.attestKey(keyID, clientDataHash: hash) { data, error in
                        if let data { continuation.resume(returning: data) }
                        else { continuation.resume(throwing: error ?? ReferralFailure.unavailable) }
                    }
                }
            } catch {
                if (error as? DCError)?.code != .serverUnavailable { rotate() }
                throw error
            }
            // If the server never receives this enrollment, the next explicit submission rotates the key.
            prefs.set(true, forKey: "referralKeyAttested")
            proof["attestation"] = attestation.base64EncodedString()
        }
        let assertion: Data
        do {
            assertion = try await withCheckedThrowingContinuation { continuation in
                service.generateAssertion(keyID, clientDataHash: hash) { data, error in
                    if let data { continuation.resume(returning: data) }
                    else { continuation.resume(throwing: error ?? ReferralFailure.unavailable) }
                }
            }
        } catch {
            if (error as? DCError)?.code == .invalidKey { rotate() }
            throw error
        }
        proof["assertion"] = assertion.base64EncodedString()
        return proof
    }
}
