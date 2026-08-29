import SwiftUI
import UIKit
import MobileAIKeyboardCore

struct OnboardingView: View {
    private enum Stage: Int, CaseIterable { case welcome, tryIt, access }

    @State private var stage: Stage
    @State private var accessStatus: KeyboardAccessStatus?
    @State private var showAccessDetails = false
    @State private var sample = "明日の会議、よろしく"
    @State private var refinedSample: String?
    @State private var settingsWasOpened = false
    @State private var settingsOpenError: String?
    @State private var verificationText = ""
    @FocusState private var verificationFocused: Bool
    @AppStorage("mobileAIKeyboard.onboardingComplete") private var onboardingComplete = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountStore: AccountActivityStore
    @EnvironmentObject private var shortcutRegistry: ShortcutRegistryStore
    private let accessStatusStore = AppGroupKeyboardAccessStatusStore()
    private let startsAtAccess: Bool

    init(startsAtAccess: Bool = false) {
        self.startsAtAccess = startsAtAccess
        _stage = State(initialValue: startsAtAccess ? .access : .welcome)
    }

    private var forcesOnboarding: Bool {
        startsAtAccess || ProcessInfo.processInfo.arguments.contains("-onboarding-qa") ||
        ProcessInfo.processInfo.arguments.contains("-onboarding-access-qa")
    }

    var body: some View {
        Group {
            if onboardingComplete && !forcesOnboarding {
                AppShellView()
                    .environmentObject(accountStore)
                    .environmentObject(shortcutRegistry)
            } else {
                onboardingFlow
            }
        }
        .environmentObject(shortcutRegistry)
        .onAppear {
            accountStore.bindShortcutRegistry(shortcutRegistry)
            refreshAccessStatus()
            if ProcessInfo.processInfo.arguments.contains("-onboarding-access-qa") { stage = .access }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { refreshAccessStatus() }
        }
        .alert("Private Skill Keysを削除できませんでした", isPresented: Binding(
            get: { accountStore.shortcutBoundaryError != nil },
            set: { if !$0 { accountStore.dismissShortcutBoundaryError() } }
        )) {
            Button("閉じる", role: .cancel) {}
        } message: {
            Text("\(accountStore.shortcutBoundaryError ?? "不明なエラー")。キーボードのフルアクセスを無効にしてから再試行してください。")
        }
    }

    private var onboardingFlow: some View {
        ZStack {
            OnboardingPalette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                onboardingHeader
                TabView(selection: $stage) {
                    welcomePage.tag(Stage.welcome)
                    tryItPage.tag(Stage.tryIt)
                    accessPage.tag(Stage.access)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.spring(response: 0.35, dampingFraction: 0.86), value: stage)
            }
        }
        .sheet(isPresented: $showAccessDetails) {
            AccessExplanationSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        // The reference onboarding is a deliberately light, cool-grey visual
        // system. Several cards use fixed white surfaces, so allowing only the
        // semantic foreground colors to flip in Dark Mode makes the entire
        // first-run experience appear blank. Keep this flow internally
        // consistent; the keyboard itself still follows the user's theme.
        .preferredColorScheme(.light)
    }

