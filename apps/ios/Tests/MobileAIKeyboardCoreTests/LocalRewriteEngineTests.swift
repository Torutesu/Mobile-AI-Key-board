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

    func testWhitespaceRewriteKeepsParagraphsAndProtectedEntities() throws {
        let input = "https://example.com   を確認  \n \n \n田中さん   よろしく"
        let result = try XCTUnwrap(LocalRewriteEngine().whitespaceRewrite(input))
        XCTAssertEqual(result.rewritten, "https://example.com を確認\n\n田中さん よろしく")
        XCTAssertTrue(result.preservedEntities.contains("https://example.com"))
        XCTAssertTrue(result.preservedEntities.contains("田中さん"))
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

    func testSelectionFingerprintBindsIdenticalTextToItsContext() {
        let locking = EntityLocking()
        let captured = locking.selectionFingerprint(selectedText: "foo", before: "first ", after: " end")
        XCTAssertEqual(captured, locking.selectionFingerprint(selectedText: "foo", before: "first ", after: " end"))
        XCTAssertNotEqual(captured, locking.selectionFingerprint(selectedText: "foo", before: "second ", after: " end"))
        XCTAssertNotEqual(captured, locking.selectionFingerprint(selectedText: "foo", before: "first ", after: " changed"))
    }

    func testSelectionFingerprintBoundsRemoteContextButKeepsNearestCharacters() {
        let locking = EntityLocking()
        let remotePrefixA = String(repeating: "a", count: 40) + "nearest"
        let remotePrefixB = String(repeating: "b", count: 40) + "nearest"
        XCTAssertEqual(
            locking.selectionFingerprint(selectedText: "x", before: remotePrefixA, after: "tail", contextLimit: 7),
            locking.selectionFingerprint(selectedText: "x", before: remotePrefixB, after: "tail", contextLimit: 7)
        )
    }
}
