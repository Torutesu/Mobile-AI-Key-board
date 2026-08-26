import XCTest
@testable import MobileAIKeyboardCore

final class LaunchSettingsTests: XCTestCase {
    private let settingsReducer = KeyboardSettingsReducer()
    private let qualificationReducer = QualificationReducer()

    func testSettingsAreVersionedExtensionSafeAndResetAtBoundary() {
        var state = KeyboardSettingsState.defaultFixture
        state = settingsReducer.reduce(state, .setTheme(.dark))
        state = settingsReducer.reduce(state, .setKeySize(.large))
        state = settingsReducer.reduce(state, .setOneHandedMode(.left))
        state = settingsReducer.reduce(state, .setEnglishWorkflowEnabled(false))
        state = settingsReducer.reduce(state, .setPackEnabled(.absoluteDate, true))
        XCTAssertEqual(state.schemaVersion, KeyboardSettingsState.currentSchemaVersion)
        XCTAssertTrue(state.isEnabled(.absoluteDate))
        XCTAssertFalse(state.englishWorkflowPackEnabled)
        state = settingsReducer.reduce(state, .migrate(fromSchemaVersion: 1))
        XCTAssertEqual(state.schemaVersion, KeyboardSettingsState.currentSchemaVersion)
        state = settingsReducer.reduce(state, .clearBoundary)
        XCTAssertEqual(state.theme, .dark)
        XCTAssertEqual(state.keySize, .large)
        XCTAssertEqual(state.oneHandedMode, .left)
        state = settingsReducer.reduce(state, .reset)
        XCTAssertEqual(state, .defaultFixture)
    }

    func testWorkflowPacksUseLocalDisclosureAndPreserveEntities() {
        let engine = JapaneseWorkflowEngine()
        let input = "田中さんへ https://example.com/path よろしく。金額 123 です。"
        for pack in JapaneseWorkflowPack.allCases {
            let result = try! XCTUnwrap(engine.transform(input, pack: pack))
            XCTAssertEqual(result.original, input)
            XCTAssertTrue(result.sourceDisclosure.contains("端末内"))
            XCTAssertTrue(result.preservedEntities.contains("https://example.com/path"))
            XCTAssertTrue(result.preservedEntities.contains("123"))
            XCTAssertTrue(JapaneseWorkflowEngine().preservesEntities(original: input, rewritten: result.rewritten))
        }
    }

    func testWorkflowEntityTokenDropFailsClosed() {
        let engine = JapaneseWorkflowEngine()
        let input = "田中さんへ https://example.com/path 金額 123"
        XCTAssertFalse(engine.preservesEntities(original: input, rewritten: "田中さんへ https://example.com/ 金額 123"))
        XCTAssertFalse(engine.preservesEntities(original: input, rewritten: "田中さんへ https://example.com/path 金額"))
    }

    func testAbsoluteDateFixtureIsDeterministicWithoutClaimingIME() {
        let reference = Date(timeIntervalSince1970: 1_735_689_600)
        let result = JapaneseWorkflowEngine().transform("今日と明日の予定", pack: .absoluteDate, referenceDate: reference)!
        XCTAssertTrue(result.rewritten.contains("2025年"))
        XCTAssertTrue(result.sourceDisclosure.contains("IME変換"))
    }

    func testQualificationIsContentFreeAndPhysicalStatusRemainsNotProven() {
        var state = QualificationState()
        state = qualificationReducer.reduce(state, .runFixtureForSession(ownerSubject: "fixture-user", now: Date(timeIntervalSince1970: 100), expiresAt: Date(timeIntervalSince1970: 200)))
        XCTAssertTrue(state.fixturePassed)
        XCTAssertEqual(state.measurement?.contentFree, true)
        XCTAssertEqual(state.physicalStatus, .notProven)
        XCTAssertEqual(state.measurement?.sessions, 1_000)
        XCTAssertEqual(state.measurement?.crashes, 0)
        state = qualificationReducer.reduce(state, .clearBoundary)
        XCTAssertNil(state.measurement)
        XCTAssertFalse(state.fixturePassed)
    }

    func testQualificationBudgetBoundariesAndIntegerCrashRate() {
        let budget = QualificationBudget()
        let evaluator = QualificationEvaluator()
        let atBoundary = QualificationMeasurement(coldStartP50Milliseconds: 250, coldStartP95Milliseconds: 400, warmStartP95Milliseconds: 150, keyLatencyP95Milliseconds: 50, sessions: 2_000, crashes: 1)
        XCTAssertTrue(evaluator.evaluate(atBoundary, budget: budget).passed)
        let oneOver = QualificationMeasurement(coldStartP50Milliseconds: 251, coldStartP95Milliseconds: 400, warmStartP95Milliseconds: 150, keyLatencyP95Milliseconds: 50, sessions: 1_000, crashes: 0)
        XCTAssertFalse(evaluator.evaluate(oneOver, budget: budget).passed)
        let broadRateFail = QualificationMeasurement(coldStartP50Milliseconds: 250, coldStartP95Milliseconds: 400, warmStartP95Milliseconds: 150, keyLatencyP95Milliseconds: 50, sessions: 1_000, crashes: 1)
        XCTAssertEqual(broadRateFail.crashFreeBasisPoints, 9_990)
        XCTAssertFalse(evaluator.evaluate(broadRateFail, budget: budget).passed)
        let invalid = QualificationMeasurement(coldStartP50Milliseconds: 0, coldStartP95Milliseconds: 1, warmStartP95Milliseconds: 1, keyLatencyP95Milliseconds: 1, sessions: 0, crashes: 0)
        XCTAssertFalse(evaluator.evaluate(invalid, budget: budget).valid)
    }

    func testQualificationExpiredSessionCannotRunOrRerun() {
        var state = QualificationState()
        let reducer = qualificationReducer
        state = reducer.reduce(state, .runFixtureForSession(ownerSubject: "fixture-user", now: Date(timeIntervalSince1970: 100), expiresAt: Date(timeIntervalSince1970: 200)))
        XCTAssertNotNil(state.measurement)
        state = reducer.reduce(state, .runFixtureForSession(ownerSubject: "fixture-user", now: Date(timeIntervalSince1970: 200), expiresAt: Date(timeIntervalSince1970: 200)))
        XCTAssertEqual(state.measurement?.sessions, 1_000)
        var empty = QualificationState()
        empty = reducer.reduce(empty, .runFixture)
        XCTAssertNil(empty.measurement)
    }

    func testLaunchReadinessIsHonestAndNoCollection() {
        let readiness = LaunchReadinessFixture()
        XCTAssertTrue(readiness.fullAccessEnabled)
        XCTAssertFalse(readiness.networkConnected)
        XCTAssertTrue(readiness.collectedDataTypes.isEmpty)
        XCTAssertTrue(readiness.privacyManifestSourceDeclared)
        XCTAssertFalse(readiness.privacyManifestArchivedVerified)
        XCTAssertTrue(readiness.supportEntry.hasPrefix("local-fixture"))
        XCTAssertTrue(readiness.incidentEntry.hasPrefix("local-fixture"))
    }
}
