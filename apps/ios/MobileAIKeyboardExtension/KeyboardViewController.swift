import UIKit
import MobileAIKeyboardCore

/// Minimal ordinary keyboard foundation. All key events are committed directly to the host
/// document proxy; no key value is sent to telemetry or a network service.
final class KeyboardViewController: UIInputViewController {
    private var machine = KeyboardStateMachine()
    private let policy = SensitiveFieldPolicy()
    private let statusLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private let shiftButton = UIButton(type: .system)
    private var letterButtons: [UIButton] = []
    private var isShifted = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground
        buildView()
        // iOS routes secure text fields to the system keyboard and does not expose their traits to
        // custom keyboards. For adapters that do receive traits, updateFieldSecurity(_:) is the
        // single policy gate before rendering command UI.
    }

    private func buildView() {
        statusLabel.text = "入力"
        statusLabel.textAlignment = .center
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.accessibilityTraits = .header
        statusLabel.accessibilityLabel = "キーボードの状態"

        actionButton.setTitle("AI", for: .normal)
        actionButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        actionButton.accessibilityLabel = "AIコマンドを開く"
        actionButton.accessibilityHint = "文章を確認してから端末内または許可された処理を開始します"
        actionButton.addTarget(self, action: #selector(invoke), for: .touchUpInside)

        let header = UIStackView(arrangedSubviews: [statusLabel, actionButton])
        header.axis = .horizontal
        header.alignment = .center
        header.distribution = .equalSpacing
        header.isLayoutMarginsRelativeArrangement = true
        header.layoutMargins = UIEdgeInsets(top: 2, left: 10, bottom: 2, right: 10)

        let first = makeLetterRow(OrdinaryKeyboardLayout.letterRows[0])
        let second = makeLetterRow(OrdinaryKeyboardLayout.letterRows[1])
        let third = makeLetterRow(OrdinaryKeyboardLayout.letterRows[2], leading: makeShiftButton(), trailing: makeDeleteButton())
        let bottom = makeBottomRow()
        let stack = UIStackView(arrangedSubviews: [header, first, second, third, bottom])
        stack.axis = .vertical
        stack.spacing = 4
        stack.distribution = .fillEqually
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)

        view.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 252)
        ])
    }

    private func makeLetterRow(_ letters: String, leading: UIView? = nil, trailing: UIView? = nil) -> UIStackView {
        var views: [UIView] = []
        if let leading { views.append(leading) }
        for letter in letters {
            let button = makeKey(String(letter))
            letterButtons.append(button)
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
        let spaceButton = makeUtilityButton("space", title: "空白", label: "スペース")
        spaceButton.addTarget(self, action: #selector(space), for: .touchUpInside)
        let returnButton = makeUtilityButton("return", title: "改行", label: "改行")
        returnButton.addTarget(self, action: #selector(returnKey), for: .touchUpInside)
        let row = UIStackView(arrangedSubviews: [globe, spaceButton, returnButton])
        row.axis = .horizontal
        row.spacing = 3
        row.distribution = .fillProportionally
        spaceButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 132).isActive = true
        return row
    }

    private func makeKey(_ letter: String) -> UIButton {
        let button = makeUtilityButton("letter-\(letter.lowercased())", title: letter, label: letter)
        button.addTarget(self, action: #selector(letterPressed(_:)), for: .touchUpInside)
        button.accessibilityHint = "入力欄に文字を入力"
        return button
    }

    private func makeShiftButton() -> UIButton {
        shiftButton.setTitle("⇧", for: .normal)
        shiftButton.accessibilityLabel = "シフト"
        shiftButton.accessibilityValue = "オフ"
        styleKey(shiftButton)
        shiftButton.addTarget(self, action: #selector(toggleShift), for: .touchUpInside)
        return shiftButton
    }

    private func makeDeleteButton() -> UIButton {
        let button = makeUtilityButton("delete", title: "⌫", label: "削除")
        button.addTarget(self, action: #selector(deleteBackward), for: .touchUpInside)
        return button
    }

    private func makeUtilityButton(_ identifier: String, title: String, label: String) -> UIButton {
        let button = UIButton(type: .system)
        button.accessibilityIdentifier = identifier
        button.accessibilityLabel = label
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .body)
        styleKey(button)
        return button
    }

    private func styleKey(_ button: UIButton) {
        button.backgroundColor = .systemBackground
        button.layer.cornerRadius = 6
        button.layer.borderWidth = 0.5
        button.layer.borderColor = UIColor.separator.cgColor
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    }

    @objc private func letterPressed(_ sender: UIButton) {
        guard let title = sender.currentTitle, title.count == 1 else { return }
        textDocumentProxy.insertText(title)
        if isShifted { isShifted = false; updateShiftAppearance() }
    }

    @objc private func toggleShift() {
        isShifted.toggle()
        updateShiftAppearance()
    }

    private func updateShiftAppearance() {
        for button in letterButtons {
            guard let value = button.currentTitle?.first else { continue }
            button.setTitle(String(isShifted ? value.uppercased() : value.lowercased()), for: .normal)
        }
        shiftButton.accessibilityValue = isShifted ? "オン" : "オフ"
        shiftButton.backgroundColor = isShifted ? .systemBlue.withAlphaComponent(0.2) : .systemBackground
    }

    @objc private func space() { textDocumentProxy.insertText(" ") }
    @objc private func returnKey() { textDocumentProxy.insertText("\n") }
    @objc private func deleteBackward() { textDocumentProxy.deleteBackward() }
    @objc private func nextKeyboard() { advanceToNextInputMode() }

    @objc private func invoke() {
        guard case .locked = machine.screen else {
            transition(.invokeCommand)
            return
        }
    }

    private func transition(_ action: KeyboardAction) {
        let screen = machine.send(action)
        switch screen {
        case .typing: statusLabel.text = "入力"; actionButton.isEnabled = true
        case .command: statusLabel.text = "コマンド"; actionButton.accessibilityLabel = "コマンドをキャンセル"; actionButton.isEnabled = true
        case .locked(let reason): statusLabel.text = reason.accessibilityLabel; actionButton.isEnabled = false
        case .error(let error): statusLabel.text = error.recoveryMessage; actionButton.isEnabled = true
        default: statusLabel.text = "確認中"; actionButton.isEnabled = true
        }
        statusLabel.accessibilityValue = statusLabel.text
    }

    /// A document/field transition invalidates all pending capture or result state. This is
    /// deliberately content-free and keeps stale text from crossing editor boundaries.
    func textDidChange(_ textInput: UITextInput) {
        if case .typing = machine.screen { return }
        if case .locked = machine.screen { return }
        machine = KeyboardStateMachine()
        statusLabel.text = "入力"
        actionButton.accessibilityLabel = "AIコマンドを開く"
        actionButton.isEnabled = true
    }

    /// Host/adapter integrations call this with OS input traits before showing AI controls.
    func updateFieldSecurity(_ context: FieldSecurityContext) {
        if let reason = policy.lockReason(for: context) { transition(.lock(reason)) }
        else if case .locked = machine.screen { transition(.unlock) }
    }
}
