import SwiftUI
import MobileAIKeyboardCore

struct AccountDashboardView: View {
    @EnvironmentObject private var store: AccountActivityStore
    @EnvironmentObject private var shortcutRegistry: ShortcutRegistryStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                providerBoundaryCard
                accountCard
                navigationCard(title: "デバイス", subtitle: "現在の端末、最終利用、失効", systemImage: "iphone.gen3") { DevicesView() }
                navigationCard(title: "Connections", subtitle: "Calendar・Notion・Mapsのread-only接続", systemImage: "link") { ConnectionsView() }
                navigationCard(title: "Calendar write", subtitle: "R3・招待なしprivate event（fixture）", systemImage: "calendar.badge.plus") { CalendarWriteView() }
                navigationCard(title: "Private Skill Builder", subtitle: "コードなし・private v1・fixture deploy", systemImage: "wand.and.stars") { SkillBuilderView() }
                navigationCard(title: "キーボード設定", subtitle: "テーマ・キーサイズ・片手モード・workflow packs", systemImage: "keyboard") { KeyboardSettingsView() }
                navigationCard(title: "Skill Keys", subtitle: "QWERTYキーへの割り当て・再割り当て・削除", systemImage: "keyboard.badge.ellipsis") { SkillKeysView().environmentObject(shortcutRegistry) }
                navigationCard(title: "Contextual suggestions", subtitle: "端末内候補・raw textなし・自動適用なし", systemImage: "sparkles") { ContextualSuggestionsView() }
                navigationCard(title: "Trust Preview / Skill catalog", subtitle: "SK-006 metadata・provenance・not_proven表示", systemImage: "checkmark.seal") { TrustCatalogView() }
                navigationCard(title: "Team policy", subtitle: "owner/version/digest・explicit upgrade・revoke", systemImage: "person.3") { TeamPolicyView() }
                navigationCard(title: "R4 connector gate", subtitle: "別承認・証拠がないためdisabled", systemImage: "exclamationmark.octagon") { R4ConnectorGateView() }
                navigationCard(title: "Launch qualification", subtitle: "content-free予算と実端末not_proven表示", systemImage: "speedometer") { QualificationView() }
                navigationCard(title: "Store readiness", subtitle: "PrivacyInfo・Full Access・support入口", systemImage: "checkmark.shield") { LaunchReadinessView() }
                navigationCard(title: "Activity", subtitle: "実行履歴とcontent-free監査情報", systemImage: "clock.arrow.circlepath") { ActivityView() }
                navigationCard(title: "プライバシー", subtitle: "保持期間と削除リクエスト", systemImage: "hand.raised.shield") { PrivacyView() }
            }
            .padding()
        }
        .navigationTitle("アカウント")
    }

    private var providerBoundaryCard: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text("ローカルfixture")
                    .font(.headline)
                Text("表示と状態遷移を確認するためのデータです。外部identity/backend接続は未証明です。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "shippingbox")
                .foregroundStyle(.orange)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("ローカルfixture。外部identityとbackend接続は未証明です。")
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(store.state.account.title, systemImage: accountIcon)
                .font(.headline)
            Text(accountExplanation)
                .font(.body)
                .foregroundStyle(.secondary)
            if !store.state.account.canUseAuthenticatedFeatures {
                Button("fixtureでサインイン状態を表示") {
                    store.send(.signInFixture(label: "Fixture User"))
                }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
                .accessibilityHint("外部サービスへ接続せず、ローカルのサインイン状態だけを表示します")
            } else {
                Button("セッション期限切れを表示") {
                    store.send(.expireSession)
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }

    private var accountIcon: String {
        switch store.state.account {
        case .signedIn: return "person.crop.circle.badge.checkmark"
        case .revoked: return "person.crop.circle.badge.xmark"
        default: return "person.crop.circle"
        }
    }

    private var accountExplanation: String {
        switch store.state.account {
        case .anonymous: return "匿名・端末内の体験はサインインなしで利用できます。同期やActivityのサーバー機能にはサインインが必要です。"
        case .signInRequired: return "この機能にはアカウントが必要です。現在はfixture表示のみで、identity providerには接続していません。"
        case .signedIn: return "この表示はローカルfixtureです。実際のセッション発行・更新・revokeは未証明です。"
        case .sessionExpired: return "再認証が必要です。保存済みの操作を自動実行することはありません。"
        case .revoked: return "この端末からの新しい操作は停止されています。再接続には明示的な認証が必要です。"
        }
    }

    private func navigationCard<Destination: View>(title: String, subtitle: String, systemImage: String, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink { destination().environmentObject(store) } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage).frame(width: 28).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary).accessibilityHidden(true)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityHint("詳細を開く")
    }
}
