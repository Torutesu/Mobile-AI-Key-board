import XCTest
@testable import MobileAIKeyboardCore

final class LocalRewriteEngineTests: XCTestCase {
    func testPoliteRewriteIsDeterministicAndPreservesEntities() {
        let input = "田中さん、2026-08-26に https://example.com でお願いします"
        let result = try! XCTUnwrap(LocalRewriteEngine().politeRewrite(input))
        XCTAssertTrue(result.rewritten.contains("田中さん"))
        XCTAssertTrue(result.rewritten.contains("2026-08-26"))
        XCTAssertTrue(result.rewritten.contains("https://example.com"))
        XCTAssertEqual(result.preservedEntities, ["田中さん", "2026-08-26", "https://example.com"])
        XCTAssertEqual(result, LocalRewriteEngine().politeRewrite(input))
    }

    func testMaskRestoreProtectsEntitiesContainingRewriteWords() {
        let input = "https://example.com/よろしく?to=お願いします test@example.com 2026-08-26 @よろしく ID123 田中さん、よろしく"
        let result = try! XCTUnwrap(LocalRewriteEngine().politeRewrite(input))
        XCTAssertTrue(result.rewritten.contains("https://example.com/よろしく?to=お願いします"))
        XCTAssertTrue(result.rewritten.contains("test@example.com"))
        XCTAssertTrue(result.rewritten.contains("2026-08-26"))
        XCTAssertTrue(result.rewritten.contains("@よろしく"))
        XCTAssertTrue(result.rewritten.contains("ID123"))
        XCTAssertTrue(result.rewritten.contains("田中さん"))
        XCTAssertTrue(result.rewritten.contains("よろしくお願いいたします"))
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

    func testHighConfidenceJapaneseHonorificAndHandleEntities() {
        let values = EntityLocking().entities(in: "@alice 田中さん 佐藤様 ID 123")
        XCTAssertTrue(values.contains("@alice"))
        XCTAssertTrue(values.contains("田中さん"))
        XCTAssertTrue(values.contains("佐藤様"))
        XCTAssertTrue(values.contains("ID"))
        XCTAssertTrue(values.contains("123"))
    }
}
