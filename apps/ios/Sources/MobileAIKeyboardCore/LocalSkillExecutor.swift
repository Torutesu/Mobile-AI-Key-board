import Foundation

/// Closed, deterministic executors available to the keyboard extension.
///
/// A Skill's free-form description is metadata only. It is never interpreted
/// as code or an instruction. Execution is selected solely by an allowlisted
/// operation in the immutable Skill projection (and the projection's digest
/// is rechecked by the snapshot validator before this type is reached).
public enum LocalSkillExecutor {
    public static let supportedOperations = Set(SkillLocalOperation.allCases.map(\.rawValue))

    public static func execute(_ skill: ShortcutSkillProjectionV1, input: String) -> RewriteResult? {
        guard skill.executionRoute == .keyboardLocal,
              let rawOperation = skill.toolSummaries.first(where: { supportedOperations.contains($0.operation) })?.operation,
              let operation = SkillLocalOperation(rawValue: rawOperation) else { return nil }
        return execute(operation: operation, input: input)
    }

    public static func execute(operation: SkillLocalOperation, input: String) -> RewriteResult? {
        let engine = LocalRewriteEngine()
        switch operation {
        case .polite: return engine.politeRewrite(input)
        case .whitespace: return engine.whitespaceRewrite(input)
        case .punctuation, .normalize: return engine.punctuationRewrite(input)
        }
    }
}
