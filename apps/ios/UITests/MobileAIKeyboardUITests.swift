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

        app.buttons["toggle-local-fixture"].tap()
        let runFixture = app.buttons["run-local-fixture"]
        XCTAssertTrue(runFixture.waitForExistence(timeout: 3))
        app.scrollViews["trigger-key-scroll"].swipeUp()
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
        let request = app.textViews["skill-request"]
        XCTAssertTrue(request.waitForExistence(timeout: 5))
        request.tap()
        request.typeText("選択文を読みやすく整える")

        let create = app.buttons["create-skill-preview"]
        XCTAssertTrue(create.isHittable)
        create.tap()
        XCTAssertTrue(app.descendants(matching: .any)["skill-preview-result"].waitForExistence(timeout: 3))

        let install = app.buttons["install-created-skill"]
        XCTAssertTrue(install.isHittable)
        install.tap()
        XCTAssertTrue(app.staticTexts["キーを選ぶ"].waitForExistence(timeout: 3))
        app.buttons["trigger-key-h"].tap()
        // A successful builder preview is authoritative, so assignment does
        // not force a second duplicate fixture run.
        XCTAssertTrue(app.buttons["save-skill-key"].isHittable)
        app.buttons["save-skill-key"].tap()
        XCTAssertTrue(app.alerts["割り当てを保存しました"].waitForExistence(timeout: 3))
        app.alerts["割り当てを保存しました"].buttons["完了"].tap()

        app.terminate()
        app.launchArguments = ["-skill-keys-qa"]
        app.launch()
        XCTAssertTrue(app.buttons["assigned-skill-key-h"].waitForExistence(timeout: 5))
    }

    func testBuilderRejectsUnsupportedIntentInsteadOfPretendingToExecute() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-skill-builder-qa", "-ui-test-reset"]
        app.launch()

        let request = app.textViews["skill-request"]
        XCTAssertTrue(request.waitForExistence(timeout: 5))
        request.tap()
        request.typeText("会議を要約してSlackに送信する")
        app.buttons["create-skill-preview"].tap()

        let alert = app.alerts["Skillを作成できませんでした"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        XCTAssertTrue(alert.staticTexts["このバージョンで作成できるのは、空白・改行・句読点など文章を読みやすく整えるSkillです。要約・翻訳・外部アプリ操作は今後対応します。"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["skill-preview-result"].exists)
    }

    func testBuilderAtAccessibilityTextSizeKeepsCreationPathReachable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-skill-builder-qa", "-ui-test-reset", "-accessibility-text-size-qa"]
        app.launch()

        let request = app.textViews["skill-request"]
        XCTAssertTrue(request.waitForExistence(timeout: 5))
        request.tap()
        request.typeText("文章を自然に整える")
        let create = app.buttons["create-skill-preview"]
        for _ in 0..<6 where !create.isHittable { app.swipeUp() }
        XCTAssertTrue(create.isHittable)
        create.tap()
        XCTAssertTrue(app.descendants(matching: .any)["skill-preview-result"].waitForExistence(timeout: 3))
        let install = app.buttons["install-created-skill"]
        for _ in 0..<6 where !install.isHittable { app.swipeUp() }
        XCTAssertTrue(install.isHittable)
    }

    func testUnassignedPrivateSkillSurvivesHostRestart() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-skill-builder-qa", "-ui-test-reset"]
        app.launch()

        let request = app.textViews["skill-request"]
        XCTAssertTrue(request.waitForExistence(timeout: 5))
        request.tap()
        request.typeText("文章を自然に整える")
        app.buttons["create-skill-preview"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["skill-preview-result"].waitForExistence(timeout: 3))
        app.buttons["install-created-skill"].tap()
        XCTAssertTrue(app.staticTexts["キーを選ぶ"].waitForExistence(timeout: 3))
        app.buttons["キャンセル"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["skill-created-success"].waitForExistence(timeout: 3))

        app.terminate()
        app.launchArguments = ["-skill-keys-qa"]
        app.launch()
        XCTAssertTrue(app.staticTexts["テキストを整える"].waitForExistence(timeout: 5))
    }

    func testKeyboardSetupCanBeReopenedAfterOnboarding() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-app-shell-qa"]
        app.launch()

        app.tabBars.buttons["設定"].tap()
        let setup = app.buttons["reopen-keyboard-setup"]
        XCTAssertTrue(setup.waitForExistence(timeout: 5))
        setup.tap()
        XCTAssertTrue(app.staticTexts["キーボードを有効にする"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["設定 → 一般 → キーボード → キーボードへ進む"].exists)
    }

    private func fill(_ element: XCUIElement, with value: String, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertTrue(element.waitForExistence(timeout: 3), file: file, line: line)
        element.tap()
        element.typeText(value)
    }
}
