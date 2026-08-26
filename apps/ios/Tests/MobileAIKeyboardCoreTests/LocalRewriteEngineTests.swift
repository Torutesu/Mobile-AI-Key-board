import XCTest
@testable import MobileAIKeyboardCore

final class LocalRewriteEngineTests: XCTestCase {
    func testPoliteRewriteIsDeterministicAndPreservesEntities() {
        let input = "田中さん、2026-08-26に https://example.com でお願いします"
        let result = try! XCTUnwrap(LocalRewriteEngine().politeRewrite(input))
        XCTAssertTrue(result.rewritten.contains("田中さん"))
        XCTAssertTrue(result.rewritten.contains("2026-08-26"))
        XCTAssertTrue(result.rewritten.contains("https://example.com"))
        XCTAssertEqual(result.preservedEntities, ["2026-08-26", "https://example.com"])
        XCTAssertEqual(result, LocalRewriteEngine().politeRewrite(input))
    }

    func testEmptyInputDoesNotProduceResult() {
        XCTAssertNil(LocalRewriteEngine().politeRewrite(" \n"))
    }
}

final class EntityLockingTests: XCTestCase {
    func testFingerprintChangesWhenFieldChanges() {
        let locking = EntityLocking()
        XCTAssertNotEqual(locking.fingerprint("a"), locking.fingerprint("b"))
        XCTAssertEqual(locking.entities(in: "ID 123 and 2026-08-26"), ["ID", "123", "2026-08-26"])
    }
}
