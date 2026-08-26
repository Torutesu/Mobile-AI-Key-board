import SwiftUI
import MobileAIKeyboardCore

struct OnboardingView: View {
    @State private var showKeyboardInstructions = false

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
                    SandboxView()

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
        }
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
                Text("現在の端末内版はフルアクセス不要です。将来、外部AIを使う機能を追加する場合も、送信内容と必要な権限を実行前に表示します。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .navigationTitle("キーボードの追加")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
        }
    }
}
