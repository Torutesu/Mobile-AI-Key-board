import Foundation
import XCTest
@testable import MobileAIKeyboardCore

private final class MutableTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) { self.value = value }

    func current() -> Date {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func advance(by interval: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        value.addTimeInterval(interval)
    }
}

final class ShortcutModelsTests: XCTestCase {
    func testGenerationGateDoesNotResetForLeaseOnlyBoundaryRenewal() {
        let original = ShortcutAccountBoundaryV1(
            ownerSubjectHash: "sha256:test-owner",
            sessionEpoch: 7,
            active: true,
            expiresAt: Date(timeIntervalSince1970: 1_000)
        ).withComputedDigest()
        let renewed = ShortcutAccountBoundaryV1(
            ownerSubjectHash: original.ownerSubjectHash,
            sessionEpoch: original.sessionEpoch,
            active: true,
            expiresAt: Date(timeIntervalSince1970: 2_000)
        ).withComputedDigest()
        var gate = ShortcutGenerationGate()

        XCTAssertTrue(gate.accepts(generation: 10, boundary: original))
        XCTAssertFalse(gate.accepts(generation: 9, boundary: renewed))
        XCTAssertEqual(gate.floor, 10)
    }

    func testGenerationGateResetsOnlyForNewAuthorityScope() {
        let original = ShortcutAccountBoundaryV1(ownerSubjectHash: "owner-a", sessionEpoch: 7, active: true).withComputedDigest()
        let nextEpoch = ShortcutAccountBoundaryV1(ownerSubjectHash: "owner-a", sessionEpoch: 8, active: true).withComputedDigest()
        var gate = ShortcutGenerationGate()

        XCTAssertTrue(gate.accepts(generation: 10, boundary: original))
        XCTAssertTrue(gate.accepts(generation: 1, boundary: nextEpoch))
        XCTAssertEqual(gate.floor, 1)
    }

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
        _ = try store.activateBoundary(ownerSubjectHash: "sha256:test-owner")
        let first = makeSnapshot().withComputedDigest()
        try store.publish(first)
        let raw = try XCTUnwrap(try? Data(contentsOf: root.appendingPathComponent("ShortcutSnapshots/shortcut-snapshot.current.json")))
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        do { _ = try decoder.decode(ShortcutSnapshotV1.self, from: raw) } catch { throw error }
        let loaded = try XCTUnwrap(store.loadLastKnownGood())
        XCTAssertEqual(loaded.generation, first.generation)
        XCTAssertEqual(loaded.contentDigest, first.contentDigest)
        XCTAssertFalse(store.isUsingSharedAppGroup)

