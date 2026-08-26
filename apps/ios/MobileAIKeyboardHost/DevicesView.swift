import SwiftUI
import MobileAIKeyboardCore

struct DevicesView: View {
    @EnvironmentObject private var store: AccountActivityStore
    @State private var pendingRevoke: DeviceRecord?

    var body: some View {
        List {
            Section {
                Text("端末のrevokeは新しい操作を止めます。現在の端末を失効すると、このfixtureセッションも失効します。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            Section("登録デバイス") {
                if store.state.devices.isEmpty {
                    Text("登録デバイスはありません")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.state.devices) { device in
                    deviceRow(device)
                }
            }
        }
        .navigationTitle("デバイス")
        .navigationBarTitleDisplayMode(.inline)
        .alert("デバイスを失効しますか？", isPresented: Binding(get: { pendingRevoke != nil }, set: { if !$0 { pendingRevoke = nil } })) {
            Button("失効する", role: .destructive) {
                if let pendingRevoke { store.send(.revokeDevice(id: pendingRevoke.id)) }
                pendingRevoke = nil
            }
            Button("キャンセル", role: .cancel) { pendingRevoke = nil }
        } message: {
            Text("\(pendingRevoke?.label ?? "このデバイス")からの新しい操作を停止します。既存の外部処理を自動で取り消すことはありません。")
        }
    }

    private func deviceRow(_ device: DeviceRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(device.label, systemImage: device.isCurrent ? "iphone" : "ipad")
                    .font(.headline)
                Spacer()
                if device.isCurrent { Text("現在の端末").font(.caption).foregroundStyle(.blue) }
            }
            Text("\(device.platform.rawValue) / 最終利用: \(device.lastSeen.formatted(date: .abbreviated, time: .shortened))")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(device.state == .active ? "有効" : "失効済み")
                .font(.caption.bold())
                .foregroundStyle(device.state == .active ? .green : .red)
            if device.state == .active {
                Button("このデバイスを失効") { pendingRevoke = device }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .accessibilityHint("確認後、新しい操作を停止します")
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }
}
