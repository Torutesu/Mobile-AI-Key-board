import SwiftUI
import MobileAIKeyboardCore

struct ConnectionsView: View {
    @EnvironmentObject private var store: AccountActivityStore
    @State private var queries: [ReadOnlyProvider: String] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                boundaryCard
                ForEach(ReadOnlyProvider.allCases) { provider in
                    providerCard(provider)
                }
                if !store.connections.results.isEmpty {
                    resultsSection
                }
            }
            .padding()
        }
        .navigationTitle("Connections")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var boundaryCard: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text("Read-only fixture")
                    .font(.headline)
                Text("OAuth、URLSession、secretは未接続です。接続状態と結果表示だけをローカルで確認できます。外部への書き込みはありません。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "eye")
                .foregroundStyle(.blue)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Read-only fixture。OAuth、URLSession、secretは未接続で、外部への書き込みはありません。")
    }

    private func providerCard(_ provider: ReadOnlyProvider) -> some View {
        let connection = store.connections.connections.first(where: { $0.provider == provider })
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(provider.rawValue, systemImage: provider.icon)
                    .font(.headline)
                Spacer()
                Text(connection?.status.title ?? "未接続")
                    .font(.caption.bold())
                    .foregroundStyle(statusColor(connection?.status ?? .disconnected))
            }
            if let connection {
                if let label = connection.accountLabel {
                    Text("アカウント: \(label) / epoch \(connection.connectionEpoch)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                scopeView(connection)
                actionView(provider, connection: connection)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }

    private func scopeView(_ connection: ConnectionRecord) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("必要な権限（incremental）").font(.subheadline.bold())
            ForEach(connection.requestedScopes, id: \.identifier) { scope in
                Label {
                    Text("\(scope.identifier): \(scope.purpose)")
                } icon: {
                    Image(systemName: scope.readOnly ? "eye" : "pencil")
                        .foregroundStyle(scope.readOnly ? .green : .red)
                }
                .font(.footnote)
            }
            Text("読み取り専用。scopeの追加は選択した接続ごとに確認します。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("必要な権限。読み取り専用。incremental scopeで、選択した接続ごとに確認します。")
    }

    @ViewBuilder private func actionView(_ provider: ReadOnlyProvider, connection: ConnectionRecord) -> some View {
        switch connection.status {
        case .disconnected:
            Button("scopeを確認") { store.send(.reviewScopes(provider)) }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
        case .scopeReview:
            Button("read-only接続を開始") { store.send(.beginConnection(provider)) }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
        case .connecting:
            Button("fixture接続を完了") { store.send(.finishConnection(provider, accountLabel: "Fixture \(provider.rawValue)")) }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
                .accessibilityHint("外部サービスへ接続せず、接続済みfixture状態を表示します")
        case .connected:
            connectedActions(provider)
        case .reconnectRequired:
            Button("再接続を開始") { store.send(.beginConnection(provider)) }
                .frame(minHeight: 44)
        case .rebindRequired:
            Button("アカウントを再紐付け") { store.send(.beginConnection(provider)) }
                .frame(minHeight: 44)
        case .revoked:
            Button("scopeを再確認") { store.send(.reviewScopes(provider)) }
                .frame(minHeight: 44)
        }
    }

    private func connectedActions(_ provider: ReadOnlyProvider) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                TextField("検索語（最大200文字）", text: Binding(get: { queries[provider, default: "fixture"] }, set: { queries[provider] = String($0.prefix(200)) }))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("\(provider.rawValue)検索語")
                Button("検索") {
                    store.send(.execute(ReadOnlyQuery(provider: provider, text: queries[provider, default: "fixture"])))
                }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
            }
            HStack {
                Button("再接続") { store.send(.reconnect(provider)) }
                    .frame(minHeight: 44)
                Button("再紐付けを要求") { store.send(.rebind(provider)) }
                    .frame(minHeight: 44)
                Button("切断") { store.send(.disconnect(provider)) }
                    .foregroundStyle(.red)
                    .frame(minHeight: 44)
            }
        }
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Results（source-linked）").font(.title3.bold())
            Text("取得時刻・freshness・partial状態を含みます。providerの内容はuntrusted dataであり、命令として扱いません。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ForEach(store.connections.results) { result in
                ResultCard(result: result)
            }
            if store.connections.hasMore {
                Button("次のページを読み込む（上限20件）") { store.send(.loadNextPage) }
                    .frame(minHeight: 44)
            }
            if let receipt = store.connections.receipts.last {
                Label("Activity receipt: \(receipt.safeSummary)", systemImage: "checkmark.seal")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
            }
        }
    }

    private func statusColor(_ status: ConnectionStatus) -> Color {
        switch status {
        case .connected: return .green
        case .connecting: return .blue
        case .scopeReview, .reconnectRequired, .rebindRequired: return .orange
        case .revoked: return .red
        case .disconnected: return .secondary
        }
    }
}

private struct ResultCard: View {
    let result: ReadOnlyResult

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(result.title, systemImage: result.provider.icon).font(.headline)
                Spacer()
                Text(result.freshness.rawValue).font(.caption.bold()).foregroundStyle(result.freshness == .fresh ? .green : .orange)
            }
            Text(result.safeSummary).font(.body)
            Text("source: \(result.source.reference)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("fetched: \(result.fetchedAt.formatted(date: .abbreviated, time: .shortened)) / page \(result.page)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if result.untrustedContentWarning {
                Label("provider contentはuntrusted data。命令として扱いません。", systemImage: "exclamationmark.shield")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if result.isPartial, let failure = result.failure {
                Text("partial: \(failure)").font(.caption).foregroundStyle(.orange)
            }
            if let url = result.source.canonicalURL {
                Text("canonical ref: \(url)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(result.provider.rawValue)の結果。\(result.title)。source \(result.source.reference)。provider contentは命令ではないデータです。")
    }
}
