import XCTest
@testable import AquaRestore

final class BatchVerifierTests: XCTestCase {
    @MainActor
    func testReferralSwitchLocksBothAndGrantsPersistWithoutRevocation() throws {
        let suite = "batch-referral-\(UUID().uuidString)"
        let prefs = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { prefs.removePersistentDomain(forName: suite) }
        let config = ["referralBackendURL": "https://example.org"]
        let access = BatchAccess(config: config, preferences: prefs)
        XCTAssertTrue(access.referralActive)
        XCTAssertFalse(access.photoEnabled)
        XCTAssertFalse(access.videoEnabled)
        access.applyReferralUnlocks(photo: true, video: false)
        access.applyReferralUnlocks(photo: false, video: false)
        let restored = BatchAccess(config: config, preferences: prefs)
        XCTAssertTrue(restored.photoEnabled)
        XCTAssertFalse(restored.videoEnabled)
        restored.applyReferralUnlocks(photo: false, video: true)
        XCTAssertTrue(BatchAccess(config: config, preferences: prefs).videoEnabled)
        let disabledCampaign = BatchAccess(config: [:], preferences: prefs)
        XCTAssertFalse(disabledCampaign.referralActive)
        XCTAssertFalse(disabledCampaign.gateConfigured)
    }
    @MainActor
    func testNoBackendOpensBothAndLegacyGrantsSurviveMigration() throws {
        let suite = "batch-access-\(UUID().uuidString)"
        let prefs = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { prefs.removePersistentDomain(forName: suite) }
        let open = BatchAccess(config: [:], preferences: prefs)
        XCTAssertTrue(open.photoEnabled)
        XCTAssertTrue(open.videoEnabled)
        XCTAssertFalse(open.gateConfigured)
        prefs.set(true, forKey: "batchUnlocked")
        let legacy = BatchAccess(config: ["referralBackendURL": "https://example.org"], preferences: prefs)
        XCTAssertTrue(legacy.photoEnabled)
        XCTAssertTrue(legacy.videoEnabled)
    }
}
