import SwiftUI
import MobileAIKeyboardCore

struct PrivacyView: View {
    @EnvironmentObject private var store: AccountActivityStore
    @State private var showDeleteConfirmation = false

    var body: some View {
        List {
            Section("保持期間") {
                Picker("保持期間", selection: Binding(get: { store.state.retention }, set: { store.send(.setRetention($0)) })) {
                    ForEach(RetentionPolicy.allCases, id: \.self) { policy in
                        Text(policy.rawValue).tag(policy)
                    }
                }
                .pickerStyle(.menu)
                Text("処理中のcontentは既定で24時間以内、レシートは90日以内です。選択はfixture stateに保存されます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("削除") {
                Text(deletionDescription)
                    .font(.body)
                if case .idle = store.state.deletion {
                    Button("削除をリクエスト") { showDeleteConfirmation = true }
                        .buttonStyle(.borderedProminent)
                        .frame(minHeight: 44)
                } else {
                    deletionProgress
                }
            }
            Section("境界") {
                Text("この画面はcontent-freeのローカルfixtureです。identity providerのrevoke、backendの削除、バックアップ消去は未証明です。完了表示は実運用の削除証明ではありません。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("公開準備") {
                NavigationLink {
                    LaunchReadinessView()
                } label: {
                    Label("Store readinessを確認", systemImage: "checkmark.shield")
                }
                .frame(minHeight: 44)
            }
        }
        .navigationTitle("プライバシー")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("データ削除をリクエストしますか？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("削除をリクエスト", role: .destructive) { store.send(.requestDeletion) }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("アクティブシステムからの削除依頼を作成します。外部backendには接続しません。")
        }
    }

    @ViewBuilder private var deletionProgress: some View {
        switch store.state.deletion {
        case .idle: EmptyView()
        case .requested:
            Label("削除リクエスト済み", systemImage: "clock")
            Button("進捗を確認（fixture）") { store.send(.advanceDeletion) }
                .frame(minHeight: 44)
        case .inProgress(let progress):
            ProgressView(value: Double(progress), total: 100) { Text("削除進捗 \(progress)%") }
            Button("進捗を更新（fixture）") { store.send(progress >= 90 ? .completeDeletion : .advanceDeletion) }
                .frame(minHeight: 44)
        case .completed:
            Label("削除結果: 完了（fixture）", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case .failed(let reason):
            Label("削除結果: 失敗。\(reason)", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }

    private var deletionDescription: String {
        switch store.state.deletion {
        case .idle: return "アカウント削除ではなく、ローカルfixtureのActivityとデバイス表示を削除する流れを確認できます。"
        case .requested, .inProgress: return "削除依頼を受付けました。完了までは状態を確認できます。"
        case .completed: return "このfixtureのActivityとデバイス表示は削除されました。"
        case .failed: return "削除を完了できませんでした。安全な次の操作を確認してください。"
        }
    }
}
