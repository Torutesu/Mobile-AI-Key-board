import UIKit
import MobileAIKeyboardCore

/// Native keyboard foundation and W2 local text-action vertical slice.
/// Ordinary key values are committed directly to UITextDocumentProxy; no key value is logged,
/// retained, or sent to a network service.
final class KeyboardViewController: UIInputViewController {
    private var machine = KeyboardStateMachine()
    private let policy = SensitiveFieldPolicy()
    private let engine = LocalRewriteEngine()
    private let redactor = LocalRedactor()
    private let locking = EntityLocking()
    private let statusLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private let shiftButton = UIButton(type: .system)
    private var letterButtons: [UIButton] = []
    private var isShifted = false
    private var typingStack: UIStackView?
    private var commandTextView = UITextView()
    private var resultTextView = UITextView()
    private var selectedSource: CaptureSource = .command
    private var captureDraft: CaptureDraft?
    private var captureAcknowledged = false
    private var hasSelectionCapture = false
    private var sourceButtons: [CaptureSource: UIButton] = [:]
    private var keyboardHeightConstraint: NSLayoutConstraint?
    private var documentIdentifier: String { textDocumentProxy.documentIdentifier.uuidString }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground
        buildTypingView()
        // iOS routes secure text fields to the system keyboard and does not expose their traits to
        // custom keyboards. For adapters that do receive traits, updateFieldSecurity(_:) is the
        // single policy gate before rendering command UI.
    }

    // MARK: Ordinary keyboard

    private func buildTypingView() {
        statusLabel.text = "入力"
        statusLabel.textAlignment = .center
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.accessibilityTraits = .header
        statusLabel.accessibilityLabel = "キーボードの状態"

        actionButton.setTitle("AI", for: .normal)
        actionButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        actionButton.accessibilityLabel = "AIコマンドを開く"
        actionButton.accessibilityHint = "文章を確認してから端末内で整えます。外部送信はありません"
        actionButton.addTarget(self, action: #selector(invoke), for: .touchUpInside)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(invokeLongPress(_:)))
        hold.minimumPressDuration = 0.45
        actionButton.addGestureRecognizer(hold)

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
        typingStack = stack
        install(stack, height: 252)
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
        let hint = UILabel()
        hint.text = "端末内で処理します。入力内容は外部送信しません。"
        hint.font = .preferredFont(forTextStyle: .footnote)
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
        let target = source == .selection ? (selected ?? "") : (before + after)
        let draft = CaptureDraft(text: text, source: source, fieldFingerprint: locking.fingerprint(target), redactedText: redaction.redacted, externalTransmissionAllowed: false, fallbackMessage: fallbackMessage, documentIdentifier: documentIdentifier)
        captureDraft = draft
        captureAcknowledged = false
        transition(.beginCapture(draft))
        showCaptureReview(draft, redactionBlocked: redaction.blocked)
    }

    private func showCaptureReview(_ draft: CaptureDraft, redactionBlocked: Bool) {
        let title = UILabel(); title.text = "送信内容の確認"; title.font = .preferredFont(forTextStyle: .headline)
        let exact = makePreviewLabel("入力内容（\(draft.characterCount)文字）", value: draft.text)
        let redacted = makePreviewLabel("ローカル検出後の表示", value: draft.redactedText)
        let destination = makePreviewLabel("送信先", value: "端末内のみ / 外部送信なし")
        let source = makePreviewLabel("入力ソース", value: draft.source == .command ? "コマンド" : draft.source.rawValue)
        let warning = UILabel(); warning.text = draft.fallbackMessage ?? (redactionBlocked ? "秘密情報候補を検出したため処理を停止します。" : "内容を確認してから続けてください。")
        warning.textColor = redactionBlocked ? .systemRed : .secondaryLabel; warning.numberOfLines = 0; warning.font = .preferredFont(forTextStyle: .footnote)
        let acknowledge = makeActionButton(captureAcknowledged ? "確認済み" : "内容を確認しました", label: "送信内容を確認しました")
        acknowledge.accessibilityValue = captureAcknowledged ? "オン" : "オフ"
        acknowledge.addTarget(self, action: #selector(acknowledgeCapture), for: .touchUpInside)
        let proceed = makeActionButton("端末内で丁寧に整える", label: "確認後に端末内で丁寧に整える")
        proceed.isEnabled = captureAcknowledged && !redactionBlocked
        proceed.addTarget(self, action: #selector(startLocalRewrite), for: .touchUpInside)
        let cancel = makeActionButton("キャンセル", label: "確認をキャンセル")
        cancel.addTarget(self, action: #selector(cancelAction), for: .touchUpInside)
        let buttons = UIStackView(arrangedSubviews: [cancel, acknowledge, proceed]); buttons.axis = .vertical; buttons.spacing = 6
        let stack = UIStackView(arrangedSubviews: [title, exact, redacted, source, destination, warning, buttons]); stack.axis = .vertical; stack.spacing = 7; stack.isLayoutMarginsRelativeArrangement = true; stack.layoutMargins = UIEdgeInsets(top: 7, left: 10, bottom: 7, right: 10)
        install(stack, height: 280)
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
        transition(.beginPlanning)
        guard let local = engine.politeRewrite(draft.text) else { transition(.fail(.emptyInput)); return }
        let result = RewriteResult(original: local.original, rewritten: local.rewritten, preservedEntities: local.preservedEntities, fieldFingerprint: draft.fieldFingerprint, documentIdentifier: draft.documentIdentifier)
        transition(.showRewrite(result))
        showResultReview(result)
    }

    private func showResultReview(_ result: RewriteResult) {
        resultTextView = UITextView(); resultTextView.text = result.rewritten; resultTextView.selectedRange = NSRange(location: (result.rewritten as NSString).length, length: 0); resultTextView.font = .preferredFont(forTextStyle: .body); resultTextView.isEditable = false; resultTextView.inputView = UIView(); resultTextView.accessibilityLabel = "書き換え結果"; resultTextView.layer.cornerRadius = 8; resultTextView.layer.borderWidth = 0.5; resultTextView.layer.borderColor = UIColor.separator.cgColor
        let title = UILabel(); title.text = "結果を確認"; title.font = .preferredFont(forTextStyle: .headline)
        let hint = UILabel(); hint.text = "編集・再生成・コピー・適用を選べます。適用前にentityを保護します。"; hint.textColor = .secondaryLabel; hint.numberOfLines = 0; hint.font = .preferredFont(forTextStyle: .footnote)
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
    }

    @objc private func editResult() { resultTextView.isEditable = true; resultTextView.becomeFirstResponder(); transition(.editResult) }

    @objc private func regenerateResult() {
        guard let draft = captureDraft, let regenerated = engine.politeRewrite(draft.text) else { return }
        let result = RewriteResult(original: regenerated.original, rewritten: regenerated.rewritten, preservedEntities: regenerated.preservedEntities, fieldFingerprint: draft.fieldFingerprint, documentIdentifier: draft.documentIdentifier)
        resultTextView.text = result.rewritten
        resultTextView.selectedRange = NSRange(location: (result.rewritten as NSString).length, length: 0)
        transition(.updateRewrite(result))
    }

    @objc private func copyResult() {
        let proposed = resultTextView.text ?? ""
        guard proposed.count <= LocalTextLimits.resultCharacters else { presentRecoverableError(.resultTooLarge); return }
        UIPasteboard.general.string = proposed
        transition(.copyResult)
    }

    @objc private func applyResult() {
        guard let draft = captureDraft, let result = currentResult() else { return }
        let proposed = resultTextView.text ?? ""
        guard proposed.count <= LocalTextLimits.resultCharacters else { presentRecoverableError(.resultTooLarge); return }
        guard result.preservedEntities.allSatisfy({ proposed.contains($0) }) else { presentRecoverableError(.protectedEntityChanged); return }
        if draft.source != .selection, !(textDocumentProxy.selectedText ?? "").isEmpty {
            presentRecoverableError(.activeSelectionNotApproved)
            return
        }
        let effectiveResult = RewriteResult(original: result.original, rewritten: proposed, preservedEntities: result.preservedEntities, fieldFingerprint: result.fieldFingerprint, documentIdentifier: result.documentIdentifier)
        transition(.updateRewrite(effectiveResult))
        let expectedAppliedField = (textDocumentProxy.documentContextBeforeInput ?? "") + proposed + (textDocumentProxy.documentContextAfterInput ?? "")
        let snapshot = EditorSnapshot(documentIdentifier: documentIdentifier, fieldFingerprint: currentTargetFingerprint(for: draft.source), expectedAppliedFingerprint: locking.fingerprint(expectedAppliedField))
        transition(.applyResultWithSnapshot(snapshot))
        guard case .applied(let token) = machine.screen else { return }
        textDocumentProxy.insertText(proposed)
        showUndoView(token)
    }

    private func showUndoView(_ token: UndoToken) {
        let title = UILabel(); title.text = "適用しました"; title.font = .preferredFont(forTextStyle: .headline)
        let detail = UILabel(); detail.text = "入力欄が変わるとUndoは無効になります。"; detail.textColor = .secondaryLabel; detail.numberOfLines = 0
        let undo = makeActionButton("Undo", label: "元の選択範囲を復元"); undo.addTarget(self, action: #selector(undoResult), for: .touchUpInside)
        let done = makeActionButton("完了", label: "キーボードへ戻る"); done.addTarget(self, action: #selector(cancelAction), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [title, detail, undo, done]); stack.axis = .vertical; stack.spacing = 8; stack.isLayoutMarginsRelativeArrangement = true; stack.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        install(stack, height: 252)
    }

    @objc private func undoResult() {
        guard case .applied(let token) = machine.screen else { return }
        guard (textDocumentProxy.documentContextBeforeInput ?? "").hasSuffix(token.rewritten) else { transition(.fail(.staleField)); return }
        let currentField = (textDocumentProxy.documentContextBeforeInput ?? "") + (textDocumentProxy.documentContextAfterInput ?? "")
        let snapshot = EditorSnapshot(documentIdentifier: documentIdentifier, fieldFingerprint: locking.fingerprint(currentField))
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
        if source == .selection, let selected = textDocumentProxy.selectedText { return locking.fingerprint(selected) }
        return locking.fingerprint((textDocumentProxy.documentContextBeforeInput ?? "") + (textDocumentProxy.documentContextAfterInput ?? ""))
    }

    private func makePreviewLabel(_ title: String, value: String) -> UILabel {
        let label = UILabel(); label.text = "\(title): \(value)"; label.numberOfLines = 2; label.font = .preferredFont(forTextStyle: .footnote); label.accessibilityLabel = "\(title)。\(value)"; return label
    }

    private func makeActionButton(_ title: String, label: String) -> UIButton {
        let button = UIButton(type: .system); button.setTitle(title, for: .normal); button.accessibilityLabel = label; button.titleLabel?.font = .preferredFont(forTextStyle: .body); button.backgroundColor = .systemBackground; button.layer.cornerRadius = 7; button.layer.borderWidth = 0.5; button.layer.borderColor = UIColor.separator.cgColor; button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true; return button
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
        statusLabel.text = "入力"; statusLabel.accessibilityValue = "入力"; actionButton.accessibilityLabel = "AIコマンドを開く"; actionButton.isEnabled = true; install(typingStack, height: 252)
    }

    @objc private func cancelAction() { transition(.cancel); captureDraft = nil; captureAcknowledged = false; hasSelectionCapture = false; showTyping() }

    private func transition(_ action: KeyboardAction) {
        let screen = machine.send(action)
        switch screen {
        case .typing: statusLabel.text = "入力"; actionButton.isEnabled = true
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
        if case .applied(let token) = machine.screen {
            let currentField = (textDocumentProxy.documentContextBeforeInput ?? "") + (textDocumentProxy.documentContextAfterInput ?? "")
            let identityMatches = token.documentIdentifier == nil || token.documentIdentifier == documentIdentifier
            if identityMatches && locking.fingerprint(currentField) == token.appliedFingerprint { return }
        }
        if case .typing = machine.screen { return }
        if case .locked = machine.screen { return }
        machine = KeyboardStateMachine(); captureDraft = nil; captureAcknowledged = false; hasSelectionCapture = false; showTyping()
    }

    /// Host/adapter integrations call this with OS input traits before showing AI controls.
    func updateFieldSecurity(_ context: FieldSecurityContext) {
        if let reason = policy.lockReason(for: context) { transition(.lock(reason)) }
        else if case .locked = machine.screen { transition(.unlock) }
    }
}

private extension UIStackView {
    convenience init(axis: NSLayoutConstraint.Axis, spacing: CGFloat) {
        self.init(); self.axis = axis; self.spacing = spacing
    }
}