    private var onboardingHeader: some View {
        HStack(spacing: 14) {
            if stage != .welcome {
                Button {
                    withAnimation { stage = Stage(rawValue: stage.rawValue - 1) ?? .welcome }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.bold))
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.88), in: Circle())
                }
                .foregroundStyle(.primary)
                .accessibilityLabel("戻る")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
            Spacer()
            HStack(spacing: 7) {
                ForEach(Stage.allCases, id: \.rawValue) { item in
                    Capsule()
                        .fill(item == stage ? Color.primary : Color.primary.opacity(0.14))
                        .frame(width: item == stage ? 28 : 8, height: 8)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("オンボーディング \(stage.rawValue + 1) / \(Stage.allCases.count)")
            Spacer()
            Button("あとで") { completeOnboarding() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 52, height: 44)
                .accessibilityHint("設定せずにSkill Keys画面へ進みます")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var welcomePage: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 10)
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.72))
                            .frame(width: min(proxy.size.width * 0.74, 310), height: min(proxy.size.width * 0.74, 310))
                            .shadow(color: .cyan.opacity(0.18), radius: 36, y: 18)
                        KeyboardPreview().padding(.horizontal, 30)
                    }
                    VStack(spacing: 10) {
                        Text("どこで書いていても、\nAIを一打で。")
                            .font(.largeTitle.weight(.bold))
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.8)
                        Text("いつものキーボードに、あなたのSkillを。\n長押しするだけで、文章を整えられます。")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                    }
                    VStack(spacing: 12) {
                        PrimaryOnboardingButton(title: "まず試してみる", systemImage: "sparkles") {
                            withAnimation { stage = .tryIt }
                        }
                        .accessibilityIdentifier("onboarding-start")
                        Label("試すだけなら、アクセス許可は不要です", systemImage: "lock.shield")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
                .frame(minHeight: proxy.size.height)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var tryItPage: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("許可の前に、体験する")
                        .font(.largeTitle.weight(.bold))
                    Text("このデモは端末内だけで動きます。")
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .padding(.top, 30)
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label("入力", systemImage: "text.cursor").font(.headline)
                        Spacer()
                        Text("端末内")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.green.opacity(0.12), in: Capsule())
                            .foregroundStyle(.green)
                    }
                    TextEditor(text: $sample)
                        .font(.title3)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 96)
                        .padding(14)
                        .background(OnboardingPalette.field, in: RoundedRectangle(cornerRadius: 18))
                        .accessibilityLabel("整える文章")
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { refinedSample = refine(sample) }
                    } label: {
                        Label(refinedSample == nil ? "丁寧に整える" : "もう一度整える", systemImage: "wand.and.stars")
                            .font(.headline)
                            .frame(maxWidth: .infinity).frame(height: 54)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(Color.primary, in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityIdentifier("onboarding-refine")
                    if let refinedSample {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("できました", systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(.green)
                            Text(refinedSample).font(.title3.weight(.medium))
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .accessibilityIdentifier("onboarding-refined-result")
                    }
                }
                .padding(20)
                .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 30))
                .shadow(color: .black.opacity(0.06), radius: 24, y: 12)
                .padding(.horizontal, 20)
                VStack(spacing: 12) {
                    PrimaryOnboardingButton(title: "キーボードを追加する", systemImage: "keyboard") {
                        withAnimation { stage = .access }
                    }
                    .accessibilityIdentifier("onboarding-continue-to-access")
                    Text("次は約1分。設定はいつでも解除できます。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24).padding(.bottom, 28)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
    }

    private var accessPage: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 8) {
                    ZStack {
                        Circle().fill(Color.cyan.opacity(0.13)).frame(width: 82, height: 82)
                        Image(systemName: accessIsReady ? "checkmark" : "keyboard")
                            .font(.system(size: 34, weight: .semibold))
                    }
                    .foregroundStyle(accessIsReady ? .green : .primary)
                    Text(accessIsReady ? "準備できました" : "キーボードを有効にする")
                        .font(.largeTitle.weight(.bold))
                    Text(accessIsReady ? "対応する入力欄でSkill Keyを使えます。\nパスワードなど安全な入力欄では自動で停止します。" : "iOSの設定で一度だけ有効にします。\n入力内容を勝手に送信することはありません。")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
                .padding(.top, 24)
                VStack(spacing: 0) {
                    AccessStepRow(number: 1, title: "iOS設定を開く", detail: "設定 → 一般 → キーボード → キーボードへ進む", isComplete: settingsWasOpened || accessIsReady)
                    Divider().padding(.leading, 64)
                    AccessStepRow(number: 2, title: "キーボードを追加", detail: "新しいキーボードを追加 → Mobile AI Keyboard → フルアクセスをオン", isComplete: accessIsReady)
                    Divider().padding(.leading, 64)
                    AccessStepRow(number: 3, title: "この画面で試す", detail: "入力欄をタップし、地球儀からMobile AI Keyboardを選択", isComplete: accessIsReady)
                }
                .padding(.vertical, 6)
                .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 28))
                .shadow(color: .black.opacity(0.05), radius: 22, y: 10)
                .padding(.horizontal, 20)
                Button { showAccessDetails = true } label: {
                    Label("フルアクセスが必要な理由", systemImage: "lock.shield")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.primary).frame(minHeight: 44)
                .accessibilityIdentifier("onboarding-access-details")
                if let settingsOpenError {
                    Label(settingsOpenError, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.medium)).foregroundStyle(.orange)
                        .padding(.horizontal, 24)
                }
                if settingsWasOpened && !accessIsReady {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("設定から戻ったら、ここで確認", systemImage: "keyboard")
                            .font(.headline)
                        TextField("ここをタップして、地球儀から切り替える", text: $verificationText)
                            .focused($verificationFocused)
                            .textFieldStyle(.roundedBorder)
                            .frame(minHeight: 48)
                            .accessibilityIdentifier("onboarding-keyboard-verification")
                            .onChange(of: verificationText) { _ in refreshAccessStatus() }
                        Text("Mobile AI Keyboardが表示されたら、設定は完了です。文字を1つ入力すると自動で確認します。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 20))
                    .padding(.horizontal, 20)
                }
                VStack(spacing: 12) {
                    if accessIsReady {
                        PrimaryOnboardingButton(title: "Skill Keysをはじめる", systemImage: "sparkles") { completeOnboarding() }
                            .accessibilityIdentifier("onboarding-finish")
                    } else {
                        PrimaryOnboardingButton(title: settingsWasOpened ? "iOS設定をもう一度開く" : "iOS設定を開く", systemImage: "arrow.up.forward.app") { openSettings() }
                            .accessibilityIdentifier("onboarding-open-settings")
                        Button("設定できたか確認") { refreshAccessStatus() }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.primary).frame(minHeight: 44)
                            .accessibilityIdentifier("onboarding-refresh-access")
                    }
                    Button("今はスキップ") { completeOnboarding() }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).frame(minHeight: 44)
                        .accessibilityHint("通常入力とアプリ内機能は後から試せます")
                }
                .padding(.horizontal, 24).padding(.bottom, 28)
            }
        }
        .scrollIndicators(.hidden)
    }

    private var accessIsReady: Bool {
        accessStatus?.isFresh() == true && accessStatus?.fullAccessEnabled == true && accessStatus?.appGroupAvailable == true
    }

    private func openSettings() {
        verificationFocused = false
        accessStatusStore.invalidate()
        accessStatus = nil
        settingsOpenError = nil
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            settingsOpenError = "iOS設定を開けませんでした。もう一度お試しください。"
            return
        }
        UIApplication.shared.open(url, options: [:]) { opened in
            DispatchQueue.main.async {
                settingsWasOpened = opened
                if !opened { settingsOpenError = "iOS設定を開けませんでした。もう一度お試しください。" }
            }
        }
    }

    private func refreshAccessStatus() { accessStatus = accessStatusStore.load() }
    private func completeOnboarding() {
        if startsAtAccess { dismiss() }
        else { onboardingComplete = true }
    }

    private func refine(_ value: String) -> String {
        LocalRewriteEngine().politeRewrite(value)?.rewritten ?? "文章を入力してください。"
    }
}

