import XCTest
@testable import MobileAIKeyboardCore

final class SensitiveFieldPolicyTests: XCTestCase {
    let policy = SensitiveFieldPolicy()

    func testSecureTextEntryBlocksAI() {
        let context = FieldSecurityContext(isSecureTextEntry: true)
        XCTAssertEqual(policy.lockReason(for: context), .secureField)
        XCTAssertFalse(policy.allowsAI(for: context))
    }

    func testPasswordAndOneTimeCodeAreBlocked() {
        XCTAssertEqual(policy.lockReason(for: FieldSecurityContext(textContentType: "password")), .secureField)
        XCTAssertEqual(policy.lockReason(for: FieldSecurityContext(textContentType: "oneTimeCode")), .secureField)
        XCTAssertEqual(policy.lockReason(for: FieldSecurityContext(textContentType: "creditCardNumber")), .secureField)
    }

    func testOrdinaryTextRemainsAvailable() {
        XCTAssertNil(policy.lockReason(for: FieldSecurityContext(textContentType: "plainText")))
        XCTAssertTrue(policy.allowsAI(for: FieldSecurityContext(textContentType: "plainText")))
    }
}
