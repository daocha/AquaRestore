import XCTest
@testable import AquaRestore

final class BatchVerifierTests: XCTestCase {
    func testUtf8BuildVerifierAcceptsOnlyCorrectCode() {
        let salt = "000102030405060708090a0b0c0d0e0f"
        let verifier = "384098cfd1872d7aacd8a22b8d0d7a87f898616c6e6a4a2c31c79832ac65afd3"
        XCTAssertTrue(BatchAccess.verify("sample-測試-5678", saltHex: salt, verifierHex: verifier))
        XCTAssertFalse(BatchAccess.verify("wrong", saltHex: salt, verifierHex: verifier))
    }
    @MainActor
    func testUnlocksPersistIndependentlyAndLegacyAccessSurvives() async throws {
        let suite = "batch-access-\(UUID().uuidString)"
        let prefs = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { prefs.removePersistentDomain(forName: suite) }
        let config = ["photoSalt": "000102030405060708090a0b0c0d0e0f",
                      "photoVerifier": "384098cfd1872d7aacd8a22b8d0d7a87f898616c6e6a4a2c31c79832ac65afd3",
                      "videoSalt": "000102030405060708090a0b0c0d0e0f",
                      "videoVerifier": "384098cfd1872d7aacd8a22b8d0d7a87f898616c6e6a4a2c31c79832ac65afd3"]
        let access = BatchAccess(config: config, preferences: prefs)
        XCTAssertFalse(access.photoEnabled)
        XCTAssertFalse(access.videoEnabled)
        let photoResult = await access.unlock("sample-測試-5678")
        XCTAssertTrue(photoResult)
        XCTAssertTrue(access.photoEnabled)
        XCTAssertFalse(access.videoEnabled)
        let wrongVideo = await access.unlock("wrong", video: true)
        XCTAssertFalse(wrongVideo)
        let restored = BatchAccess(config: config, preferences: prefs)
        XCTAssertTrue(restored.photoEnabled)
        XCTAssertFalse(restored.videoEnabled)
        let videoResult = await restored.unlock("sample-測試-5678", video: true)
        XCTAssertTrue(videoResult)
        XCTAssertTrue(BatchAccess(config: config, preferences: prefs).videoEnabled)
        prefs.removePersistentDomain(forName: suite)
        prefs.set(true, forKey: "batchUnlocked")
        let legacy = BatchAccess(config: config, preferences: prefs)
        XCTAssertTrue(legacy.photoEnabled)
        XCTAssertTrue(legacy.videoEnabled)
    }

    @MainActor
    func testMissingPhotoCodeEnablesOnlyPhotos() throws {
        let suite = "batch-access-\(UUID().uuidString)"
        let prefs = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { prefs.removePersistentDomain(forName: suite) }
        let access = BatchAccess(config: ["videoVerifier": "configured"], preferences: prefs)
        XCTAssertTrue(access.photoEnabled)
        XCTAssertFalse(access.videoEnabled)
    }
    func testDebugPackagedVerifiersMatchBundleIdentifier() throws {
        #if DEBUG
        let url = try XCTUnwrap(Bundle.main.url(forResource: "BatchGate", withExtension: "plist"))
        let config = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
        let identifier = try XCTUnwrap(Bundle.main.bundleIdentifier)
        for feature in ["photo", "video"] {
            XCTAssertTrue(BatchAccess.verify(identifier, saltHex: try XCTUnwrap(config[feature + "Salt"]),
                                            verifierHex: try XCTUnwrap(config[feature + "Verifier"])))
        }
        #endif
    }
}
