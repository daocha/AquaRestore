import SwiftUI
import CommonCrypto
import StoreKit

@MainActor
final class BatchAccess: ObservableObject {
    static let shared = BatchAccess()
    @Published private(set) var enabled: Bool
    private let config: [String: String]
    private init() {
        config = Bundle.main.url(forResource: "BatchGate", withExtension: "plist")
            .flatMap { NSDictionary(contentsOf: $0) as? [String: String] } ?? [:]
        enabled = config["verifier", default: ""].isEmpty || UserDefaults.standard.bool(forKey: "batchUnlocked")
    }
    func unlock(_ code: String) async -> Bool {
        if enabled { return true }
        let salt = Self.bytes(config["salt", default: ""])
        let expected = Self.bytes(config["verifier", default: ""])
        let valid = await Task.detached {
            var result = [UInt8](repeating: 0, count: 32)
            let password = Array(code.utf8)
            let status = password.withUnsafeBytes { p in salt.withUnsafeBytes { s in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), p.bindMemory(to: Int8.self).baseAddress, password.count,
                                    s.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 120_000, &result, 32)
            } }
            guard status == kCCSuccess, expected.count == result.count else { return false }
            return zip(expected, result).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
        }.value
        if valid { UserDefaults.standard.set(true, forKey: "batchUnlocked"); enabled = true }
        return valid
    }
    nonisolated private static func bytes(_ hex: String) -> [UInt8] {
        stride(from: 0, to: hex.count, by: 2).compactMap { i in
            let start = hex.index(hex.startIndex, offsetBy: i)
            return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)
        }
    }
}

@MainActor
enum RatingReminder {
    static func saved(video: Bool) {
        let key = video ? "ratingVideos" : "ratingPhotos"
        UserDefaults.standard.set(min(10, UserDefaults.standard.integer(forKey: key) + 1), forKey: key)
    }
    static func requestIfEligible() {
        #if !DEBUG
        let prefs = UserDefaults.standard
        guard Bundle.main.appStoreReceiptURL?.lastPathComponent != "sandboxReceipt",
              !prefs.bool(forKey: "ratingRequested"),
              SharingPlan.eligible(videos: prefs.integer(forKey: "ratingVideos"), photos: prefs.integer(forKey: "ratingPhotos")),
              let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        prefs.set(true, forKey: "ratingRequested")
        SKStoreReviewController.requestReview(in: scene)
        #endif
    }
}
