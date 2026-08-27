import UIKit
import MobileAIKeyboardCore

/// Native keyboard foundation and W2 local text-action vertical slice.
/// Ordinary key values are committed directly to UITextDocumentProxy; no key value is logged,
/// retained, or sent to a network service.
final class KeyboardViewController: UIInputViewController {
    private var machine = KeyboardStateMachine()
    private let policy = SensitiveFieldPolicy()
    private let redactor = LocalRedactor()
    private let locking = EntityLocking()
    private let statusLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private let skillPaletteButton = UIButton(type: .system)
    private var shiftButton = UIButton(type: .system)
    private var letterButtons: [UIButton] = []
    private var inputState = KeyboardInputState()
    private var returnButton: UIButton?
    private var actionButtonConfigured = false
    private var skillPaletteButtonConfigured = false
    private var isSkillPaletteVisible = false
    private var typingStack: UIStackView?
    private var commandTextView = UITextView()
    private var resultTextView = UITextView()
    private var selectedSource: CaptureSource = .command
    private var captureDraft: CaptureDraft?
    private var captureAcknowledged = false
    private var hasSelectionCapture = false
    private var sourceButtons: [CaptureSource: UIButton] = [:]
    private var keyboardHeightConstraint: NSLayoutConstraint?
    private let shortcutStore = AppGroupShortcutSnapshotStore()
    private let nativeSkillFailureStore = AppGroupNativeSkillFailureStore()
    private let accessStatusStore = AppGroupKeyboardAccessStatusStore()
    private let settingsStore = AppGroupKeyboardSettingsStore()
    private var keyboardSettings = KeyboardSettingsState.defaultFixture
    private var shortcutSnapshot: ShortcutSnapshotV1?
    private var shortcutBindings: [ShortcutKeyCode: ShortcutBindingV1] = [:]
    private var shortcutSkills: [String: ShortcutSkillProjectionV1] = [:]
    private var letterButtonsByKey: [ShortcutKeyCode: UIButton] = [:]
    private var consumedLongPressKey: ShortcutKeyCode?
    private var longPressBeganKey: ShortcutKeyCode?
    private let longPressFeedback = UIImpactFeedbackGenerator(style: .light)
    private var isFullAccessEnabled = false
    private var pendingShortcutSkill: ShortcutSkillProjectionV1?
    private var pendingShortcutActivation: ShortcutActivationV1?
    private var boundaryRefreshTimer: Timer?
    private var deleteRepeatTimer: Timer?
    private var documentIdentifier: String { textDocumentProxy.documentIdentifier.uuidString }

    override func viewDidLoad() {
        super.viewDidLoad()
        reloadKeyboardSettings()
        buildTypingView()
        refreshFieldSecurityFromProxy()
        updateFullAccessState()
        refreshShortcutSnapshot()
        // iOS routes secure text fields to the system keyboard and does not expose their traits to
        // custom keyboards. For adapters that do receive traits, updateFieldSecurity(_:) is the
        // single policy gate before rendering command UI.
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let previousSettings = keyboardSettings
        reloadKeyboardSettings()
        if previousSettings != keyboardSettings { buildTypingView() }
        refreshFieldSecurityFromProxy()
        updateFullAccessState()
        consumedLongPressKey = nil
        longPressBeganKey = nil
        refreshShortcutSnapshot()
        boundaryRefreshTimer?.invalidate()
        boundaryRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshVisibleShortcutAuthority()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopDeleteRepeat()
        boundaryRefreshTimer?.invalidate()
        boundaryRefreshTimer = nil
        clearEphemeralState(showTypingView: false)
    }

    private func refreshVisibleShortcutAuthority() {
        // Re-read even when owner/epoch is unchanged: the host may publish a
        // newer generation, and an initial nil read must converge while warm.
        refreshShortcutSnapshot()
    }

    private func updateFullAccessState() {
        let hadFullAccess = isFullAccessEnabled
        isFullAccessEnabled = hasFullAccess
        accessStatusStore.publish(fullAccessEnabled: isFullAccessEnabled)
        // Local command processing does not need Full Access. The permission is
        // required for the App Group-backed Skill Key projection and any future
        // network capability, so ordinary typing and local workflow stay usable.
        actionButton.isEnabled = true
        if hadFullAccess && !isFullAccessEnabled && (pendingShortcutActivation != nil || pendingShortcutSkill != nil || isSkillPaletteVisible) {
            clearEphemeralState(showTypingView: true)
            UIAccessibility.post(notification: .announcement, argument: "フルアクセスが無効になったためSkill実行を停止しました。通常入力は利用できます。")
        }
        updateBoundKeyPresentation()
        if !isFullAccessEnabled {
            statusLabel.text = "入力。Skill Keyはフルアクセスが必要"
            statusLabel.accessibilityValue = "通常入力と端末内AIは利用できます。Skill Key同期にはフルアクセスが必要です"
        }
    }

