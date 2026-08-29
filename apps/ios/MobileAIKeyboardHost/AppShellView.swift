import SwiftUI
import UIKit

/// Consumer-facing iOS shell. The creation action remains reachable from every
/// destination and the custom safe-area bar mirrors the reference product's
/// keyboard / discovery / profile hierarchy.
struct AppShellView: View {
    private enum Tab: Hashable { case keyboard, skills, profile }
    @EnvironmentObject private var accountStore: AccountActivityStore
    @EnvironmentObject private var shortcutRegistry: ShortcutRegistryStore
    @State private var selectedTab: Tab = .keyboard
    @State private var showCreateFlow = false

    private let background = Color(red: 0.94, green: 0.96, blue: 0.98)

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { SkillKeysView().environmentObject(shortcutRegistry) }
                .tag(Tab.keyboard)
            NavigationStack { SkillsCatalogView().environmentObject(shortcutRegistry) }
                .tag(Tab.skills)
            NavigationStack {
                ProfileHomeView()
                    .environmentObject(accountStore)
                    .environmentObject(shortcutRegistry)
            }
            .tag(Tab.profile)
        }
        .toolbar(.hidden, for: .tabBar)
        .background(background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .sheet(isPresented: $showCreateFlow) {
            CreateSkillFlowView()
                .environmentObject(accountStore)
                .environmentObject(shortcutRegistry)
        }
        .onAppear {
            accountStore.bindShortcutRegistry(shortcutRegistry)
            if !accountStore.state.account.canUseAuthenticatedFeatures {
                accountStore.send(.signInFixture(label: "このiPhone"))
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                tabButton(.keyboard, title: "キーボード", icon: "keyboard")
                tabButton(.skills, title: "Skills", icon: "wand.and.stars")
                tabButton(.profile, title: "プロフィール", icon: "person")
            }
            .padding(5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.78), lineWidth: 1))

            Button { showCreateFlow = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .medium))
                    .frame(width: 58, height: 58)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.82), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .accessibilityLabel("新しいSkillを作る")
            .accessibilityIdentifier("open-skill-builder")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(background.opacity(0.92))
    }

    private func tabButton(_ tab: Tab, title: String, icon: String) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { selectedTab = tab }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                Text(title).font(.caption2.weight(.semibold)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(selectedTab == tab ? Color.primary.opacity(0.08) : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selectedTab == tab ? Color.primary : Color.secondary)
        .accessibilityValue(selectedTab == tab ? "選択中" : "")
        .accessibilityIdentifier("app-tab-\(title)")
    }
}

struct CreateSkillFlowView: View {
    private enum Stage { case choose, privateBuilder }
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountStore: AccountActivityStore
    @EnvironmentObject private var shortcutRegistry: ShortcutRegistryStore
    @State private var stage: Stage = .choose

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .choose:
                    SkillTypeChooserView(
                        onClose: { dismiss() },
                        onChoosePrivate: {
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { stage = .privateBuilder }
                        }
                    )
                case .privateBuilder:
                    SkillBuilderView()
                        .environmentObject(accountStore)
                        .environmentObject(shortcutRegistry)
                }
            }
        }
        .presentationDragIndicator(.hidden)
    }
}

