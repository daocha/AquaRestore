import SwiftUI
import StoreKit

@MainActor
final class BatchAccess: ObservableObject {
    static let shared = BatchAccess()
    @Published private(set) var photoEnabled: Bool
    @Published private(set) var videoEnabled: Bool
    var referralActive: Bool { !config["referralBackendURL", default: ""].isEmpty }
    var gateConfigured: Bool { referralActive }
    var backendURL: String { config["referralBackendURL", default: ""] }
    private let config: [String: String]
    private let preferences: UserDefaults
    private convenience init() {
        let values = Bundle.main.url(forResource: "BatchGate", withExtension: "plist")
            .flatMap { NSDictionary(contentsOf: $0) as? [String: String] } ?? [:]
        self.init(config: values, preferences: .standard)
    }
    init(config values: [String: String], preferences prefs: UserDefaults) {
        config = values
        preferences = prefs
        let legacy = prefs.bool(forKey: "batchUnlocked")
        let locked = !values["referralBackendURL", default: ""].isEmpty
        photoEnabled = !locked || legacy || prefs.bool(forKey: "batchPhotoUnlocked")
        videoEnabled = !locked || legacy || prefs.bool(forKey: "batchVideoUnlocked")
    }
    func applyReferralUnlocks(photo: Bool, video: Bool) {
        if photo { preferences.set(true, forKey: "batchPhotoUnlocked"); photoEnabled = true }
        if video { preferences.set(true, forKey: "batchVideoUnlocked"); videoEnabled = true }
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
