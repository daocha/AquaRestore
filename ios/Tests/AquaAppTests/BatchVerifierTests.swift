import XCTest
@testable import AquaRestore

final class BatchVerifierTests: XCTestCase {
    func testUtf8BuildVerifierAcceptsOnlyCorrectCode() {
        let salt = "000102030405060708090a0b0c0d0e0f"
        let verifier = "384098cfd1872d7aacd8a22b8d0d7a87f898616c6e6a4a2c31c79832ac65afd3"
        XCTAssertTrue(BatchAccess.verify("sample-測試-5678", saltHex: salt, verifierHex: verifier))
        XCTAssertFalse(BatchAccess.verify("wrong", saltHex: salt, verifierHex: verifier))
    }
}
