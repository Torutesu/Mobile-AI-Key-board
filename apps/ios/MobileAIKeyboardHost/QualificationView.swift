import SwiftUI
import MobileAIKeyboardCore

struct QualificationView: View {
    @EnvironmentObject private var store: AccountActivityStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("端末内のcontent-free fixtureで予算判定します。実端末の性能・クラッシュ率はここでは証明しません。")
                    .font(.body)
                budgetCard
                if let measurement = store.qualification.measurement {
                    measurementCard(measurement)
                }
                Button("ローカルfixtureを実行") { store.send(.runFixture) }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
                    .disabled(!store.state.account.canUseAuthenticatedFeatures)
                if !store.state.account.canUseAuthenticatedFeatures {
                    Text("有効なサインインセッションが必要です。期限切れセッションからの再実行は停止します。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Label(store.qualification.physicalStatus.rawValue, systemImage: "exclamationmark.shield")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("実端末検証は未証明: not_proven")
            }
            .padding()
        }
        .navigationTitle("Launch qualification")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var budgetCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("予算").font(.headline)
            Text("cold P50 ≤ \(store.qualification.budget.coldStartP50Milliseconds)ms / cold P95 ≤ \(store.qualification.budget.coldStartP95Milliseconds)ms")
            Text("warm P95 ≤ \(store.qualification.budget.warmStartP95Milliseconds)ms / key P95 ≤ \(store.qualification.budget.keyLatencyP95Milliseconds)ms")
            Text("crash-free ≥ 99.80% beta / 99.95% broad")
        }
        .font(.footnote)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func measurementCard(_ measurement: QualificationMeasurement) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(store.qualification.fixturePassed ? "fixture予算内" : "fixture予算超過", systemImage: store.qualification.fixturePassed ? "checkmark.circle" : "xmark.circle")
                .foregroundStyle(store.qualification.fixturePassed ? .green : .red)
            Text("cold P50 \(measurement.coldStartP50Milliseconds)ms / P95 \(measurement.coldStartP95Milliseconds)ms")
            Text("warm P95 \(measurement.warmStartP95Milliseconds)ms / key P95 \(measurement.keyLatencyP95Milliseconds)ms")
            Text("sessions: \(measurement.sessions) / crashes: \(measurement.crashes) / crash-free: \(crashFreePercentage(measurement))")
            Text(measurement.contentFree ? "content-free: 収集なし" : "content-freeではありません")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private func crashFreePercentage(_ measurement: QualificationMeasurement) -> String {
        guard let basisPoints = measurement.crashFreeBasisPoints else { return "invalid" }
        return "\(basisPoints / 100).\(String(format: "%02d", basisPoints % 100))%"
    }
}