    private func refreshShortcutSnapshot() {
        let requestedBoundary = shortcutStore.loadActiveBoundary()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let snapshot = self?.shortcutStore.loadLastKnownGood()
            DispatchQueue.main.async {
                guard let self else { return }
                let currentBoundary = self.shortcutStore.loadActiveBoundary()
                self.applyShortcutSnapshot(currentBoundary == requestedBoundary ? snapshot : nil)
            }
        }
    }

    private func applyShortcutSnapshot(_ snapshot: ShortcutSnapshotV1?) {
        let paletteWasVisible = isSkillPaletteVisible
        let previousPaletteIdentity = activePaletteEntries().map { "\($0.0.id)|\($0.0.skillDigest)" }
        guard let snapshot,
              let boundary = shortcutStore.loadActiveBoundary(),
              (try? ShortcutSnapshotValidator.validate(snapshot, expectedDeviceID: ShortcutDeviceIdentity.localFixtureID, expectedOwnerSubjectHash: boundary.ownerSubjectHash, expectedPolicyEpoch: boundary.sessionEpoch)) != nil else {
            shortcutSnapshot = nil
            shortcutBindings = [:]
            shortcutSkills = [:]
            clearEphemeralState(showTypingView: typingStack != nil)
            updateBoundKeyPresentation()
            return
        }
        shortcutSnapshot = snapshot
        // Host handoffs are intentionally not exposed to the extension until
        // their return path is implemented end-to-end. An old snapshot may
        // still contain one, so fail closed at the consumer boundary too.
        shortcutBindings = Dictionary(uniqueKeysWithValues: snapshot.bindings.filter {
            $0.enabled && $0.executionRoute == .keyboardLocal && nativeSkillFailureStore.decision(for: $0, boundary: boundary) == .allowed
        }.map { ($0.keyCode, $0) })
        shortcutSkills = Dictionary(uniqueKeysWithValues: snapshot.skills.filter { $0.executionRoute == .keyboardLocal }.map { ("\($0.id)|\($0.versionID)", $0) })
        updateBoundKeyPresentation()
        if paletteWasVisible {
            let nextPaletteIdentity = activePaletteEntries().map { "\($0.0.id)|\($0.0.skillDigest)" }
            if previousPaletteIdentity != nextPaletteIdentity {
                isSkillPaletteVisible = false
                if nextPaletteIdentity.isEmpty { showTyping() } else { showSkillPalette() }
            }
        }
    }

    private func updateBoundKeyPresentation() {
        let shortcutsAllowed: Bool
        if case .locked = machine.screen { shortcutsAllowed = false } else { shortcutsAllowed = true }
        let paletteCount = activePaletteEntries().count
        skillPaletteButton.isEnabled = shortcutsAllowed && isFullAccessEnabled && paletteCount > 0
        skillPaletteButton.isHidden = !shortcutsAllowed
        skillPaletteButton.accessibilityValue = paletteCount == 0 ? "割り当てなし" : "\(paletteCount)件"
        for (key, button) in letterButtonsByKey {
            guard shortcutsAllowed, let binding = shortcutBindings[key], let skill = shortcutSkills["\(binding.skillID)|\(binding.versionID)"] else {
                button.layer.borderWidth = 0.5
                button.layer.borderColor = UIColor.separator.cgColor
                button.accessibilityLabel = key.displayLabel
                button.accessibilityValue = nil
                button.accessibilityHint = isFullAccessEnabled ? "タップで通常入力" : "タップで通常入力。AI機能とSkill Key同期にはフルアクセスが必要です"
                button.accessibilityCustomActions = nil
                continue
            }
            button.layer.borderWidth = 1.5
            button.layer.borderColor = UIColor.systemCyan.cgColor
            button.accessibilityLabel = "\(key.displayLabel)、\(skill.name)、端末内の選択文変換"
            button.accessibilityValue = isFullAccessEnabled ? "利用可能" : "フルアクセスが必要"
            button.accessibilityHint = isFullAccessEnabled ? "タップで通常入力。長押し、またはSkill一覧から実行" : "タップで通常入力。フルアクセスを許可するとSkillを実行できます"
            button.accessibilityCustomActions = isFullAccessEnabled ? [UIAccessibilityCustomAction(name: "\(skill.name)を実行") { [weak self] _ in
                self?.invokeShortcut(skill, binding: binding)
                return true
            }] : nil
        }
    }

    // MARK: Ordinary keyboard

    private func buildTypingView() {
        statusLabel.text = "入力"
        statusLabel.textAlignment = .center
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.accessibilityTraits = .header
        statusLabel.accessibilityLabel = "キーボードの状態"

        actionButton.setTitle("AI", for: .normal)
        actionButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        actionButton.titleLabel?.adjustsFontForContentSizeCategory = true
        actionButton.accessibilityLabel = "AIコマンドを開く"
        actionButton.accessibilityHint = "文章を確認してから端末内で整えます。外部送信はありません"
        if !actionButtonConfigured {
            actionButton.addTarget(self, action: #selector(invoke), for: .touchUpInside)
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(invokeLongPress(_:)))
            hold.minimumPressDuration = 0.45
            actionButton.addGestureRecognizer(hold)
            actionButtonConfigured = true
        }

        skillPaletteButton.setTitle("Skills", for: .normal)
        skillPaletteButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        skillPaletteButton.titleLabel?.adjustsFontForContentSizeCategory = true
        skillPaletteButton.accessibilityIdentifier = "skill-palette"
        skillPaletteButton.accessibilityLabel = "Skill一覧を開く"
        skillPaletteButton.accessibilityHint = "長押しせず、割り当て済みSkillを選んで実行します"
        if !skillPaletteButtonConfigured {
            skillPaletteButton.addTarget(self, action: #selector(showSkillPalette), for: .touchUpInside)
            skillPaletteButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            skillPaletteButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            actionButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            actionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            skillPaletteButtonConfigured = true
        }

        let header = UIStackView(arrangedSubviews: [statusLabel, skillPaletteButton, actionButton])
        header.axis = .horizontal
        header.alignment = .center
        header.distribution = .equalSpacing
        header.isLayoutMarginsRelativeArrangement = true
        header.layoutMargins = UIEdgeInsets(top: 2, left: 10, bottom: 2, right: 10)

        letterButtons.removeAll()
        letterButtonsByKey.removeAll()
        let first: UIStackView
        let second: UIStackView
        let third: UIStackView
        switch inputState.layer {
        case .letters:
            first = makeLetterRow(OrdinaryKeyboardLayout.letterRows[0])
            second = makeLetterRow(OrdinaryKeyboardLayout.letterRows[1])
            third = makeLetterRow(OrdinaryKeyboardLayout.letterRows[2], leading: makeShiftButton(), trailing: makeDeleteButton())
        case .numbersAndSymbols:
            first = makeLetterRow(OrdinaryKeyboardLayout.numberRows[0])
            second = makeLetterRow(OrdinaryKeyboardLayout.numberRows[1])
            third = makeLetterRow(OrdinaryKeyboardLayout.numberRows[2], trailing: makeDeleteButton())
        }
        let bottom = makeBottomRow()
        let stack = UIStackView(arrangedSubviews: [header, first, second, third, bottom])
        stack.axis = .vertical
        stack.spacing = 4
        stack.distribution = .fillEqually
        stack.isLayoutMarginsRelativeArrangement = true
        switch keyboardSettings.oneHandedMode {
        case .off: stack.layoutMargins = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        case .left: stack.layoutMargins = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 52)
        case .right: stack.layoutMargins = UIEdgeInsets(top: 4, left: 52, bottom: 4, right: 4)
        }
        typingStack = stack
        updateShiftAppearance()
        updateReturnKeyPresentation()
        install(stack, height: keyboardHeight)
        updateBoundKeyPresentation()
    }

    private func activePaletteEntries() -> [(ShortcutBindingV1, ShortcutSkillProjectionV1)] {
        shortcutBindings.values.compactMap { binding in
            shortcutSkills["\(binding.skillID)|\(binding.versionID)"].map { (binding, $0) }
        }.sorted { lhs, rhs in
            lhs.0.keyCode.displayLabel.localizedStandardCompare(rhs.0.keyCode.displayLabel) == .orderedAscending
        }
    }

    /// Visible, non-hold alternative for Switch Control, VoiceOver, motor
    /// accessibility, and users who prefer discovery over memorized keys.
    /// Every entry routes through the same exact-version activation checks as
    /// the physical long-press and accessibility custom action.
    @objc private func showSkillPalette() {
        if case .locked = machine.screen { return }
        guard isFullAccessEnabled else { presentRecoverableError(.unavailable); return }
        let entries = activePaletteEntries()
        guard !entries.isEmpty else {
            presentRecoverableError(.unavailable)
            return
        }
        isSkillPaletteVisible = true
        let title = UILabel()
        title.text = "Skill一覧"
        title.font = .preferredFont(forTextStyle: .headline)
        title.adjustsFontForContentSizeCategory = true
        title.accessibilityTraits = .header
        let detail = UILabel()
        detail.text = "タップして実行。文字キーの長押しは不要です。"
        detail.numberOfLines = 0
        detail.font = .preferredFont(forTextStyle: .footnote)
        detail.adjustsFontForContentSizeCategory = true
        let stack = UIStackView(arrangedSubviews: [title, detail])
        stack.axis = .vertical
        stack.spacing = 6
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        for (binding, skill) in entries {
            let button = makeActionButton("\(binding.keyCode.displayLabel)  \(skill.name)", label: "\(binding.keyCode.displayLabel)、\(skill.name)を実行")
            button.accessibilityHint = "選択中の文章を確認してから端末内で実行します"
            button.addAction(UIAction { [weak self] _ in
                self?.isSkillPaletteVisible = false
                self?.invokeShortcut(skill, binding: binding)
            }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
        let close = makeActionButton("閉じる", label: "Skill一覧を閉じて通常入力へ戻る")
        close.addTarget(self, action: #selector(closeSkillPalette), for: .touchUpInside)
        stack.addArrangedSubview(close)
        install(stack, height: 252)
        UIAccessibility.post(notification: .screenChanged, argument: title)
    }

    @objc private func closeSkillPalette() {
        isSkillPaletteVisible = false
        showTyping()
        UIAccessibility.post(notification: .screenChanged, argument: skillPaletteButton)
    }

    private func makeLetterRow(_ letters: String, leading: UIView? = nil, trailing: UIView? = nil) -> UIStackView {
        var views: [UIView] = []
        if let leading { views.append(leading) }
        for letter in letters {
            let button = makeKey(String(letter))
            if ShortcutKeyCode(displayLabel: String(letter)) != nil { letterButtons.append(button) }
            views.append(button)
        }
        if let trailing { views.append(trailing) }
        let row = UIStackView(arrangedSubviews: views)
        row.axis = .horizontal
        row.spacing = 3
        row.distribution = .fillEqually
        return row
    }

    private func makeBottomRow() -> UIStackView {
        let globe = makeUtilityButton("globe", title: "🌐", label: "次のキーボード")
        globe.addTarget(self, action: #selector(nextKeyboard), for: .touchUpInside)
        let layerButton = makeUtilityButton("layer", title: inputState.layer.toggleTitle, label: inputState.layer == .letters ? "数字と記号" : "英字")
        layerButton.addTarget(self, action: #selector(toggleInputLayer), for: .touchUpInside)
        let spaceButton = makeUtilityButton("space", title: "空白", label: "スペース")
        spaceButton.addTarget(self, action: #selector(space), for: .touchUpInside)
        let returnButton = makeUtilityButton("return", title: returnKeyDisplay().displayLabel, label: returnKeyAccessibilityLabel())
        returnButton.addTarget(self, action: #selector(returnKey), for: .touchUpInside)
        self.returnButton = returnButton
        let row = UIStackView(arrangedSubviews: [globe, layerButton, spaceButton, returnButton])
        row.axis = .horizontal
        row.spacing = 3
        row.distribution = .fillProportionally
        spaceButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true
        return row
    }

    private func makeKey(_ letter: String) -> UIButton {
        let baseLetter = letter.first.map { String($0).lowercased() } ?? letter
        let displayLetter = inputState.displayLetter(Character(baseLetter))
        let button = makeUtilityButton("letter-\(baseLetter)", title: String(displayLetter), label: String(displayLetter))
        if let key = ShortcutKeyCode(displayLabel: letter) {
            letterButtonsByKey[key] = button
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(skillKeyLongPress(_:)))
            hold.minimumPressDuration = 0.45
            hold.allowableMovement = 10
            // An unassigned key keeps its ordinary tap/alternate behavior. A
            // bound key is suppressed only after the long-press handler arms.
            hold.cancelsTouchesInView = false
            button.addGestureRecognizer(hold)
        }
        button.addTarget(self, action: #selector(letterPressed(_:)), for: .touchUpInside)
        button.addTarget(self, action: #selector(letterTouchEnded(_:)), for: [.touchUpOutside, .touchCancel])
        button.accessibilityHint = "入力欄に文字を入力"
        return button
    }

    private func makeShiftButton() -> UIButton {
        shiftButton = UIButton(type: .system)
        shiftButton.setTitle("⇧", for: .normal)
        shiftButton.accessibilityLabel = "シフト"
        shiftButton.accessibilityValue = inputState.shift.accessibilityValue
        styleKey(shiftButton)
        shiftButton.addTarget(self, action: #selector(toggleShift), for: .touchUpInside)
        return shiftButton
    }

    private func makeDeleteButton() -> UIButton {
        let button = makeUtilityButton("delete", title: "⌫", label: "削除")
        button.addTarget(self, action: #selector(startDeleteRepeat), for: .touchDown)
        button.addTarget(self, action: #selector(stopDeleteRepeat), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
        return button
    }

    private func makeUtilityButton(_ identifier: String, title: String, label: String) -> UIButton {
        let button = UIButton(type: .system)
        button.accessibilityIdentifier = identifier
        button.accessibilityLabel = label
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .body)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        styleKey(button)
        return button
    }

    private func styleKey(_ button: UIButton) {
        button.backgroundColor = .systemBackground
        button.layer.cornerRadius = 6
        button.layer.borderWidth = 0.5
        button.layer.borderColor = UIColor.separator.cgColor
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: keyMinimumHeight).isActive = true
    }

    @objc private func letterPressed(_ sender: UIButton) {
        guard let title = sender.currentTitle, title.count == 1 else { return }
        if let key = ShortcutKeyCode(displayLabel: title), consumedLongPressKey == key {
            consumedLongPressKey = nil
            return
        }
        textDocumentProxy.insertText(title)
        performKeyHaptic()
        inputState.commitLetter()
        updateShiftAppearance()
    }

    @objc private func letterTouchEnded(_ sender: UIButton) {
        guard let title = sender.currentTitle, let key = ShortcutKeyCode(displayLabel: title) else { return }
        if consumedLongPressKey == key { consumedLongPressKey = nil }
    }

    @objc private func toggleShift() {
        inputState.pressShift()
        performKeyHaptic()
        updateShiftAppearance()
    }

    @objc private func toggleInputLayer() {
        inputState.toggleLayer()
        performKeyHaptic()
        buildTypingView()
    }

    private func updateShiftAppearance() {
        for button in letterButtons {
            guard let value = button.currentTitle?.first else { continue }
            let base = Character(String(value).lowercased())
            let display = inputState.displayLetter(base)
            button.setTitle(String(display), for: .normal)
            button.accessibilityLabel = String(display)
        }
        shiftButton.accessibilityValue = inputState.shift.accessibilityValue
        shiftButton.backgroundColor = inputState.shift == .lower ? .systemBackground : .systemBlue.withAlphaComponent(0.2)
        updateBoundKeyPresentation()
    }

    private func returnKeyDisplay() -> KeyboardReturnAction {
        switch textDocumentProxy.returnKeyType {
        case .go: return .go
        case .join: return .join
        case .next: return .next
        case .search: return .search
        case .send: return .send
        case .done: return .done
        case .continue: return .continue
        default: return .newline
        }
    }

    private func returnKeyAccessibilityLabel() -> String {
        let action = returnKeyDisplay()
        return action == .newline ? "改行" : "\(action.displayLabel)（改行を入力）"
    }

    private func updateReturnKeyPresentation() {
        let action = returnKeyDisplay()
        returnButton?.setTitle(action.displayLabel, for: .normal)
        returnButton?.accessibilityLabel = returnKeyAccessibilityLabel()
    }

    @objc private func space() { textDocumentProxy.insertText(" "); performKeyHaptic() }
    @objc private func returnKey() { textDocumentProxy.insertText("\n"); performKeyHaptic() }
    @objc private func startDeleteRepeat() {
        stopDeleteRepeat()
        textDocumentProxy.deleteBackward()
        performKeyHaptic()
        let timer = Timer(timeInterval: 0.08, target: self, selector: #selector(repeatDeleteBackward), userInfo: nil, repeats: true)
        deleteRepeatTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { [weak self, weak timer] in
            guard let self, self.deleteRepeatTimer === timer, let timer else { return }
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    @objc private func stopDeleteRepeat() {
        deleteRepeatTimer?.invalidate()
        deleteRepeatTimer = nil
    }

    @objc private func repeatDeleteBackward() { textDocumentProxy.deleteBackward() }
    @objc private func nextKeyboard() { advanceToNextInputMode() }

    @objc private func skillKeyLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard let button = gesture.view as? UIButton,
              let title = button.currentTitle,
              let key = ShortcutKeyCode(displayLabel: title) else { return }
        switch gesture.state {
        case .began:
            if case .locked = machine.screen { return }
            guard let binding = shortcutBindings[key], let skill = shortcutSkills["\(binding.skillID)|\(binding.versionID)"] else { return }
            guard isFullAccessEnabled else {
                presentRecoverableError(.unavailable)
                return
            }
            longPressBeganKey = key
            consumedLongPressKey = key
            if keyboardSettings.hapticsEnabled {
                longPressFeedback.prepare()
                longPressFeedback.impactOccurred()
            }
            statusLabel.text = "長押し: \(skill.name)"
            statusLabel.accessibilityValue = "\(skill.name)を実行します"
            invokeShortcut(skill, binding: binding)
        case .ended:
            // UIControl may deliver touchUpInside before or after recognizer
            // cleanup depending on the host app. Keep the suppression scoped
            // to this pointer sequence, never to the next tap.
            DispatchQueue.main.async { [weak self] in
                if self?.consumedLongPressKey == key { self?.consumedLongPressKey = nil }
                if self?.longPressBeganKey == key { self?.longPressBeganKey = nil }
            }
        case .cancelled, .failed:
            guard longPressBeganKey == key else { return }
            statusLabel.text = "長押しをキャンセルしました"
            statusLabel.accessibilityValue = "長押しをキャンセルしました。通常入力は利用できます"
            UIAccessibility.post(notification: .announcement, argument: statusLabel.text)
            // Keep suppression armed until this touch ends so a cancelled
            // gesture cannot accidentally commit a character from the same
            // pointer sequence. A new sequence starts cleanly on touch-up.
            DispatchQueue.main.async { [weak self] in
                if self?.longPressBeganKey == key { self?.longPressBeganKey = nil }
            }
        default: break
        }
    }

    private func invokeShortcut(_ skill: ShortcutSkillProjectionV1, binding: ShortcutBindingV1) {
        guard isFullAccessEnabled else {
            presentRecoverableError(.unavailable)
            showTyping()
            return
        }
        if case .locked = machine.screen { return }
        guard let boundary = shortcutStore.loadActiveBoundary(),
              nativeSkillFailureStore.decision(for: binding, boundary: boundary) == .allowed,
              let snapshot = shortcutStore.loadLastKnownGood(),
              snapshot.generation == shortcutSnapshot?.generation,
              let exactBinding = snapshot.bindings.first(where: {
                  $0.id == binding.id && $0.skillID == binding.skillID && $0.versionID == binding.versionID &&
                  $0.skillDigest == binding.skillDigest && $0.keyCode == binding.keyCode && $0.enabled
              }),
              snapshot.skills.contains(where: {
                  $0.id == skill.id && $0.versionID == skill.versionID && $0.skillDigest == skill.skillDigest
              }) else {
            applyShortcutSnapshot(nil)
            presentRecoverableError(.staleField)
            return
        }
        guard skill.executionRoute == .keyboardLocal else {
            statusLabel.text = "このSkillはhostアプリで確認してから実行します。通常入力は利用できます。"
            UIAccessibility.post(notification: .announcement, argument: statusLabel.text)
            return
        }
            guard let text = ShortcutCapturePolicy.localSelection(skill: skill, selectedText: textDocumentProxy.selectedText) else {
                presentRecoverableError(.emptyInput)
                return
            }
            let source: CaptureSource = .selection
            guard text.count <= LocalTextLimits.selectionCharacters else { presentRecoverableError(.captureTooLarge); return }
            let redaction = redactor.redact(text)
            pendingShortcutSkill = skill
            pendingShortcutActivation = ShortcutActivationV1(binding: exactBinding, snapshot: snapshot, editorSessionID: documentIdentifier)
            selectedSource = source
            captureDraft = CaptureDraft(text: text, source: source, fieldFingerprint: locking.selectionFingerprint(selectedText: text, before: textDocumentProxy.documentContextBeforeInput ?? "", after: textDocumentProxy.documentContextAfterInput ?? ""), redactedText: redaction.redacted, externalTransmissionAllowed: false, fallbackMessage: "\(skill.name) v\(skill.skillVersion)。選択範囲を確認してから端末内で実行します。", documentIdentifier: documentIdentifier)
            captureAcknowledged = false
            transition(.beginCapture(captureDraft!))
            showCaptureReview(captureDraft!, redactionBlocked: redaction.blocked)
    }

    // MARK: Command, capture review, result review

    @objc private func invoke() {
        guard case .locked = machine.screen else {
            transition(.invokeCommand)
            if case .command = machine.screen { showCommandView() }
            return
        }
    }

    @objc private func invokeLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        invoke()
    }

    private func showCommandView() {
        selectedSource = .command
        commandTextView = UITextView()
        commandTextView.font = .preferredFont(forTextStyle: .body)
        commandTextView.adjustsFontForContentSizeCategory = true
        commandTextView.backgroundColor = .systemBackground
        commandTextView.layer.cornerRadius = 8
        commandTextView.layer.borderWidth = 0.5
        commandTextView.layer.borderColor = UIColor.separator.cgColor
        commandTextView.accessibilityLabel = "コマンド"
        commandTextView.accessibilityHint = "例: 丁寧に短く整えて"
        commandTextView.inputView = UIView()
        sourceButtons.removeAll()

        let title = UILabel()
        title.text = "コマンド"
        title.font = .preferredFont(forTextStyle: .headline)
        title.adjustsFontForContentSizeCategory = true
        title.accessibilityTraits = .header
        let hint = UILabel()
        hint.text = "端末内で処理します。入力内容は外部送信しません。"
        hint.font = .preferredFont(forTextStyle: .footnote)
        hint.adjustsFontForContentSizeCategory = true
        hint.textColor = .secondaryLabel
        hint.numberOfLines = 0

        let chips = UIStackView(axis: .horizontal, spacing: 6)
        for source in [CaptureSource.selection, .surroundingContext] {
            let button = makeSourceButton(source)
            sourceButtons[source] = button
            chips.addArrangedSubview(button)
        }
        let fallback = UILabel()
        fallback.text = "選択なし・利用できないhost contextは、入力したコマンドだけで処理します。"
        fallback.font = .preferredFont(forTextStyle: .caption1)
        fallback.textColor = .secondaryLabel
        fallback.numberOfLines = 0

        let review = makeActionButton("確認", label: "入力内容を確認")
        review.addTarget(self, action: #selector(beginCapture), for: .touchUpInside)
        let cancel = makeActionButton("キャンセル", label: "コマンドをキャンセル")
        cancel.addTarget(self, action: #selector(cancelAction), for: .touchUpInside)
        let buttons = UIStackView(arrangedSubviews: [cancel, review])
        buttons.axis = .horizontal
        buttons.spacing = 8
        buttons.distribution = .fillEqually

        let editorKeyboard = makeEditorKeyboard(for: commandTextView)
        let stack = UIStackView(arrangedSubviews: [title, hint, commandTextView, chips, fallback, editorKeyboard, buttons])
        stack.axis = .vertical
        stack.spacing = 8
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        commandTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        install(stack, height: 432)
        postScreenChange(title)
    }

    private func makeSourceButton(_ source: CaptureSource) -> UIButton {
        let title = source == .selection ? "選択範囲" : "周辺コンテキスト"
        let button = makeActionButton(title, label: "入力ソース: \(title)。明示的に選択")
        button.accessibilityValue = "オフ"
        button.addTarget(self, action: #selector(sourceTapped(_:)), for: .touchUpInside)
        button.accessibilityIdentifier = "source-\(source.rawValue)"
        return button
    }

    @objc private func sourceTapped(_ sender: UIButton) {
        guard let id = sender.accessibilityIdentifier?.replacingOccurrences(of: "source-", with: ""), let source = CaptureSource(rawValue: id) else { return }
        selectedSource = selectedSource == source ? .command : source
        for (source, button) in sourceButtons {
            let active = source == selectedSource
            button.accessibilityValue = active ? "オン" : "オフ"
            button.backgroundColor = active ? .systemBlue.withAlphaComponent(0.2) : .systemBackground
        }
    }

    @objc private func beginCapture() {
        hasSelectionCapture = false
        let selected = textDocumentProxy.selectedText
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let after = textDocumentProxy.documentContextAfterInput ?? ""
        var text = commandTextView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        var source = CaptureSource.command
        var fallbackMessage: String?
        switch selectedSource {
        case .selection where !(selected ?? "").isEmpty:
            text = selected ?? text
            source = .selection
            hasSelectionCapture = true
        case .selection:
            fallbackMessage = "選択範囲を取得できなかったため、入力したコマンドだけを使います。"
        case .surroundingContext where !before.isEmpty || !after.isEmpty:
            text = String(before.suffix(LocalTextLimits.surroundingBeforeCharacters))
                + String(after.prefix(LocalTextLimits.surroundingAfterCharacters))
            source = .surroundingContext
        case .surroundingContext:
            fallbackMessage = "host contextを取得できなかったため、入力したコマンドだけを使います。"
        case .command: break
        }
        guard !text.isEmpty else {
            presentRecoverableError(.emptyInput)
            return
        }
        let limit = source == .command ? LocalTextLimits.commandCharacters :
            (source == .selection ? LocalTextLimits.selectionCharacters :
                LocalTextLimits.surroundingBeforeCharacters + LocalTextLimits.surroundingAfterCharacters)
        guard text.count <= limit else {
            presentRecoverableError(.captureTooLarge)
            return
        }
        let redaction = redactor.redact(text)
        let targetFingerprint = source == .selection
            ? locking.selectionFingerprint(selectedText: selected ?? "", before: before, after: after)
            : locking.fingerprint(before + after)
        let draft = CaptureDraft(text: text, source: source, fieldFingerprint: targetFingerprint, redactedText: redaction.redacted, externalTransmissionAllowed: false, fallbackMessage: fallbackMessage, documentIdentifier: documentIdentifier)
        captureDraft = draft
        captureAcknowledged = false
        transition(.beginCapture(draft))
        showCaptureReview(draft, redactionBlocked: redaction.blocked)
    }

    private func showCaptureReview(_ draft: CaptureDraft, redactionBlocked: Bool) {
        let title = UILabel(); title.text = pendingShortcutSkill.map { "\($0.name) — 入力内容の確認" } ?? "送信内容の確認"; title.font = .preferredFont(forTextStyle: .headline); title.adjustsFontForContentSizeCategory = true; title.accessibilityTraits = .header
        let exact = makeExactContentView("入力内容（\(draft.characterCount)文字）", value: draft.text)
        let redacted = makePreviewLabel("ローカル検出後の表示", value: draft.redactedText)
        let destination = makePreviewLabel("実行先", value: pendingShortcutSkill?.executionRoute == .keyboardLocal ? "端末内のみ / 外部送信なし" : "host確認が必要")
        let source = makePreviewLabel("入力ソース", value: draft.source == .command ? "コマンド" : draft.source.rawValue)
        let warning = UILabel(); warning.text = draft.fallbackMessage ?? (redactionBlocked ? "秘密情報候補を検出したため処理を停止します。" : "内容を確認してから続けてください。")
        warning.textColor = redactionBlocked ? .systemRed : .secondaryLabel; warning.numberOfLines = 0; warning.font = .preferredFont(forTextStyle: .footnote); warning.adjustsFontForContentSizeCategory = true
        let acknowledge = makeActionButton(captureAcknowledged ? "確認済み" : "内容を確認しました", label: "送信内容を確認しました")
        acknowledge.accessibilityValue = captureAcknowledged ? "オン" : "オフ"
        acknowledge.addTarget(self, action: #selector(acknowledgeCapture), for: .touchUpInside)
        let proceedTitle = pendingShortcutSkill?.name ?? "端末内で丁寧に整える"
        let proceed = makeActionButton("確認後に\(proceedTitle)", label: "確認後に\(proceedTitle)を実行")
        proceed.isEnabled = captureAcknowledged && !redactionBlocked
        proceed.addTarget(self, action: #selector(startLocalRewrite), for: .touchUpInside)
        let cancel = makeActionButton("キャンセル", label: "確認をキャンセル")
        cancel.addTarget(self, action: #selector(cancelAction), for: .touchUpInside)
        let buttons = UIStackView(arrangedSubviews: [cancel, acknowledge, proceed]); buttons.axis = .vertical; buttons.spacing = 6
        let stack = UIStackView(arrangedSubviews: [title, exact, redacted, source, destination, warning, buttons]); stack.axis = .vertical; stack.spacing = 7; stack.isLayoutMarginsRelativeArrangement = true; stack.layoutMargins = UIEdgeInsets(top: 7, left: 10, bottom: 7, right: 10)
        install(stack, height: 368)
        postScreenChange(title)
    }

    @objc private func acknowledgeCapture() {
        guard let draft = captureDraft else { return }
        guard !captureAcknowledged else { return }
        captureAcknowledged = true
        captureDraft = draft.acknowledging()
        transition(.acknowledgeCapture)
        if let updated = captureDraft { showCaptureReview(updated, redactionBlocked: redactor.redact(updated.text).blocked) }
    }

    @objc private func startLocalRewrite() {
        guard let draft = captureDraft, draft.acknowledged else { transition(.fail(.missingDisclosure)); return }
        guard shortcutActivationStillCurrent() else { presentRecoverableError(.staleField); return }
        transition(.beginPlanning)
        let local: RewriteResult?
        if let skill = pendingShortcutSkill {
            local = LocalSkillExecutor.execute(skill, input: draft.text)
        } else {
            local = LocalRewriteEngine().politeRewrite(draft.text)
        }
        guard let local else {
            recordNativeSkillFailureIfNeeded()
            transition(.fail(.emptyInput))
            refreshShortcutSnapshot()
            return
        }
        guard local.rewritten.count <= LocalTextLimits.resultCharacters else {
            presentRecoverableError(.resultTooLarge)
            return
        }
        recordNativeSkillSuccessIfNeeded()
        guard shortcutActivationStillCurrent() else { presentRecoverableError(.staleField); return }
        let result = RewriteResult(original: local.original, rewritten: local.rewritten, preservedEntities: local.preservedEntities, fieldFingerprint: draft.fieldFingerprint, documentIdentifier: draft.documentIdentifier)
        transition(.showRewrite(result))
        showResultReview(result)
    }

    private func showResultReview(_ result: RewriteResult) {
        resultTextView = UITextView(); resultTextView.text = result.rewritten; resultTextView.selectedRange = NSRange(location: (result.rewritten as NSString).length, length: 0); resultTextView.font = .preferredFont(forTextStyle: .body); resultTextView.adjustsFontForContentSizeCategory = true; resultTextView.isEditable = false; resultTextView.inputView = UIView(); resultTextView.accessibilityLabel = "書き換え結果"; resultTextView.layer.cornerRadius = 8; resultTextView.layer.borderWidth = 0.5; resultTextView.layer.borderColor = UIColor.separator.cgColor
        let title = UILabel(); title.text = "結果を確認"; title.font = .preferredFont(forTextStyle: .headline); title.adjustsFontForContentSizeCategory = true; title.accessibilityTraits = .header
        let hint = UILabel(); hint.text = "編集・再生成・コピー・適用を選べます。適用前にentityを保護します。"; hint.textColor = .secondaryLabel; hint.numberOfLines = 0; hint.font = .preferredFont(forTextStyle: .footnote); hint.adjustsFontForContentSizeCategory = true
        let edit = makeActionButton("編集", label: "結果を編集"); edit.addTarget(self, action: #selector(editResult), for: .touchUpInside)
        let regenerate = makeActionButton("再生成", label: "結果を端末内で再生成"); regenerate.addTarget(self, action: #selector(regenerateResult), for: .touchUpInside)
        let copy = makeActionButton("コピー", label: "結果をクリップボードへコピー"); copy.addTarget(self, action: #selector(copyResult), for: .touchUpInside)
        let apply = makeActionButton("適用", label: "結果を入力欄へ適用"); apply.addTarget(self, action: #selector(applyResult), for: .touchUpInside)
        let cancel = makeActionButton("キャンセル", label: "結果をキャンセル"); cancel.addTarget(self, action: #selector(cancelAction), for: .touchUpInside)
        let row1 = UIStackView(arrangedSubviews: [edit, regenerate, copy]); row1.axis = .horizontal; row1.spacing = 6; row1.distribution = .fillEqually
        let row2 = UIStackView(arrangedSubviews: [cancel, apply]); row2.axis = .horizontal; row2.spacing = 6; row2.distribution = .fillEqually
        let editorKeyboard = makeEditorKeyboard(for: resultTextView, requiresEditable: true)
        let stack = UIStackView(arrangedSubviews: [title, hint, resultTextView, editorKeyboard, row1, row2]); stack.axis = .vertical; stack.spacing = 7; stack.isLayoutMarginsRelativeArrangement = true; stack.layoutMargins = UIEdgeInsets(top: 7, left: 10, bottom: 7, right: 10)
        resultTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 76).isActive = true
        install(stack, height: 456)
        postScreenChange(title)
    }

    @objc private func editResult() { resultTextView.isEditable = true; resultTextView.becomeFirstResponder(); transition(.editResult) }

    @objc private func regenerateResult() {
        guard shortcutActivationStillCurrent(), let draft = captureDraft else { presentRecoverableError(.staleField); return }
        let regenerated: RewriteResult?
        if let skill = pendingShortcutSkill {
            regenerated = LocalSkillExecutor.execute(skill, input: draft.text)
        } else {
            regenerated = LocalRewriteEngine().politeRewrite(draft.text)
        }
        guard let regenerated else {
            recordNativeSkillFailureIfNeeded()
            refreshShortcutSnapshot()
            return
        }
        guard regenerated.rewritten.count <= LocalTextLimits.resultCharacters else {
            presentRecoverableError(.resultTooLarge)
            return
        }
        recordNativeSkillSuccessIfNeeded()
        guard shortcutActivationStillCurrent() else { presentRecoverableError(.staleField); return }
        let result = RewriteResult(original: regenerated.original, rewritten: regenerated.rewritten, preservedEntities: regenerated.preservedEntities, fieldFingerprint: draft.fieldFingerprint, documentIdentifier: draft.documentIdentifier)
        resultTextView.text = result.rewritten
        resultTextView.selectedRange = NSRange(location: (result.rewritten as NSString).length, length: 0)
        transition(.updateRewrite(result))
    }

    @objc private func copyResult() {
        guard shortcutActivationStillCurrent() else { presentRecoverableError(.staleField); return }
        let proposed = resultTextView.text ?? ""
        guard proposed.count <= LocalTextLimits.resultCharacters else { presentRecoverableError(.resultTooLarge); return }
        UIPasteboard.general.string = proposed
        transition(.copyResult)
    }

    @objc private func applyResult() {
        guard shortcutActivationStillCurrent() else { presentRecoverableError(.staleField); return }
        guard let draft = captureDraft, let result = currentResult() else { return }
        let proposed = resultTextView.text ?? ""
        guard proposed.count <= LocalTextLimits.resultCharacters else { presentRecoverableError(.resultTooLarge); return }
        guard result.preservedEntities.allSatisfy({ proposed.contains($0) }) else { presentRecoverableError(.protectedEntityChanged); return }
        // UIInputViewController can replace the active selection, but it has no
        // atomic API for replacing an arbitrary before/after context window.
        // Inserting here would duplicate the original text. Keep Copy available
        // and fail closed until a range-authoritative host handoff exists.
        guard draft.source != .surroundingContext else {
            presentRecoverableError(.surroundingContextApplyUnavailable)
            return
        }
        if draft.source != .selection, !(textDocumentProxy.selectedText ?? "").isEmpty {
            presentRecoverableError(.activeSelectionNotApproved)
            return
        }
        let effectiveResult = RewriteResult(original: result.original, rewritten: proposed, preservedEntities: result.preservedEntities, fieldFingerprint: result.fieldFingerprint, documentIdentifier: result.documentIdentifier)
        transition(.updateRewrite(effectiveResult))
        let expectedBefore = (textDocumentProxy.documentContextBeforeInput ?? "") + proposed
        let expectedAfter = textDocumentProxy.documentContextAfterInput ?? ""
        let expectedAppliedFingerprint = locking.selectionFingerprint(selectedText: "", before: expectedBefore, after: expectedAfter)
        let snapshot = EditorSnapshot(documentIdentifier: documentIdentifier, fieldFingerprint: currentTargetFingerprint(for: draft.source), expectedAppliedFingerprint: expectedAppliedFingerprint)
        transition(.applyResultWithSnapshot(snapshot))
        guard case .applied(let token) = machine.screen else { return }
        guard shortcutActivationStillCurrent() else { presentRecoverableError(.staleField); return }
        textDocumentProxy.insertText(proposed)
        showUndoView(token)
    }

    private func showUndoView(_ token: UndoToken) {
        let title = UILabel(); title.text = "適用しました"; title.font = .preferredFont(forTextStyle: .headline); title.adjustsFontForContentSizeCategory = true; title.accessibilityTraits = .header
        let detail = UILabel(); detail.text = "入力欄が変わるとUndoは無効になります。"; detail.textColor = .secondaryLabel; detail.numberOfLines = 0; detail.font = .preferredFont(forTextStyle: .body); detail.adjustsFontForContentSizeCategory = true
        let undo = makeActionButton("Undo", label: "元の選択範囲を復元"); undo.addTarget(self, action: #selector(undoResult), for: .touchUpInside)
        let done = makeActionButton("完了", label: "キーボードへ戻る"); done.addTarget(self, action: #selector(cancelAction), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [title, detail, undo, done]); stack.axis = .vertical; stack.spacing = 8; stack.isLayoutMarginsRelativeArrangement = true; stack.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        install(stack, height: 252)
        postScreenChange(title)
    }

    @objc private func undoResult() {
        guard shortcutActivationStillCurrent() else { presentRecoverableError(.staleField); return }
        guard case .applied(let token) = machine.screen else { return }
        guard (textDocumentProxy.documentContextBeforeInput ?? "").hasSuffix(token.rewritten) else { transition(.fail(.staleField)); return }
        let snapshot = EditorSnapshot(documentIdentifier: documentIdentifier, fieldFingerprint: currentAppliedFingerprint())
        transition(.undoWithSnapshot(snapshot))
        guard case .typing = machine.screen else { return }
        for _ in token.rewritten { textDocumentProxy.deleteBackward() }
        if hasSelectionCapture { textDocumentProxy.insertText(token.original) }
        showTyping()
    }

    private func currentResult() -> RewriteResult? {
        guard case .resultReview(let result) = machine.screen else { return nil }
        return result
    }

    private func currentTargetFingerprint(for source: CaptureSource) -> String {
        if source == .selection, let selected = textDocumentProxy.selectedText {
            return locking.selectionFingerprint(selectedText: selected, before: textDocumentProxy.documentContextBeforeInput ?? "", after: textDocumentProxy.documentContextAfterInput ?? "")
        }
        return locking.fingerprint((textDocumentProxy.documentContextBeforeInput ?? "") + (textDocumentProxy.documentContextAfterInput ?? ""))
    }

    /// Fingerprint for an already-applied edit at the current insertion point.
    /// Apply prediction, textDidChange acknowledgement, and Undo must use this
    /// exact format or a successful insertion would revoke its own Undo token.
    private func currentAppliedFingerprint() -> String {
        locking.selectionFingerprint(
            selectedText: "",
            before: textDocumentProxy.documentContextBeforeInput ?? "",
            after: textDocumentProxy.documentContextAfterInput ?? ""
        )
    }

    private func makeExactContentView(_ title: String, value: String) -> UIStackView {
        let heading = UILabel()
        heading.text = title
        heading.font = .preferredFont(forTextStyle: .footnote)
        heading.adjustsFontForContentSizeCategory = true

        let textView = UITextView()
        textView.text = value
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.backgroundColor = .secondarySystemBackground
        textView.layer.cornerRadius = 8
        textView.layer.borderWidth = 0.5
        textView.layer.borderColor = UIColor.separator.cgColor
        textView.accessibilityLabel = title
        textView.accessibilityValue = value
        textView.accessibilityHint = "全文をスクロールして確認できます"
        textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 104).isActive = true

        let stack = UIStackView(arrangedSubviews: [heading, textView])
        stack.axis = .vertical
        stack.spacing = 4
        return stack
    }

    private func makePreviewLabel(_ title: String, value: String) -> UILabel {
        let label = UILabel(); label.text = "\(title): \(value)"; label.numberOfLines = 2; label.font = .preferredFont(forTextStyle: .footnote); label.adjustsFontForContentSizeCategory = true; label.accessibilityLabel = "\(title)。\(value)"; return label
    }

    private func makeActionButton(_ title: String, label: String) -> UIButton {
        let button = UIButton(type: .system); button.setTitle(title, for: .normal); button.accessibilityLabel = label; button.titleLabel?.font = .preferredFont(forTextStyle: .body); button.titleLabel?.adjustsFontForContentSizeCategory = true; button.backgroundColor = .systemBackground; button.layer.cornerRadius = 7; button.layer.borderWidth = 0.5; button.layer.borderColor = UIColor.separator.cgColor; button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true; return button
    }

    private func makeEditorKeyboard(for textView: UITextView, requiresEditable: Bool = false) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 3
        for letters in OrdinaryKeyboardLayout.letterRows {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 2
            row.distribution = .fillEqually
            for letter in letters {
                let value = String(letter)
                let button = makeUtilityButton("editor-letter-\(value)", title: value, label: "\(value)を編集欄へ入力")
                button.addAction(UIAction { [weak self, weak textView] _ in
                    guard let self, let textView, !requiresEditable || textView.isEditable else { return }
                    self.replaceEditorSelection(in: textView, with: value)
                }, for: .touchUpInside)
                row.addArrangedSubview(button)
            }
            stack.addArrangedSubview(row)
        }
        let controls = UIStackView()
        controls.axis = .horizontal
        controls.spacing = 3
        controls.distribution = .fillEqually
        let space = makeUtilityButton("editor-space", title: "空白", label: "編集欄へスペースを入力")
        space.addAction(UIAction { [weak self, weak textView] _ in
            guard let self, let textView, !requiresEditable || textView.isEditable else { return }
            self.replaceEditorSelection(in: textView, with: " ")
        }, for: .touchUpInside)
        let delete = makeUtilityButton("editor-delete", title: "⌫", label: "編集欄の文字を削除")
        delete.addAction(UIAction { [weak self, weak textView] _ in
            guard let self, let textView, !requiresEditable || textView.isEditable else { return }
            self.deleteEditorSelection(in: textView)
        }, for: .touchUpInside)
        controls.addArrangedSubview(space)
        controls.addArrangedSubview(delete)
        stack.addArrangedSubview(controls)
        return stack
    }

    private func replaceEditorSelection(in textView: UITextView, with replacement: String) {
        let current = (textView.text ?? "") as NSString
        let selection = textView.selectedRange.location == NSNotFound ? NSRange(location: current.length, length: 0) : textView.selectedRange
        textView.text = current.replacingCharacters(in: selection, with: replacement)
        textView.selectedRange = NSRange(location: selection.location + (replacement as NSString).length, length: 0)
    }

    private func deleteEditorSelection(in textView: UITextView) {
        let current = (textView.text ?? "") as NSString
        var selection = textView.selectedRange.location == NSNotFound ? NSRange(location: current.length, length: 0) : textView.selectedRange
        if selection.length == 0 && selection.location > 0 {
            selection = current.rangeOfComposedCharacterSequence(at: selection.location - 1)
        }
        guard selection.length > 0 else { return }
        textView.text = current.replacingCharacters(in: selection, with: "")
        textView.selectedRange = NSRange(location: selection.location, length: 0)
    }

    private func presentRecoverableError(_ error: KeyboardError) {
        statusLabel.text = error.recoveryMessage
        statusLabel.accessibilityValue = error.recoveryMessage
        UIAccessibility.post(notification: .announcement, argument: error.recoveryMessage)
    }

    private func postScreenChange(_ target: UIView) {
        DispatchQueue.main.async {
            UIAccessibility.post(notification: .screenChanged, argument: target)
        }
    }

    private func install(_ content: UIView, height: CGFloat) {
        view.subviews.forEach { $0.removeFromSuperview() }
        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = false
        scrollView.showsVerticalScrollIndicator = true
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        keyboardHeightConstraint?.isActive = false
        let heightConstraint = view.heightAnchor.constraint(equalToConstant: height)
        heightConstraint.priority = .required
        keyboardHeightConstraint = heightConstraint
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            heightConstraint
        ])
    }

    private func showTyping() {
        guard let typingStack else { return }
        isSkillPaletteVisible = false
        statusLabel.text = isFullAccessEnabled ? "入力" : "入力。Skill Keyはフルアクセスが必要"
        statusLabel.accessibilityValue = statusLabel.text
        actionButton.accessibilityLabel = "AIコマンドを開く（端末内）"
        actionButton.isEnabled = true
        install(typingStack, height: 252)
        postScreenChange(statusLabel)
    }

    @objc private func cancelAction() {
        transition(.cancel)
        clearEphemeralState(showTypingView: true)
    }

    /// Command and result editors can contain user text that is not present in
    /// the host document. Every terminal/invalidation path must erase it, drop
    /// the selection, and release first responder ownership.
    private func wipeEditorBuffers() {
        commandTextView.resignFirstResponder()
        resultTextView.resignFirstResponder()
        commandTextView.selectedRange = NSRange(location: 0, length: 0)
        resultTextView.selectedRange = NSRange(location: 0, length: 0)
        commandTextView.text = nil
        resultTextView.text = nil
    }

    private func clearEphemeralState(showTypingView: Bool) {
        let existingLock: LockReason?
        if case .locked(let reason) = machine.screen { existingLock = reason } else { existingLock = nil }
        machine = KeyboardStateMachine()
        captureDraft = nil
        captureAcknowledged = false
        hasSelectionCapture = false
        pendingShortcutSkill = nil
        pendingShortcutActivation = nil
        consumedLongPressKey = nil
        longPressBeganKey = nil
        isSkillPaletteVisible = false
        wipeEditorBuffers()
        if showTypingView { showTyping() }
        if let existingLock {
            transition(.lock(existingLock))
            actionButton.isHidden = true
        }
    }

    private func shortcutActivationStillCurrent(now: Date = Date()) -> Bool {
        guard let activation = pendingShortcutActivation else { return true }
        guard isFullAccessEnabled else { return false }
        guard activation.editorSessionID == documentIdentifier, activation.expiresAt >= now,
              let current = shortcutStore.loadLastKnownGood(), current.generation == activation.snapshotGeneration,
              current.deviceID == activation.deviceID else {
            applyShortcutSnapshot(nil)
            return false
        }
        guard let boundary = shortcutStore.loadActiveBoundary() else {
            applyShortcutSnapshot(nil)
            return false
        }
        let binding = current.bindings.first {
            $0.id == activation.bindingID && $0.skillID == activation.skillID && $0.versionID == activation.versionID &&
            $0.skillDigest == activation.skillDigest && $0.enabled
        }
        let isCurrent = binding.map { nativeSkillFailureStore.decision(for: $0, boundary: boundary) == .allowed } ?? false
        if !isCurrent { applyShortcutSnapshot(nil) }
        return isCurrent
    }

    private func activeNativeSkillContext() -> (ShortcutBindingV1, ShortcutAccountBoundaryV1)? {
        guard let activation = pendingShortcutActivation,
              let boundary = shortcutStore.loadActiveBoundary(),
              let snapshot = shortcutStore.loadLastKnownGood(),
              snapshot.generation == activation.snapshotGeneration,
              let binding = snapshot.bindings.first(where: {
                  $0.id == activation.bindingID && $0.skillID == activation.skillID && $0.versionID == activation.versionID &&
                  $0.skillDigest == activation.skillDigest && $0.enabled
              }) else { return nil }
        return (binding, boundary)
    }

    private func recordNativeSkillFailureIfNeeded() {
        guard let (binding, boundary) = activeNativeSkillContext() else { return }
        _ = try? nativeSkillFailureStore.recordFailure(for: binding, boundary: boundary)
    }

    private func recordNativeSkillSuccessIfNeeded() {
        guard let (binding, boundary) = activeNativeSkillContext() else { return }
        try? nativeSkillFailureStore.recordSuccess(for: binding, boundary: boundary)
    }

    private func transition(_ action: KeyboardAction) {
        let screen = machine.send(action)
        switch screen {
        case .typing: statusLabel.text = isFullAccessEnabled ? "入力" : "入力。Skill Keyはフルアクセスが必要"; actionButton.isEnabled = true
        case .command: statusLabel.text = "コマンド"; actionButton.accessibilityLabel = "コマンドをキャンセル"; actionButton.isEnabled = true
        case .captureReview: statusLabel.text = "確認"; actionButton.isEnabled = true
        case .resultReview: statusLabel.text = "結果"; actionButton.isEnabled = true
        case .applied: statusLabel.text = "適用済み"; actionButton.isEnabled = false
        case .locked(let reason): statusLabel.text = reason.accessibilityLabel; actionButton.isEnabled = false
        case .error(let error): statusLabel.text = error.recoveryMessage; actionButton.isEnabled = true
        default: statusLabel.text = "処理中"; actionButton.isEnabled = true
        }
        statusLabel.accessibilityValue = statusLabel.text
    }

    /// A document/field transition invalidates capture, result and undo state. An Apply callback
    /// is accepted only when the resulting document identity and whole-field fingerprint match.
    func textDidChange(_ textInput: UITextInput) {
        consumedLongPressKey = nil
        longPressBeganKey = nil
        updateReturnKeyPresentation()
        refreshFieldSecurityFromProxy()
        if isSkillPaletteVisible {
            showTyping()
            return
        }
        if case .applied(let token) = machine.screen {
            let identityMatches = token.documentIdentifier == nil || token.documentIdentifier == documentIdentifier
            if identityMatches && currentAppliedFingerprint() == token.appliedFingerprint { return }
        }
        if case .typing = machine.screen { return }
        if case .locked = machine.screen { return }
        clearEphemeralState(showTypingView: true)
    }

    /// Host/adapter integrations call this with OS input traits before showing AI controls.
    func updateFieldSecurity(_ context: FieldSecurityContext) {
        if let reason = policy.lockReason(for: context) {
            clearEphemeralState(showTypingView: true)
            transition(.lock(reason))
            actionButton.isHidden = true
            updateBoundKeyPresentation()
        } else if case .locked = machine.screen {
            transition(.unlock)
            actionButton.isHidden = false
            showTyping()
            updateBoundKeyPresentation()
        }
    }

    private func refreshFieldSecurityFromProxy() {
        let keyboardType: String?
        switch textDocumentProxy.keyboardType {
        case .asciiCapableNumberPad: keyboardType = "asciiCapableNumberPad"
        case .phonePad: keyboardType = "phonePad"
        case .numberPad: keyboardType = "numberPad"
        case .decimalPad: keyboardType = "decimalPad"
        default: keyboardType = nil
        }
        updateFieldSecurity(FieldSecurityContext(
            // UIKit exposes this trait as optional through the document proxy;
            // nil means the host did not mark the field secure. Explicit
            // sensitive content types below still fail closed.
            isSecureTextEntry: textDocumentProxy.isSecureTextEntry ?? false,
            textContentType: textDocumentProxy.textContentType?.rawValue,
            keyboardType: keyboardType
        ))
    }

    private var keyMinimumHeight: CGFloat {
        switch keyboardSettings.keySize {
        case .compact: return 44
        case .standard: return 48
        case .large: return 52
        }
    }

    private var keyboardHeight: CGFloat {
        switch keyboardSettings.keySize {
        case .compact: return 240
        case .standard: return 260
        case .large: return 284
        }
    }

    private func reloadKeyboardSettings() {
        keyboardSettings = settingsStore.load()
        switch keyboardSettings.theme {
        case .system: overrideUserInterfaceStyle = .unspecified
        case .light: overrideUserInterfaceStyle = .light
        case .dark: overrideUserInterfaceStyle = .dark
        }
        view.backgroundColor = .secondarySystemBackground
    }

    private func performKeyHaptic() {
        guard keyboardSettings.hapticsEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

private extension UIStackView {
    convenience init(axis: NSLayoutConstraint.Axis, spacing: CGFloat) {
        self.init(); self.axis = axis; self.spacing = spacing
    }
}
