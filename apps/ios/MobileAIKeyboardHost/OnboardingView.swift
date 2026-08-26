import SwiftUI
import UIKit
import MobileAIKeyboardCore

struct OnboardingView: View {
    @State private var showKeyboardInstructions = false
    @State private var accessStatus: KeyboardAccessStatus?
    @EnvironmentObject private var accountStore: AccountActivityStore
    @EnvironmentObject private var shortcutRegistry: ShortcutRegistryStore
    private let accessStatusStore = AppGroupKeyboardAccessStatusStore()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mobile AI Keyboard")
                            .font(.largeTitle.bold())
                        Text("入力を、あなたの確認のもとで整えるキーボード")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    privacyCard
                    keyboardSetupCard
                    NavigationLink {
                        LaunchReadinessView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("公開準備を確認")
                                    .font(.headline)
                                Text("Full Access無効・収集なし・ネットワーク未接続のfixture")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .accessibilityHidden(true)
                        } icon: {
                            Image(systemName: "checkmark.shield")
                                .foregroundStyle(.green)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityHint("プライバシー宣言と未証明の公開準備項目を確認します")
                    SandboxView()

                    NavigationLink {
                    AccountDashboardView()
                            .environmentObject(accountStore)
                            .environmentObject(shortcutRegistry)
                    } label: {
                        Label("アカウント・Activity・プライバシー", systemImage: "person.2")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .accessibilityHint("サインイン状態、デバイス、実行履歴、保持期間を確認します")

                    Button {
                        showKeyboardInstructions = true
                    } label: {
                        Label("キーボードを追加する", systemImage: "keyboard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
                    .accessibilityHint("設定アプリのキーボード設定を開くための案内を表示します")
                }
                .padding()
            }
            .navigationTitle("はじめに")
            .sheet(isPresented: $showKeyboardInstructions) {
                KeyboardInstructionsView()
            }
            .onAppear {
                accessStatus = accessStatusStore.load()
                accountStore.bindShortcutRegistry(shortcutRegistry)
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
    }

    private var keyboardSetupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("キーボードを有効にする", systemImage: "keyboard.badge.ellipsis")
                .font(.headline)
            Text("通常入力は端末内で動作します。Skill Keyの共有には、キーボードを追加したあとフルアクセスを許可してください。許可はいつでも設定から取り消せます。")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                setupStep("1", title: "キーボードを追加", detail: "設定 → 一般 → キーボード → キーボード → 新しいキーボードを追加")
                setupStep("2", title: "Mobile AI Keyboardを選択", detail: "キーボード一覧でMobile AI Keyboardをオンにする")
                setupStep("3", title: "フルアクセスを確認", detail: "App GroupでSkill Keyのメタデータを同期するために必要です")
            }
            accessStatusRow
            boundaryLegend
            HStack(spacing: 10) {
                Button("設定を開く") { openSettings() }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
                Button("状態を更新") { accessStatus = accessStatusStore.load() }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }

    private func setupStep(_ number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var accessStatusRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: accessStatus?.fullAccessEnabled == true ? "checkmark.circle.fill" : "questionmark.circle")
                .foregroundStyle(accessStatus?.fullAccessEnabled == true ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(accessStatus?.fullAccessEnabled == true ? "フルアクセス: 有効（最後に確認）" : "フルアクセス: 未確認")
                    .font(.subheadline.weight(.semibold))
                Text(accessStatus?.fullAccessEnabled == true
                     ? "App Groupのキー設定を共有できます。入力内容はこの状態レコードに保存しません。"
                     : "設定後にキーボードを一度表示すると状態を確認できます。未確認でも通常入力は利用できます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(accessStatus?.appGroupAvailable == true ? "App Group: 共有可能" : "App Group: 未確認（共有できない場合はHost内fallback）")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let checkedAt = accessStatus?.checkedAt {
                    Text("拡張機能からの最終確認: \(checkedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var boundaryLegend: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("データの境界")
                .font(.subheadline.weight(.semibold))
            Text("端末内: 通常入力とローカルworkflow。ネットワーク通信なし。")
            Text("App Group: キー・Skill version/digest・表示名だけをHostと拡張間で共有。")
            Text("ネットワーク: 現在のベータでは未接続。外部AI・CalendarのHost handoffは実行不可。")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("通常入力は端末内", systemImage: "lock.shield")
                .font(.headline)
            Text("AI機能を使うときだけ、送信する内容を確認できます。安全な入力欄ではAI機能を停止します。")
                .foregroundStyle(.secondary)
            Text("ネットワーク通信やアカウントは、テキストのローカル体験を試したあとに設定できます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("通常入力は端末内。AI機能を使うときだけ送信内容を確認できます。安全な入力欄ではAI機能を停止します。")
    }
}

private struct KeyboardInstructionsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("設定 → 一般 → キーボード → キーボード → 新しいキーボードを追加 → Mobile AI Keyboard")
                    .font(.body)
                Text("ベータ版では、Skill Keyの設定をHostとキーボード拡張間で共有するためフルアクセスを使います。現在のローカルworkflowはネットワーク通信を行わず、入力内容・prompt・token・資格情報を保存しません。外部AIやCalendar連携は、この画面から実行できません。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("設定アプリでMobile AI Keyboardを開き、フルアクセスをオンにしてください。不要になったらいつでもオフにできます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("設定を開く") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
                Spacer()
            }
            .padding()
            .navigationTitle("キーボードの追加")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
        }
    }
}
