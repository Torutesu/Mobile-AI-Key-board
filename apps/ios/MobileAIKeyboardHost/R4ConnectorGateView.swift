import SwiftUI
import MobileAIKeyboardCore

struct R4ConnectorGateView: View {
    @EnvironmentObject private var store: AccountActivityStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("R4: \(store.r4Gate.connector)", systemImage: "exclamationmark.octagon")
                    .font(.title3.weight(.semibold))
                Text("外部 communication / publish / send は別承認と外部証拠が必要です。このiOS fixtureではconnectorを有効化できません。")
                Text("status: \(store.r4Gate.decision)")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                Text("approval evidence: \(store.r4Gate.approvalEvidencePresent ? "present" : "absent") / enabled: \(store.r4Gate.enabled ? "true" : "false")")
                    .font(.footnote)
                Button("enableを試す（常に拒否）") { store.send(.attemptEnable) }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .accessibilityHint("別承認と証拠がないため有効化されません")
                Text("network、OAuth、secret、外部送信はありません。R4のphysical qualificationも未証明です。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("R4 connector gate")
        .navigationBarTitleDisplayMode(.inline)
    }
}