private struct SkillTypeChooserView: View {
    let onClose: () -> Void
    let onChoosePrivate: () -> Void
    @State private var dragOffset: CGFloat = 0
    private let background = Color(red: 0.94, green: 0.96, blue: 0.98)

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.title2.weight(.medium))
                            .frame(width: 52, height: 52).background(.white.opacity(0.9), in: Circle())
                    }
                    .buttonStyle(.plain).foregroundStyle(.primary).accessibilityLabel("閉じる")
                    Spacer()
                    Text("Skillの種類").font(.headline)
                    Spacer()
                    Color.clear.frame(width: 52, height: 52)
                }
                .padding(.horizontal, 20).padding(.top, 10)

                VStack(spacing: 5) {
                    Text("Public").font(.largeTitle.weight(.bold))
                    Text("公開・共有Skillは準備中").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                }
                .opacity(0.38).padding(.top, 44)

                Spacer(minLength: 26)
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.white.opacity(0.96), .cyan.opacity(0.22), .purple.opacity(0.22)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 214, height: 214)
                        .shadow(color: .cyan.opacity(0.2), radius: 34)
                    Circle().stroke(.white.opacity(0.9), lineWidth: 2).frame(width: 214, height: 214)
                    VStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill").font(.title2)
                        Text("下へドラッグ").font(.headline)
                        Text("Privateを選ぶ").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                .offset(y: max(0, dragOffset))
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { dragOffset = min(max(0, $0.translation.height), 92) }
                        .onEnded { value in
                            if value.translation.height > 64 { onChoosePrivate() }
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) { dragOffset = 0 }
                        }
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Private Skillを選ぶ")
                .accessibilityHint("ダブルタップして、端末内だけのSkill作成へ進みます")
                .accessibilityAddTraits(.isButton)
                .onTapGesture(perform: onChoosePrivate)

                Spacer(minLength: 30)
                VStack(spacing: 7) {
                    Text("Private").font(.largeTitle.weight(.bold))
                    Text("このiPhoneとキーボードだけで使う").font(.body.weight(.medium))
                    Text("公開されません。まず端末内で試してからキーに追加します。")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                Button("Private Skillを作る", action: onChoosePrivate)
                    .font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(.black, in: Capsule())
                    .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 28)
                    .accessibilityIdentifier("choose-private-skill")
            }
        }
        .preferredColorScheme(.light)
    }
}

private struct SkillsCatalogView: View {
    private enum Filter: String, CaseIterable { case featured = "おすすめ", latest = "新着" }
    @EnvironmentObject private var registry: ShortcutRegistryStore
    @State private var filter: Filter = .featured
    @State private var query = ""

    private var results: [ShortcutSkillOption] {
        let available = registry.skills.filter(\.isAssignable)
        let filtered = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? available : available.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.description.localizedCaseInsensitiveContains(query)
        }
        return filter == .latest ? Array(filtered.reversed()) : filtered
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                Picker("並び順", selection: $filter) {
                    ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).padding(.bottom, 8)

                if results.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
                        Text("Skillが見つかりません").font(.headline)
                        Text("別の言葉で検索してください。").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 70)
                } else {
                    ForEach(results) { skill in skillCard(skill) }
                }
            }
            .padding(20).padding(.bottom, 20)
        }
        .background(Color(red: 0.94, green: 0.96, blue: 0.98).ignoresSafeArea())
        .navigationTitle("Skills")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Skillを検索")
        .preferredColorScheme(.light)
    }

    private func skillCard(_ skill: ShortcutSkillOption) -> some View {
        NavigationLink {
            SkillKeysView().environmentObject(registry)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Image(systemName: skill.icon).font(.title2).foregroundStyle(.cyan)
                        .frame(width: 56, height: 56).background(Color.cyan.opacity(0.11), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(skill.name).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                        Text(skill.description).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                Divider()
                Label("このiPhoneで利用可能", systemImage: "lock.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding(18).background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
    }
}

private struct ProfileHomeView: View {
    @EnvironmentObject private var accountStore: AccountActivityStore
    @EnvironmentObject private var shortcutRegistry: ShortcutRegistryStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill").font(.system(size: 78)).foregroundStyle(.black)
                    Text("このiPhone").font(.title.bold())
                    Text("Private Skills · \(shortcutRegistry.skills.filter(\.isAssignable).count)件")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 18)

                profileLink("My Skills", subtitle: "作成済みSkillとキー割り当て", icon: "wand.and.stars") {
                    SkillKeysView().environmentObject(shortcutRegistry)
                }
                profileLink("キーボード設定", subtitle: "入力、見た目、アクセス許可", icon: "keyboard") {
                    KeyboardSettingsView().environmentObject(accountStore).environmentObject(shortcutRegistry)
                }
                profileLink("アカウントと安全性", subtitle: "端末・接続・プライバシーの詳細", icon: "person.crop.circle") {
                    AccountDashboardView().environmentObject(accountStore).environmentObject(shortcutRegistry)
                }
            }
            .padding(20).padding(.bottom, 20)
        }
        .background(Color(red: 0.94, green: 0.96, blue: 0.98).ignoresSafeArea())
        .navigationTitle("プロフィール")
        .preferredColorScheme(.light)
    }

    private func profileLink<Destination: View>(_ title: String, subtitle: String, icon: String, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title3).frame(width: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain).foregroundStyle(.primary)
        .accessibilityIdentifier("profile-link-\(title)")
    }
}
