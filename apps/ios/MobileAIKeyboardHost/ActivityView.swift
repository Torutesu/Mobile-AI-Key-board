import SwiftUI
import MobileAIKeyboardCore

struct ActivityView: View {
    @EnvironmentObject private var store: AccountActivityStore

    var body: some View {
        List {
            Section {
                Text("本文・prompt・selectionは表示しません。plan version、risk、状態、時刻、結果だけを表示するcontent-free監査情報です。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            Section("実行履歴") {
                if store.state.activities.isEmpty {
                    Text("Activityはありません")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.state.activities) { activity in
                    NavigationLink { ActivityDetailView(activity: activity) } label: {
                        ActivityRow(activity: activity)
                    }
                }
            }
        }
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ActivityRow: View {
    let activity: ActivityRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(activity.immutablePlanVersion).font(.headline)
                Spacer()
                StatusBadge(status: activity.status)
            }
            Text("risk \(activity.riskClass) / \(activity.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(activity.immutablePlanVersion)。risk \(activity.riskClass)。状態 \(activity.status.rawValue)。詳細を開く")
    }
}

struct ActivityDetailView: View {
    let activity: ActivityRecord

    var body: some View {
        List {
            Section("状態") {
                LabeledContent("status") { StatusBadge(status: activity.status) }
                LabeledContent("risk", value: activity.riskClass)
                LabeledContent("作成", value: activity.createdAt.formatted(date: .complete, time: .shortened))
                LabeledContent("更新", value: activity.updatedAt.formatted(date: .complete, time: .shortened))
            }
            Section("immutable plan") {
                LabeledContent("version", value: activity.immutablePlanVersion)
                VStack(alignment: .leading, spacing: 4) {
                    Text("digest").font(.caption).foregroundStyle(.secondary)
                    Text(activity.planDigest)
                        .font(.caption.monospaced())
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .textSelection(.enabled)
                }
            }
            Section("user-readable receipt") {
                Text(activity.safeReceipt)
                    .accessibilityLabel("結果。\(activity.safeReceipt)")
                if let safeFailure = activity.safeFailure {
                    Text("失敗・未完了: \(safeFailure)")
                        .foregroundStyle(.red)
                }
            }
            Section("steps（本文なし）") {
                ForEach(activity.steps) { step in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(step.operation).font(.headline)
                        Text("\(step.status.rawValue): \(step.safeSummary)").font(.footnote).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .navigationTitle("Activity詳細")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct StatusBadge: View {
    let status: ActivityStatus

    var body: some View {
        Text(status.rawValue)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
            .accessibilityLabel("状態 \(status.rawValue)")
    }

    private var color: Color {
        switch status {
        case .succeeded: return .green
        case .running: return .blue
        case .partial: return .orange
        case .failed, .unknown: return .red
        }
    }
}