        let newer = ShortcutSnapshotV1(id: "ss_new", generation: 2, userSubjectHash: first.userSubjectHash, deviceID: "device", layout: ShortcutLayoutV1(id: first.layout.id, userID: "user", deviceID: "device", revision: 2, keyBindingIDs: first.layout.keyBindingIDs), bindings: first.bindings, skills: first.skills, policyEpoch: first.policyEpoch).withComputedDigest()
        try store.publish(newer)
        XCTAssertEqual(store.loadLastKnownGood()?.generation, 2)
        XCTAssertThrowsError(try store.publish(newer))
    }

    func testLoaderChoosesHighestValidGenerationWhenSlotsAreReordered() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("shortcut-slot-order-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppGroupShortcutSnapshotStore(appGroupIdentifier: "group.invalid.slot-order", fallbackDirectoryURL: root)
        let boundary = try store.activateBoundary(ownerSubjectHash: "sha256:test-owner")
        let first = makeSnapshot(ownerSubjectHash: boundary.ownerSubjectHash, policyEpoch: boundary.sessionEpoch).withComputedDigest()
        try store.publish(first)
        let second = ShortcutSnapshotV1(id: "ss_second", generation: 2, userSubjectHash: first.userSubjectHash, deviceID: first.deviceID, layout: ShortcutLayoutV1(id: first.layout.id, userID: first.layout.userID, deviceID: first.deviceID, revision: 2, keyBindingIDs: first.layout.keyBindingIDs), bindings: first.bindings, skills: first.skills, policyEpoch: first.policyEpoch).withComputedDigest()
        try store.publish(second)

        let directory = root.appendingPathComponent("ShortcutSnapshots")
        let currentURL = directory.appendingPathComponent("shortcut-snapshot.current.json")
        let previousURL = directory.appendingPathComponent("shortcut-snapshot.previous.json")
        let currentData = try Data(contentsOf: currentURL)
        let previousData = try Data(contentsOf: previousURL)
        try previousData.write(to: currentURL, options: .atomic)
        try currentData.write(to: previousURL, options: .atomic)

        XCTAssertEqual(store.loadLastKnownGood()?.generation, 2)
    }

    func testAssignedPrivateProjectionRestoresFromSnapshotAfterRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("shortcut-private-restart-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppGroupShortcutSnapshotStore(appGroupIdentifier: "group.invalid.private", fallbackDirectoryURL: root)
        let boundary = try store.activateBoundary(ownerSubjectHash: "sha256:private-owner")
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
        let snapshot = ShortcutSnapshotV1(id: "ss_private_demo", generation: 1, userSubjectHash: boundary.ownerSubjectHash, deviceID: "device", layout: layout, bindings: [binding], skills: [skill], policyEpoch: boundary.sessionEpoch).withComputedDigest()

        try store.publish(snapshot)
        let restarted = try XCTUnwrap(store.loadLastKnownGood())
        XCTAssertEqual(restarted.bindings.first?.skillID, "skill_private_demo")
        XCTAssertEqual(restarted.skills.first?.versionID, "sv_private_demo_1")
        XCTAssertEqual(restarted.skills.first?.skillDigest, digest)
        XCTAssertEqual(restarted.skills.first?.inputSources, [.selection])
        XCTAssertEqual(restarted.skills.first?.toolSummaries.first?.operation, "local.text.normalize")
    }

    func testTombstoneRevocationFloorPreventsPreviousExecutableResurrection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("shortcut-revocation-floor-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppGroupShortcutSnapshotStore(appGroupIdentifier: "group.invalid.revocation", fallbackDirectoryURL: root)
        _ = try store.activateBoundary(ownerSubjectHash: "sha256:test-owner")
        try store.publish(makeSnapshot().withComputedDigest())
        try store.publishTombstone(reason: .signedOut, deviceID: "device", userID: "user")

        let directory = root.appendingPathComponent("ShortcutSnapshots")
        try Data("corrupt-current".utf8).write(to: directory.appendingPathComponent("shortcut-snapshot.current.json"), options: .atomic)
        XCTAssertNil(store.loadLastKnownGood(), "the generation-1 executable previous slot must stay revoked")
    }

    func testCorruptRevocationFloorFailsClosed() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("shortcut-corrupt-floor-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppGroupShortcutSnapshotStore(appGroupIdentifier: "group.invalid.floor", fallbackDirectoryURL: root)
        _ = try store.activateBoundary(ownerSubjectHash: "sha256:test-owner")
        try store.publish(makeSnapshot().withComputedDigest())
        let floor = root.appendingPathComponent("ShortcutSnapshots/shortcut-snapshot.revocation-floor.json")
        try FileManager.default.createDirectory(at: floor.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: floor, options: .atomic)
        XCTAssertNil(store.loadLastKnownGood())
    }

    func testValidatorBindsLayoutAndBindingsToDeclaredOwner() throws {
        let base = makeSnapshot()
        let mismatched = ShortcutSnapshotV1(id: base.id, generation: 1, userSubjectHash: "owner-a", deviceID: base.deviceID, layout: base.layout, bindings: base.bindings, skills: base.skills).withComputedDigest()
        XCTAssertThrowsError(try ShortcutSnapshotValidator.validate(mismatched, expectedOwnerSubjectHash: "owner-b")) { error in
            XCTAssertEqual(error as? ShortcutValidationError, .ownerOrDevice)
        }
    }

    func testAccountBoundaryRejectsOwnerAndSessionEpochReplay() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("shortcut-owner-boundary-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppGroupShortcutSnapshotStore(appGroupIdentifier: "group.invalid.owner", fallbackDirectoryURL: root)
        let ownerA = try store.activateBoundary(ownerSubjectHash: "sha256:owner-a")
        let base = makeSnapshot(ownerSubjectHash: ownerA.ownerSubjectHash, policyEpoch: ownerA.sessionEpoch).withComputedDigest()
        try store.publish(base)
        XCTAssertEqual(store.loadLastKnownGood()?.userSubjectHash, "sha256:owner-a")

        let ownerB = try store.activateBoundary(ownerSubjectHash: "sha256:owner-b")
        XCTAssertGreaterThan(ownerB.sessionEpoch, ownerA.sessionEpoch)
        XCTAssertNil(store.loadLastKnownGood(), "owner A data must close immediately when B becomes authoritative")

        _ = try store.deactivateBoundary()
        XCTAssertNil(store.loadLastKnownGood())

        let resumedB = try store.activateBoundary(ownerSubjectHash: "sha256:owner-b")
        XCTAssertGreaterThan(resumedB.sessionEpoch, ownerB.sessionEpoch)
        let staleEpoch = makeSnapshot(ownerSubjectHash: resumedB.ownerSubjectHash, policyEpoch: ownerB.sessionEpoch).withComputedDigest()
        XCTAssertThrowsError(try ShortcutSnapshotValidator.validate(staleEpoch, expectedOwnerSubjectHash: resumedB.ownerSubjectHash, expectedPolicyEpoch: resumedB.sessionEpoch)) { error in
            XCTAssertEqual(error as? ShortcutValidationError, .ownerOrDevice)
        }
    }

    func testCorruptBoundaryCannotResetEpochAndReplaySameOwnerSnapshot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("shortcut-corrupt-boundary-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppGroupShortcutSnapshotStore(appGroupIdentifier: "group.invalid.corrupt-owner", fallbackDirectoryURL: root)
        let original = try store.activateBoundary(ownerSubjectHash: "sha256:owner-a")
        try store.publish(makeSnapshot(ownerSubjectHash: original.ownerSubjectHash, policyEpoch: original.sessionEpoch).withComputedDigest())

        let boundaryURL = root.appendingPathComponent("ShortcutSnapshots/shortcut-account-boundary.current.json")
        try Data("{}".utf8).write(to: boundaryURL, options: .atomic)
        XCTAssertNil(store.loadLastKnownGood())

        let recovered = try store.activateBoundary(ownerSubjectHash: "sha256:owner-a")
        XCTAssertGreaterThan(recovered.sessionEpoch, original.sessionEpoch)
        XCTAssertNil(store.loadLastKnownGood(), "the old same-owner epoch must not reopen after authority corruption")
    }

    func testExpiredAccountBoundaryFailsClosedWithoutDeletingSnapshot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("shortcut-expired-boundary-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppGroupShortcutSnapshotStore(appGroupIdentifier: "group.invalid.expired-owner", fallbackDirectoryURL: root)
        let active = try store.activateBoundary(ownerSubjectHash: "sha256:owner-a")
        try store.publish(makeSnapshot(ownerSubjectHash: active.ownerSubjectHash, policyEpoch: active.sessionEpoch).withComputedDigest())

        let expired = ShortcutAccountBoundaryV1(ownerSubjectHash: active.ownerSubjectHash, sessionEpoch: active.sessionEpoch, active: true, expiresAt: Date(timeIntervalSince1970: 100)).withComputedDigest()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try container.encode(formatter.string(from: date))
        }
        let boundaryURL = root.appendingPathComponent("ShortcutSnapshots/shortcut-account-boundary.current.json")
        try encoder.encode(expired).write(to: boundaryURL, options: .atomic)

        XCTAssertNil(store.loadActiveBoundary())
        XCTAssertNil(store.loadLastKnownGood(), "an expired host lease must close extension execution")
    }

    func testMaximumRevocationFloorFailsClosedWithoutIntegerOverflow() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("shortcut-max-floor-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppGroupShortcutSnapshotStore(appGroupIdentifier: "group.invalid.max-floor", fallbackDirectoryURL: root)
        _ = try store.activateBoundary(ownerSubjectHash: "sha256:owner-a")
        let generation = ShortcutSnapshotValidator.maxMonotonicValue
        let floor: [String: Any] = [
            "schema_version": 1,
            "generation": generation,
            "content_digest": ShortcutDigest.sha256("revocation-floor-v1:\(generation)")
        ]
        let floorURL = root.appendingPathComponent("ShortcutSnapshots/shortcut-snapshot.revocation-floor.json")
        try FileManager.default.createDirectory(at: floorURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: floor, options: [.sortedKeys]).write(to: floorURL, options: .atomic)

        XCTAssertNil(store.loadLastKnownGood())
        XCTAssertThrowsError(try store.publishTombstone(reason: .signedOut, deviceID: "device", userID: "user")) { error in
            XCTAssertEqual(error as? ShortcutStoreError, .generationConflict)
        }
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

    func testNativeFailureCircuitBreakerDisablesOnlyExactVersionAndCorruptionFailsSkillsClosed() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("native-failure-store-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshotStore = AppGroupShortcutSnapshotStore(appGroupIdentifier: "group.invalid.native-failure", fallbackDirectoryURL: root)
        let boundary = try snapshotStore.activateBoundary(ownerSubjectHash: "sha256:native-failure-owner")
        let clock = MutableTestClock(Date(timeIntervalSince1970: 1_000))
        let store = AppGroupNativeSkillFailureStore(
            appGroupIdentifier: "group.invalid.native-failure",
            fallbackDirectoryURL: root,
            now: { clock.current() }
        )
        let first = makeSnapshot(ownerSubjectHash: boundary.ownerSubjectHash, policyEpoch: boundary.sessionEpoch).bindings[0]
        let secondDigest = ShortcutDigest.sha256("second-native-skill")
        let second = ShortcutBindingV1(
            id: "bind_second_native",
            userID: "user",
            deviceID: "device",
            skillID: "skill_second_native",
            versionID: "sv_second_native",
            skillVersion: 1,
            skillDigest: secondDigest,
            keyCode: .keyM,
            presentation: ShortcutPresentation(iconValue: "wand.and.stars", shortLabel: "Second", accessibilityLabel: "M Second", accessibilityHint: "長押しで実行")
        )

        XCTAssertEqual(try store.recordFailure(for: first, boundary: boundary), .allowed)
        XCTAssertEqual(try store.recordFailure(for: first, boundary: boundary), .allowed)
        XCTAssertEqual(try store.recordFailure(for: first, boundary: boundary), .disabled)
        XCTAssertEqual(store.decision(for: first, boundary: boundary), .disabled)
        XCTAssertEqual(store.decision(for: second, boundary: boundary), .allowed)
        clock.advance(by: AppGroupNativeSkillFailureStore.failureWindow + 1)
        XCTAssertEqual(store.decision(for: first, boundary: boundary), .allowed)
        XCTAssertEqual(try store.recordFailure(for: first, boundary: boundary), .allowed)

        let file = root.appendingPathComponent("NativeSkillFailures/native-skill-failures.current.json")
        try Data("corrupt".utf8).write(to: file, options: .atomic)
        XCTAssertEqual(store.decision(for: first, boundary: boundary), .storeUnavailable)
        XCTAssertEqual(store.decision(for: second, boundary: boundary), .storeUnavailable)
    }

    func testNativeFailureWriteFailureLatchesExactSkillClosed() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("native-failure-write-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshotStore = AppGroupShortcutSnapshotStore(appGroupIdentifier: "group.invalid.native-failure-write", fallbackDirectoryURL: root)
        let boundary = try snapshotStore.activateBoundary(ownerSubjectHash: "sha256:native-write-failure-owner")
        let store = AppGroupNativeSkillFailureStore(
            appGroupIdentifier: "group.invalid.native-failure-write",
            fallbackDirectoryURL: root,
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        let binding = makeSnapshot(ownerSubjectHash: boundary.ownerSubjectHash, policyEpoch: boundary.sessionEpoch).bindings[0]

        store.failWritesForTesting()
        XCTAssertThrowsError(try store.recordFailure(for: binding, boundary: boundary))
        XCTAssertEqual(store.decision(for: binding, boundary: boundary), .storeUnavailable)
    }

    private func makeSnapshot(ownerSubjectHash: String? = "sha256:test-owner", policyEpoch: Int = 1) -> ShortcutSnapshotV1 {
        let skillDigest = ShortcutDigest.sha256("test-skill:v1")
        let skill = ShortcutSkillProjectionV1(id: "skill_test", versionID: "sv_test", skillVersion: 1, skillDigest: skillDigest, name: "Test", description: "local only")
        let binding = ShortcutBindingV1(id: "bind_test", userID: "user", deviceID: "device", skillID: skill.id, versionID: skill.versionID, skillVersion: 1, skillDigest: skillDigest, keyCode: .keyH, presentation: ShortcutPresentation(iconValue: "wand.and.stars", shortLabel: "Test", accessibilityLabel: "H Test", accessibilityHint: "長押しで実行"))
        let layout = ShortcutLayoutV1(id: "layout_test", userID: "user", deviceID: "device", revision: 1, keyBindingIDs: [binding.id], paletteBindingIDs: [binding.id])
        return ShortcutSnapshotV1(id: "ss_test", generation: 1, userSubjectHash: ownerSubjectHash, deviceID: "device", layout: layout, bindings: [binding], skills: [skill], policyEpoch: policyEpoch)
    }
}
