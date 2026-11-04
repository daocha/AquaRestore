import XCTest
#if canImport(AquaCore)
@testable import AquaCore
#else
@testable import AquaRestore
#endif

final class ReferralIdentityTests: XCTestCase {
    func testStablePackageScopedIdentityMatchesAndroidAndServer() {
        let identity = ReferralIdentity.deviceID(package: "com.aquarestore.app.debug", deviceID: "example-device")
        XCTAssertEqual("c0601a35a34fdbb2e2301d1aa9eaf67449ebe97535273a9be2b9c35eda096e4a", identity)
        XCTAssertEqual("40094aXX1F", ReferralIdentity.code(deviceID: identity))
        XCTAssertNotEqual(identity, ReferralIdentity.deviceID(package: "com.aquarestore.app", deviceID: "example-device"))
        XCTAssertEqual("0000000000", ReferralIdentity.code(deviceID: String(repeating: "0", count: 64)))
        XCTAssertEqual(10, ReferralIdentity.code(deviceID: String(repeating: "f", count: 64)).count)
    }

    func testOnlyWellFormedCodesFromOtherDevicesAreSent() {
        XCTAssertTrue(ReferralIdentity.acceptable("40094aXX1F", ownCode: "0000000001"))
        for code in ["", "short", "40094aXX1F0", "40094aXX1-", "0000000001"] {
            XCTAssertFalse(ReferralIdentity.acceptable(code, ownCode: "0000000001"), code)
        }
    }

    func testInviteKeepsTheCodeOnItsOwnLineInBothLanguages() {
        for chinese in [false, true] {
            let lines = ReferralInvite.message(Strings(chinese: chinese), code: "40094aXX1F").components(separatedBy: "\n")
            XCTAssertTrue(lines.contains("40094aXX1F"))
        }
    }

    func testInviteLinksToTheAppStoreOnceTheListingExists() {
        XCTAssertTrue(ReferralInvite.message(Strings(chinese: false), code: "40094aXX1F", appStoreID: "123").contains("https://apps.apple.com/app/id123"))
        XCTAssertTrue(ReferralInvite.message(Strings(chinese: false), code: "40094aXX1F", appStoreID: nil).contains("search for AquaRestore on the App Store"))
    }

    func testPastingAWholeInviteEntersOnlyTheCode() {
        for chinese in [false, true] {
            let invite = ReferralInvite.message(Strings(chinese: chinese), code: "3n4AaioTlF")
            XCTAssertEqual("3n4AaioTlF", ReferralIdentity.codeIn(invite))
            XCTAssertEqual("3n4AaioTlF", ReferralIdentity.codeIn(invite.replacingOccurrences(of: "\n", with: " ")))
        }
        XCTAssertEqual("3n4AaioTlF", ReferralIdentity.codeIn("Your referral code: 3n4AaioTlF"))
        XCTAssertEqual("3n4AaioTlF", ReferralIdentity.codeIn("3n4AaioTlF"))
        XCTAssertEqual("abc", ReferralIdentity.codeIn("abc"))
        XCTAssertEqual("code: 3n4AaioTlFX", ReferralIdentity.codeIn("code: 3n4AaioTlFX"))
    }
}
