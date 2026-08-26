import XCTest
@testable import MobileAIKeyboardCore

final class ShortcutRegistryMutationTests: XCTestCase {
    func testAssignRejectsOccupiedKeyWithoutChangingInput() throws {
        let existing = binding(id: "bind_existing", skillID: "skill_existing", key: .keyH)
        let candidate = binding(id: "bind_candidate", skillID: "skill_candidate", key: .keyH)
        let before = [existing]

        XCTAssertThrowsError(try ShortcutRegistryMutation.assign(bindings: before, binding: candidate)) { error in
            XCTAssertEqual(error as? ShortcutRegistryMutationError, .keyOccupied(.keyH))
        }
        XCTAssertEqual(before, [existing])
    }

    func testReplaceExplicitlyRemovesOnlyTheConflictingBinding() throws {
        let existing = binding(id: "bind_existing", skillID: "skill_existing", key: .keyH)
        let other = binding(id: "bind_other", skillID: "skill_other", key: .keyM)
        let candidate = binding(id: "bind_candidate", skillID: "skill_candidate", key: .keyH)

        let result = try ShortcutRegistryMutation.replace(bindings: [existing, other], binding: candidate)
        XCTAssertEqual(result.map(\.id), ["bind_other", "bind_candidate"])
        XCTAssertEqual(result.last?.keyCode, .keyH)
    }

    func testSwapMovesBothBindingsAndRefreshesPresentationKey() throws {
        let source = binding(id: "bind_source", skillID: "skill_source", key: .keyH)
        let destination = binding(id: "bind_destination", skillID: "skill_destination", key: .keyM)

        let result = try ShortcutRegistryMutation.swap(bindings: [source, destination], bindingID: source.id, to: .keyM)
        XCTAssertEqual(result[0].keyCode, .keyM)
        XCTAssertEqual(result[1].keyCode, .keyH)
        XCTAssertTrue(result[0].presentation.accessibilityLabel.hasPrefix("M"))
        XCTAssertTrue(result[1].presentation.accessibilityLabel.hasPrefix("H"))
    }

    func testMoveAndReplaceRequireAnActualConflict() throws {
        let source = binding(id: "bind_source", skillID: "skill_source", key: .keyH)
        let before = [source]

        XCTAssertThrowsError(try ShortcutRegistryMutation.replace(bindings: before, binding: binding(id: "bind_new", skillID: "skill_new", key: .keyM))) { error in
            XCTAssertEqual(error as? ShortcutRegistryMutationError, .keyIsAvailable(.keyM))
        }
        XCTAssertThrowsError(try ShortcutRegistryMutation.swap(bindings: before, bindingID: source.id, to: .keyM)) { error in
            XCTAssertEqual(error as? ShortcutRegistryMutationError, .keyIsAvailable(.keyM))
        }
        XCTAssertEqual(before, [source])
    }

    func testHostHandoffCannotEnterTheMutationPath() throws {
        let hostBinding = binding(id: "bind_host", skillID: "skill_host", key: .keyH, route: .hostHandoff)
        XCTAssertThrowsError(try ShortcutRegistryMutation.assign(bindings: [], binding: hostBinding)) { error in
            XCTAssertEqual(error as? ShortcutRegistryMutationError, .hostHandoffUnavailable)
        }
    }

    private func binding(id: String, skillID: String, key: ShortcutKeyCode, route: ShortcutExecutionRoute = .keyboardLocal) -> ShortcutBindingV1 {
        let digest = ShortcutDigest.sha256(skillID)
        return ShortcutBindingV1(
            id: id,
            userID: "user",
            deviceID: "device",
            skillID: skillID,
            versionID: "version_\(skillID)",
            skillVersion: 1,
            skillDigest: digest,
            keyCode: key,
            presentation: ShortcutPresentation(iconValue: "wand.and.stars", shortLabel: skillID, accessibilityLabel: "\(key.displayLabel)、\(skillID)", accessibilityHint: "長押しで実行"),
            executionRoute: route
        )
    }
}
