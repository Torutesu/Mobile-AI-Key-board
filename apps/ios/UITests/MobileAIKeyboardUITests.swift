import XCTest

@MainActor
final class MobileAIKeyboardUITests: XCTestCase {
    func testOnboardingDeliversValueBeforeRequestingKeyboardAccess() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding-qa"]
        app.launch()

        XCTAssertTrue(app.staticTexts["どこで書いていても、\nAIを一打で。"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["試すだけなら、アクセス許可は不要です"].exists)
        app.buttons["onboarding-start"].tap()

        XCTAssertTrue(app.staticTexts["許可の前に、体験する"].waitForExistence(timeout: 3))
        app.buttons["onboarding-refine"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["onboarding-refined-result"].waitForExistence(timeout: 3))
        app.buttons["onboarding-continue-to-access"].tap()

        XCTAssertTrue(app.staticTexts["キーボードを有効にする"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["onboarding-open-settings"].isHittable)
        XCTAssertTrue(app.buttons["onboarding-access-details"].isHittable)
    }

    func testFullAccessExplanationIsPlainLanguageAndReversible() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding-access-qa"]
        app.launch()

        let details = app.buttons["onboarding-access-details"]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        details.tap()

        XCTAssertTrue(app.navigationBars["フルアクセスについて"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["勝手に送信しません"].exists)
        XCTAssertTrue(app.staticTexts["パスワード欄では停止"].exists)
        XCTAssertTrue(app.staticTexts["いつでも解除できます"].exists)
        XCTAssertTrue(app.buttons["閉じる"].isHittable)
    }

    func testTriggerKeySheetAtAccessibilityTextSizeKeepsAllKeysAndSafetyActionsReachable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-trigger-key-sheet-qa", "-ui-test-reset", "-accessibility-text-size-qa"]
        app.launch()

        XCTAssertTrue(app.staticTexts["キーを選ぶ"].waitForExistence(timeout: 5))
        let triggerKeys = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'trigger-key-'"))
        XCTAssertEqual(triggerKeys.count, 26)
        app.buttons["trigger-key-q"].tap()

        let runFixture = app.buttons["run-local-fixture"]
        XCTAssertTrue(runFixture.waitForExistence(timeout: 3))
        XCTAssertTrue(runFixture.isHittable)
        runFixture.tap()
        XCTAssertTrue(app.descendants(matching: .any)["fixture-success"].waitForExistence(timeout: 3))

        let save = app.buttons["save-skill-key"]
        XCTAssertTrue(save.isHittable)
        save.tap()
        XCTAssertTrue(app.alerts["割り当てを保存しました"].waitForExistence(timeout: 3))
    }

    func testBuilderAddAndAssignPrivateSkillWithoutLosingOrdinaryInputBoundary() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-skill-builder-qa", "-ui-test-reset"]
        app.launch()
        let start = app.buttons["コードを書かずにSkill作成を開始"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        try fill(app.textViews["達成したい結果"], with: "選択文を読みやすく整える")
        try fill(app.textFields["Skill名"], with: "UI Test Skill")
        try fill(app.textViews["plain description"], with: "端末内で選択文を整える")
        try fill(app.textFields["テスト入力例"], with: "hello   world")
        try fill(app.textFields["期待する出力例"], with: "hello world")

        let validate = app.buttons["schema / policy / static検証"]
        XCTAssertTrue(validate.waitForExistence(timeout: 3))
        validate.tap()
        let beginTest = app.buttons["fixture testを開始"]
        XCTAssertTrue(beginTest.waitForExistence(timeout: 3))
        beginTest.tap()
        let finishTest = app.buttons["fixture testを完了"]
        XCTAssertTrue(finishTest.waitForExistence(timeout: 3))
        finishTest.tap()
        let plan = app.buttons["private v1 deploy planを作成"]
        XCTAssertTrue(plan.waitForExistence(timeout: 3))
        plan.tap()
        let confirm = app.buttons["confirm-private-deploy"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()

        let add = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'add-private-'")).firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.tap()
        XCTAssertTrue(app.alerts["キーボード候補に追加しました"].waitForExistence(timeout: 3))
        app.alerts["キーボード候補に追加しました"].buttons["閉じる"].tap()

        let openSkillKeys = app.buttons["open-skill-keys"]
        XCTAssertTrue(openSkillKeys.waitForExistence(timeout: 3))
        openSkillKeys.tap()
        XCTAssertTrue(app.staticTexts["タップ = 通常入力 / 長押し = Skill"].waitForExistence(timeout: 3))

        let privateOption = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'skill-option-skill_private_'")).firstMatch
        XCTAssertTrue(privateOption.waitForExistence(timeout: 3))
        privateOption.tap()
        XCTAssertTrue(app.staticTexts["キーを選ぶ"].waitForExistence(timeout: 3))
        app.buttons["trigger-key-h"].tap()
        let runFixture = app.buttons["run-local-fixture"]
        XCTAssertTrue(runFixture.waitForExistence(timeout: 3))
        XCTAssertTrue(runFixture.isHittable)
        runFixture.tap()
        XCTAssertTrue(app.descendants(matching: .any)["fixture-success"].waitForExistence(timeout: 3))
        app.buttons["save-skill-key"].tap()
        XCTAssertTrue(app.alerts["割り当てを保存しました"].waitForExistence(timeout: 3))
    }

    private func fill(_ element: XCUIElement, with value: String, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertTrue(element.waitForExistence(timeout: 3), file: file, line: line)
        element.tap()
        element.typeText(value)
    }
}
