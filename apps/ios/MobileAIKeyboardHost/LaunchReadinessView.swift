import SwiftUI
import MobileAIKeyboardCore

struct LaunchReadinessView: View {
    private let readiness = LaunchReadinessFixture()

    var body: some View {
        List {
            Section("プライバシー宣言") {
                readinessRow("Full Access", value: readiness.fullAccessEnabled ? "有効" : "無効（false）", good: !readiness.fullAccessEnabled)
                readinessRow("収集データ", value: readiness.collectedDataTypes.isEmpty ? "なし" : readiness.collectedDataTypes.joined(separator: "、"), good: readiness.collectedDataTypes.isEmpty)
                readinessRow("ネットワーク", value: readiness.networkConnected ? "接続" : "未接続", good: !readiness.networkConnected)
                readinessRow("PrivacyInfo source", value: readiness.privacyManifestSourceDeclared ? "宣言済み" : "未宣言", good: readiness.privacyManifestSourceDeclared)
                readinessRow("Archive / Store proof", value: readiness.privacyManifestArchivedVerified ? "verified" : "not_proven", good: false)
            }
            Section("サポート入口（fixture）") {
                Label("Support: \(readiness.supportEntry)", systemImage: "questionmark.circle")
                    .frame(minHeight: 44, alignment: .leading)
                Label("Incident: \(readiness.incidentEntry)", systemImage: "exclamationmark.bubble")
                    .frame(minHeight: 44, alignment: .leading)
                Text("実endpointへの接続はありません。これはsupport/incidentのローカル入口名を表示するfixtureです。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("未証明") {
                Text("PrivacyInfo archive検証、App Store申請、実端末のキーボード挙動、サポート運用、外部identity/backend接続はこのローカルfixtureでは証明していません。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Store readiness")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func readinessRow(_ title: String, value: String, good: Bool) -> some View {
        HStack {
            Label(title, systemImage: good ? "checkmark.shield" : "xmark.shield")
            Spacer()
            Text(value).foregroundStyle(good ? .green : .red)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}
