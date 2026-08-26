import Foundation
import XCTest
@testable import MobileAIKeyboardCore

final class ShortcutModelsTests: XCTestCase {
    func testCanonicalJSONUsesNormativeSnakeCaseIDsAndExcludesContent() throws {
        let snapshot = makeSnapshot().withComputedDigest()
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(snapshot)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json["snapshot_id"])
        XCTAssertNotNil(json["layout"] as? [String: Any])
        let layout = try XCTUnwrap(json["layout"] as? [String: Any])
        XCTAssertNotNil(layout["layout_id"])
        let bindings = try XCTUnwrap(json["bindings"] as? [[String: Any]])
        XCTAssertEqual(bindings.first?["binding_id"] as? String, "bind_test")
        XCTAssertNotNil(bindings.first?["trigger_key"] as? [String: Any])
        let skills = try XCTUnwrap(json["skills"] as? [[String: Any]])
        XCTAssertEqual(skills.first?["skill_id"] as? String, "skill_test")
        XCTAssertNil(json["prompt"])
        XCTAssertNil(json["token"])
        XCTAssertNil(json["captured_text"])
    }

    func testValidatorRejectsDuplicatePhysicalKeysAndAllowsOnlyQWERTYCodes() throws {
        let base = makeSnapshot()
        let secondSkill = ShortcutSkillProjectionV1(id: "skill_second", versionID: "sv_second", skillVersion: 1, skillDigest: ShortcutDigest.sha256("second"), name: "Second", description: "local")
        let second = ShortcutBindingV1(id: "bind_second", userID: "user", deviceID: "device", skillID: secondSkill.id, versionID: secondSkill.versionID, skillVersion: 1, skillDigest: secondSkill.skillDigest, keyCode: .keyH, presentation: ShortcutPresentation(iconValue: "wand.and.stars", shortLabel: "Second", accessibilityLabel: "H Second", accessibilityHint: "長押しで実行"))
        let invalid = ShortcutSnapshotV1(id: base.id, generation: 1, deviceID: "device", layout: ShortcutLayoutV1(id: base.layout.id, userID: "user", deviceID: "device", revision: 1, keyBindingIDs: ["bind_test", "bind_second"]), bindings: [base.bindings[0], second], skills: [base.skills[0], secondSkill]).withComputedDigest()
        XCTAssertThrowsError(try ShortcutSnapshotValidator.validate(invalid)) { error in
            XCTAssertEqual(error as? ShortcutValidationError, .duplicateKey)
        }
    }

    func testAppGroupStorePublishesAndReadsOneValidatedGenerationUsingFallback() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("shortcut-store-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppGroupShortcutSnapshotStore(appGroupIdentifier: "group.invalid.test", fallbackDirectoryURL: root)
        let first = makeSnapshot().withComputedDigest()
        try store.publish(first)
        let raw = try XCTUnwrap(try? Data(contentsOf: root.appendingPathComponent("ShortcutSnapshots/shortcut-snapshot.current.json")))
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        do { _ = try decoder.decode(ShortcutSnapshotV1.self, from: raw) } catch { throw error }
        let loaded = try XCTUnwrap(store.loadLastKnownGood())
        XCTAssertEqual(loaded.generation, first.generation)
        XCTAssertEqual(loaded.contentDigest, first.contentDigest)
        XCTAssertFalse(store.isUsingSharedAppGroup)

        let newer = ShortcutSnapshotV1(id: "ss_new", generation: 2, deviceID: "device", layout: ShortcutLayoutV1(id: first.layout.id, userID: "user", deviceID: "device", revision: 2, keyBindingIDs: first.layout.keyBindingIDs), bindings: first.bindings, skills: first.skills).withComputedDigest()
        try store.publish(newer)
        XCTAssertEqual(store.loadLastKnownGood()?.generation, 2)
        XCTAssertThrowsError(try store.publish(newer))
    }

    func testAssignedPrivateProjectionRestoresFromSnapshotAfterRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("shortcut-private-restart-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppGroupShortcutSnapshotStore(appGroupIdentifier: "group.invalid.private", fallbackDirectoryURL: root)
        let digest = ShortcutDigest.sha256("private-demo:v1")
        let skill = ShortcutSkillProjectionV1(
            id: "skill_private_demo",
            versionID: "sv_private_demo_1",
            skillVersion: 1,
            skillDigest: digest,
            name: "Private Demo",
            description: "metadata only",
            inputSources: [.selection],
            toolSummaries: [ShortcutToolSummary(operation: "local.text.normalize", sideEffect: "none")],
            executionRoute: .keyboardLocal
        )
        let binding = ShortcutBindingV1(
            id: "bind_private_demo",
            userID: "user",
            deviceID: "device",
            skillID: skill.id,
            versionID: skill.versionID,
            skillVersion: skill.skillVersion,
            skillDigest: skill.skillDigest,
            keyCode: .keyH,
            presentation: ShortcutPresentation(iconValue: "wand.and.stars", shortLabel: skill.name, accessibilityLabel: "H Private Demo", accessibilityHint: "長押しで実行"),
            executionRoute: .keyboardLocal
        )
        let layout = ShortcutLayoutV1(id: "layout_private_demo", userID: "user", deviceID: "device", revision: 1, keyBindingIDs: [binding.id], paletteBindingIDs: [binding.id])
        let snapshot = ShortcutSnapshotV1(id: "ss_private_demo", generation: 1, deviceID: "device", layout: layout, bindings: [binding], skills: [skill]).withComputedDigest()

        try store.publish(snapshot)
        let restarted = try XCTUnwrap(store.loadLastKnownGood())
        XCTAssertEqual(restarted.bindings.first?.skillID, "skill_private_demo")
        XCTAssertEqual(restarted.skills.first?.versionID, "sv_private_demo_1")
        XCTAssertEqual(restarted.skills.first?.skillDigest, digest)
        XCTAssertEqual(restarted.skills.first?.inputSources, [.selection])
        XCTAssertEqual(restarted.skills.first?.toolSummaries.first?.operation, "local.text.normalize")
    }

    func testValidatorRejectsDuplicateSkillProjectionAndExpiredSnapshot() throws {
        let base = makeSnapshot()
        let duplicate = ShortcutSnapshotV1(id: base.id, generation: 1, deviceID: "device", layout: base.layout, bindings: base.bindings, skills: [base.skills[0], base.skills[0]]).withComputedDigest()
        XCTAssertThrowsError(try ShortcutSnapshotValidator.validate(duplicate)) { error in
            XCTAssertEqual(error as? ShortcutValidationError, .duplicateSkill)
        }
        let expired = ShortcutSnapshotV1(id: base.id, generation: 1, deviceID: "device", layout: base.layout, bindings: base.bindings, skills: base.skills, createdAt: Date(timeIntervalSince1970: 100), expiresAt: Date(timeIntervalSince1970: 200)).withComputedDigest()
        XCTAssertThrowsError(try ShortcutSnapshotValidator.validate(expired, now: Date(timeIntervalSince1970: 300))) { error in
            XCTAssertEqual(error as? ShortcutValidationError, .chronology)
        }
    }

    func testLocalShortcutCaptureRequiresExplicitNonblankSelection() {
        let skill = makeSnapshot().skills[0]
        XCTAssertNil(ShortcutCapturePolicy.localSelection(skill: skill, selectedText: nil))
        XCTAssertNil(ShortcutCapturePolicy.localSelection(skill: skill, selectedText: "  \n"))
        XCTAssertEqual(ShortcutCapturePolicy.localSelection(skill: skill, selectedText: "選択した文章"), "選択した文章")

        let unsafeContextOnly = ShortcutSkillProjectionV1(
            id: skill.id,
            versionID: skill.versionID,
            skillVersion: skill.skillVersion,
            skillDigest: skill.skillDigest,
            name: skill.name,
            description: skill.description,
            inputSources: [.surroundingText],
            outputType: .replaceSelection
        )
        XCTAssertNil(ShortcutCapturePolicy.localSelection(skill: unsafeContextOnly, selectedText: "選択した文章"))
    }

    private func makeSnapshot() -> ShortcutSnapshotV1 {
        let skillDigest = ShortcutDigest.sha256("test-skill:v1")
        let skill = ShortcutSkillProjectionV1(id: "skill_test", versionID: "sv_test", skillVersion: 1, skillDigest: skillDigest, name: "Test", description: "local only")
        let binding = ShortcutBindingV1(id: "bind_test", userID: "user", deviceID: "device", skillID: skill.id, versionID: skill.versionID, skillVersion: 1, skillDigest: skillDigest, keyCode: .keyH, presentation: ShortcutPresentation(iconValue: "wand.and.stars", shortLabel: "Test", accessibilityLabel: "H Test", accessibilityHint: "長押しで実行"))
        let layout = ShortcutLayoutV1(id: "layout_test", userID: "user", deviceID: "device", revision: 1, keyBindingIDs: [binding.id], paletteBindingIDs: [binding.id])
        return ShortcutSnapshotV1(id: "ss_test", generation: 1, deviceID: "device", layout: layout, bindings: [binding], skills: [skill])
    }
}
