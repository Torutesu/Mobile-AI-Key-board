import Foundation

/// Closed, deterministic executors available to the keyboard extension.
///
/// A Skill's free-form description is metadata only. It is never interpreted
/// as code or an instruction. Execution is selected solely by an allowlisted
/// operation in the immutable Skill projection (and the projection's digest
/// is rechecked by the snapshot validator before this type is reached).
public enum LocalSkillExecutor {
    public static let supportedOperations: Set<String> = [
        "local.text.normalize",
        "local.text.polite",
        "local.text.punctuation"
    ]

    public static func execute(_ skill: ShortcutSkillProjectionV1, input: String) -> RewriteResult? {
        guard skill.executionRoute == .keyboardLocal,
              let operation = skill.toolSummaries.first(where: { supportedOperations.contains($0.operation) })?.operation else { return nil }
        let engine = LocalRewriteEngine()
        switch operation {
        case "local.text.polite": return engine.politeRewrite(input)
        case "local.text.punctuation", "local.text.normalize": return engine.punctuationRewrite(input)
        default: return nil
        }
    }
}
