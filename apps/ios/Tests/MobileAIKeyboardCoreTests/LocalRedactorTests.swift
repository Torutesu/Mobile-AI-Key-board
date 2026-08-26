import XCTest
@testable import MobileAIKeyboardCore

final class LocalRedactorTests: XCTestCase {
    func testSecretsAreRedactedAndBlockedBeforeProcessing() {
        let result = LocalRedactor().redact("token sk_test_1234567890123456 and code 123456")
        XCTAssertTrue(result.blocked)
        XCTAssertFalse(result.redacted.contains("sk_test_1234567890123456"))
        XCTAssertFalse(result.redacted.contains("123456"))
        XCTAssertGreaterThanOrEqual(result.detected.count, 2)
    }


    func testCommonHyphenatedAndProviderKeysAreBlocked() {
        let openAIStyle = "sk-" + "fixture1234567890abcdef"
        let githubStyle = "ghp_" + "fixture1234567890abcdef"
        let result = LocalRedactor().redact("\(openAIStyle) and \(githubStyle)")
        XCTAssertTrue(result.blocked)
        XCTAssertFalse(result.redacted.contains(openAIStyle))
        XCTAssertFalse(result.redacted.contains(githubStyle))
    }
}
