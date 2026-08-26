import SwiftUI
import MobileAIKeyboardCore

/// W5's single, invite-free R3 write fixture. No OAuth, EventKit, URLSession,
/// provider API, attendee, or invite surface is present in this screen.
struct CalendarWriteView: View {
    @EnvironmentObject private var store: AccountActivityStore
    @State private var title = "設計レビュー"
    @State private var start = Date().addingTimeInterval(3600)
    @State private var end = Date().addingTimeInterval(7200)
    @State private var timezone = "Asia/Tokyo"
    private let calendarID = "fixture-private"

    private var draft: PrivateCalendarEventDraft {
        PrivateCalendarEventDraft(title: title, start: start, end: end, timezoneIdentifier: timezone, calendarIdentifier: calendarID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                boundaryCard
                capabilityCard
                draftCard
                stateCard
            }
            .padding()
        }
        .navigationTitle("Calendar write")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadDraftIfPresent() }
    }

    private var boundaryCard: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text("R3 / private Calendar write fixture").font(.headline)
                Text("OAuth・provider network・EventKitは未接続です。端末内fixtureだけが、招待なしのprivate予定を1件作成します。外部効果は明示確認後に限ります。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "calendar.badge.plus").foregroundStyle(.orange)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("R3 private Calendar write fixture。OAuthとprovider networkは未接続。招待なしのprivate予定を1件だけ作成し、外部効果は確認後に発生します。")
    }

    private var capabilityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("write capability", systemImage: "checkmark.shield")
                .font(.headline)
            if let capability = store.calendarWrite.capability {
                Text("接続済みfixture: \(capability.accountLabel) / epoch \(capability.connectionEpoch)")
                    .font(.body)
                Text("exact capability: create private event without attendees or invites")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("ConnectionsのCalendar read-only接続とは別の、明示的なwrite capabilityです。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("write capabilityを破棄") {
                    store.send(.disableCapability)
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
            } else {
                Text("現在はwrite capability未接続です。read-only Calendar接続やサインインを暗黙に昇格しません。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Button("fixture write capabilityを有効化") {
                    store.send(.enableFixtureCapability(accountLabel: "Fixture Calendar", connectionEpoch: nextCalendarEpoch))
                }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
                .disabled(!store.canEnableCalendarWriteFixture)
                .accessibilityHint("外部サービスへ接続せず、private write fixtureの能力だけを有効化します")
                if !store.canEnableCalendarWriteFixture {
                    Text("先にfixtureサインインとCalendar read-only接続を完了してください。write capabilityは別途この画面で確認します。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }

    private var nextCalendarEpoch: Int {
        store.connections.connections.first(where: { $0.provider == .calendar })?.connectionEpoch ?? 1
    }

    private var draftCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("予定の下書き", systemImage: "square.and.pencil").font(.headline)
                Spacer()
                Text("attendees: none").font(.caption).foregroundStyle(.secondary)
            }
            TextField("タイトル", text: $title)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("予定タイトル")
            DatePicker("開始", selection: $start, displayedComponents: [.date, .hourAndMinute])
                .frame(minHeight: 44)
            DatePicker("終了", selection: $end, displayedComponents: [.date, .hourAndMinute])
                .frame(minHeight: 44)
            TextField("タイムゾーン", text: $timezone)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("タイムゾーン")
            LabeledContent("Calendar source", value: "private fixture")
                .accessibilityLabel("Calendar source: private fixture")
            Text("参加者・招待・通知の入力欄はありません。タイトル、日時、タイムゾーン、保存先だけが確認対象です。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if !draft.isValid {
                Text("タイトル、タイムゾーン、保存先を入力し、終了時刻を開始時刻より後にしてください。")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if [.idle, .draft, .review, .confirmed].contains(status) {
                Button(status == .review || status == .confirmed ? "内容を編集して確認を無効化" : "レビューを作成") {
                    if status == .review || status == .confirmed {
                        store.send(.editDraft(draft))
                    } else {
                        store.send(.beginDraft(draft))
                        store.send(.review(now: Date()))
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
                .disabled(store.calendarWrite.capability == nil || !draft.isValid)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }

    private var status: CalendarWriteStatus { store.calendarWrite.status }

    @ViewBuilder private var stateCard: some View {
        switch status {
        case .unavailable:
            stateMessage("write capabilityを有効化すると、確認可能な下書きを作れます。", icon: "lock.shield")
        case .idle, .draft:
            stateMessage("まだ外部効果はありません。レビュー画面でデータ・サービス・外部効果を確認します。", icon: "arrow.right.circle")
        case .review:
            reviewCard
        case .confirmed:
            confirmedCard
        case .executing:
            executingCard
        case .succeeded, .failed, .partial, .unknown, .reconciling, .undone, .expired:
            receiptCard
        }
    }

    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Capture / plan review", systemImage: "checklist").font(.headline)
            Text("データ") .font(.subheadline.bold())
            Text("「\(draft.title)」 / \(draft.start.formatted(date: .abbreviated, time: .shortened))–\(draft.end.formatted(date: .omitted, time: .shortened)) / \(draft.timezoneIdentifier) / \(draft.calendarIdentifier)")
                .font(.body)
            Text("サービス") .font(.subheadline.bold())
            Text("Fixture Calendar（epoch \(store.calendarWrite.capability?.connectionEpoch ?? 0)）。OAuth/provider networkは未接続です。")
                .font(.body)
            Text("外部効果") .font(.subheadline.bold())
            Text("招待なし・private予定を1件だけ作成します。attendees/inviteは常にnone/falseで、確認なしには作成しません。")
                .font(.body)
            if let plan = store.calendarWrite.plan {
                digestView(plan)
                Button("この内容を明示確認") {
                    store.send(.confirm(digest: plan.confirmationDigest, now: Date()))
                }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }

    private func digestView(_ plan: CalendarWritePlan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("canonical SHA-256 confirmation digest").font(.subheadline.bold())
            Text(plan.confirmationDigest)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            Text("確認期限: \(plan.expiresAt.formatted(date: .abbreviated, time: .shortened))。内容を編集するとこのdigestは破棄されます。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("canonical SHA-256 confirmation digest。\(plan.confirmationDigest)。確認期限は\(plan.expiresAt.formatted(date: .abbreviated, time: .shortened))。編集すると破棄されます。")
    }

    private var confirmedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("1回分の確認が完了", systemImage: "checkmark.seal.fill").font(.headline)
            Text("このrunのdigestだけを実行できます。実行を開始すると、結果が確定するまで再編集できません。")
                .font(.body)
            if let plan = store.calendarWrite.plan { digestView(plan) }
            Button("このrunをfixtureで実行") {
                store.send(.beginExecution(now: Date()))
            }
            .buttonStyle(.borderedProminent)
            .frame(minHeight: 44)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }

    private var executingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("実行中（fixture）", systemImage: "hourglass").font(.headline)
            Text("外部ネットワークは使っていません。実際のprovider結果を装わず、下のfixture outcomeを選んでreceiptを生成します。")
                .font(.body)
                .foregroundStyle(.secondary)
            Button("成功: fixture eventを作成") {
                store.send(.settle(.succeeded(resource: CalendarWriteFixtureClient().successResource()), now: Date()))
            }
            .buttonStyle(.borderedProminent).frame(minHeight: 44)
            Button("失敗として記録") {
                store.send(.settle(.failed(reason: "fixture failure（provider network未接続）"), now: Date()))
            }
            .buttonStyle(.bordered).frame(minHeight: 44)
            Button("部分結果として記録") {
                store.send(.settle(.partial(reason: "fixture partial（provider network未接続）"), now: Date()))
            }
            .buttonStyle(.bordered).frame(minHeight: 44)
            Button("結果不明として停止") {
                store.send(.settle(.unknown(reason: "fixture timeout。reconciliationが必要です"), now: Date()))
            }
            .buttonStyle(.bordered).frame(minHeight: 44)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }

    private var receiptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(status.title, systemImage: receiptIcon).font(.headline)
            if let receipt = store.calendarWrite.receipt {
                Text(receipt.safeSummary).font(.body)
                Text("receipt: \(receipt.id) / plan \(receipt.planDigest)")
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                if let failure = receipt.failure {
                    Text("failure: \(failure)").font(.footnote).foregroundStyle(.orange)
                }
                if let resource = receipt.resource {
                    Text("provider: \(resource.provider.rawValue) / resource: \(resource.resourceIdentifier)")
                        .font(.footnote)
                    Text("source: \(resource.sourceReference)").font(.caption).foregroundStyle(.secondary)
                }
                Text("Activityにcontent-free receiptを追加しました。immutable plan: calendar.event.create_private.v1 / risk: R3")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if status == .unknown {
                Text("結果不明のため盲目的な再試行は禁止です。reconciliationだけが結果を確定できます。")
                    .font(.body).foregroundStyle(.orange)
                Button("fixture結果を照合（成功）") {
                    store.send(.reconcile(.succeeded(resource: CalendarWriteFixtureClient().successResource()), now: Date()))
                }
                .buttonStyle(.borderedProminent).frame(minHeight: 44)
                Button("照合して失敗として確定") {
                    store.send(.reconcile(.failed(reason: "fixture reconciliation failure"), now: Date()))
                }
                .buttonStyle(.bordered).frame(minHeight: 44)
            }
            if status == .succeeded, let ticket = store.calendarWrite.undoTicket, let resource = store.calendarWrite.receipt?.resource {
                Button("Undo（期限: \(ticket.expiresAt.formatted(date: .abbreviated, time: .shortened))）") {
                    store.send(.undo(resource: resource, now: Date()))
                }
                .buttonStyle(.borderedProminent).frame(minHeight: 44)
                .accessibilityHint("作成した同一fixture resourceだけを1回、期限内に取り消します")
            } else if status == .succeeded {
                Text("Undo期限切れ、または既に1回実行済みです。別resourceへのUndoは拒否されます。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }

    private var receiptIcon: String {
        switch status {
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "xmark.circle"
        case .partial: return "exclamationmark.circle"
        case .unknown, .reconciling: return "questionmark.circle"
        case .undone: return "arrow.uturn.backward.circle"
        default: return "doc.text"
        }
    }

    private func stateMessage(_ message: String, icon: String) -> some View {
        Label {
            Text(message).font(.footnote).foregroundStyle(.secondary)
        } icon: {
            Image(systemName: icon).foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private func loadDraftIfPresent() {
        guard let saved = store.calendarWrite.draft else { return }
        title = saved.title
        start = saved.start
        end = saved.end
        timezone = saved.timezoneIdentifier
    }
}