private enum OnboardingPalette {
    static let background = Color(red: 0.94, green: 0.96, blue: 0.98)
    static let field = Color(red: 0.95, green: 0.96, blue: 0.98)
}

private struct PrimaryOnboardingButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 58)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain).foregroundStyle(.white)
        .background(Color.primary, in: Capsule()).contentShape(Capsule())
    }
}

private struct AccessStepRow: View {
    let number: Int
    let title: String
    let detail: String
    let isComplete: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(isComplete ? Color.green : Color.primary).frame(width: 34, height: 34)
                Image(systemName: isComplete ? "checkmark" : "\(number).circle.fill")
                    .font(.subheadline.weight(.bold)).foregroundStyle(.white)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("手順\(number)、\(title)。\(detail)。\(isComplete ? "完了" : "未完了")")
    }
}

private struct KeyboardPreview: View {
    private let rows = [["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"], ["A", "S", "D", "F", "G", "H", "J", "K", "L"], ["Z", "X", "C", "V", "B", "N", "M"]]
    var body: some View {
        VStack(spacing: 7) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 5) {
                    ForEach(row, id: \.self) { key in
                        Text(key).font(.caption2.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 30)
                            .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(alignment: .bottom) {
                                if key == "H" || key == "M" { Capsule().fill(.cyan).frame(width: 18, height: 2) }
                            }
                    }
                }
                .padding(.horizontal, row.count == 9 ? 10 : row.count == 7 ? 24 : 0)
            }
            HStack(spacing: 6) {
                Image(systemName: "globe").frame(width: 42, height: 34).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 9))
                HStack { Image(systemName: "sparkles"); Spacer(); Text("AI").font(.caption.weight(.semibold)) }
                    .foregroundStyle(.secondary).padding(.horizontal, 12).frame(maxWidth: .infinity).frame(height: 34)
                    .background(LinearGradient(colors: [.cyan.opacity(0.12), .purple.opacity(0.12)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 9))
                Image(systemName: "return").frame(width: 42, height: 34).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 9))
            }
        }
        .padding(12).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.85), lineWidth: 1) }
        .shadow(color: .black.opacity(0.08), radius: 20, y: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Skill Keyが割り当てられたAIキーボードのプレビュー")
    }
}

private struct AccessExplanationSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Skill Keyの設定を、アプリとキーボードの間で共有するために使います。")
                        .font(.title2.bold())
                    explanationRow(icon: "checkmark.shield", title: "勝手に送信しません", detail: "AIを実行する前に、対象の文章と処理内容を確認できます。")
                    explanationRow(icon: "eye.slash", title: "パスワード欄では停止", detail: "安全な入力欄ではSkill KeyとAI機能を表示しません。")
                    explanationRow(icon: "arrow.uturn.backward", title: "いつでも解除できます", detail: "iOSの設定からフルアクセスをオフにできます。通常入力はそのまま使えます。")
                    DisclosureGroup("共有するデータの詳細") {
                        Text("共有するのはキー割り当て、Skillの識別情報、表示名、接続状態です。入力本文、生成結果、prompt、token、資格情報は設定領域に保存しません。")
                            .font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
                    }
                    .font(.subheadline.weight(.semibold)).padding(16)
                    .background(OnboardingPalette.field, in: RoundedRectangle(cornerRadius: 16))
                }
                .padding(24)
            }
            .navigationTitle("フルアクセスについて")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
        }
    }

    private func explanationRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title3).frame(width: 42, height: 42).background(Color.cyan.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
