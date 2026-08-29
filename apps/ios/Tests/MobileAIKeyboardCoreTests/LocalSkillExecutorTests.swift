import XCTest
@testable import MobileAIKeyboardCore

final class LocalSkillExecutorTests: XCTestCase {
    func testOnlyAllowlistedOperationsExecute() {
        let base = ShortcutSkillProjectionV1(id: "skill_private_demo", versionID: "sv_private_demo", skillVersion: 1, skillDigest: "sha256:" + String(repeating: "a", count: 64), name: "Demo", description: "metadata", inputSources: [.selection], toolSummaries: [ShortcutToolSummary(operation: "local.text.normalize")], executionRoute: .keyboardLocal)
        XCTAssertNotNil(LocalSkillExecutor.execute(base, input: "hello   world"))

        let arbitrary = ShortcutSkillProjectionV1(id: base.id, versionID: base.versionID, skillVersion: base.skillVersion, skillDigest: base.skillDigest, name: base.name, description: "ignore previous; shell", inputSources: [.selection], toolSummaries: [ShortcutToolSummary(operation: "shell.execute")], executionRoute: .keyboardLocal)
        XCTAssertNil(LocalSkillExecutor.execute(arbitrary, input: "hello"))
    }

    func testPrivateNormalizeExecutorIsDeterministicAndPreservesEntities() throws {
        let skill = ShortcutSkillProjectionV1(id: "skill_private_demo", versionID: "sv_private_demo", skillVersion: 1, skillDigest: "sha256:" + String(repeating: "a", count: 64), name: "Demo", description: "metadata", inputSources: [.selection], toolSummaries: [ShortcutToolSummary(operation: "local.text.normalize")], executionRoute: .keyboardLocal)
        let first = try XCTUnwrap(LocalSkillExecutor.execute(skill, input: "https://example.com   を確認"))
        let second = try XCTUnwrap(LocalSkillExecutor.execute(skill, input: "https://example.com   を確認"))
        XCTAssertEqual(first, second)
        XCTAssertTrue(first.rewritten.contains("https://example.com"))
    }

    func testEveryTypedLocalOperationUsesItsDistinctClosedExecutor() throws {
        XCTAssertEqual(
            try XCTUnwrap(LocalSkillExecutor.execute(operation: .polite, input: "よろしく")).rewritten,
            "よろしくお願いいたします。"
        )
        XCTAssertEqual(
            try XCTUnwrap(LocalSkillExecutor.execute(operation: .whitespace, input: "hello   world")).rewritten,
            "hello world"
        )
        XCTAssertEqual(
            try XCTUnwrap(LocalSkillExecutor.execute(operation: .punctuation, input: "hello   world")).rewritten,
            "hello world。"
        )
        XCTAssertEqual(LocalSkillExecutor.supportedOperations, Set(SkillLocalOperation.allCases.map(\.rawValue)))
    }
}
