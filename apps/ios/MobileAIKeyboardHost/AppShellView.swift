import SwiftUI

/// Native iOS shell matching the reference product's three destinations and
/// persistent creation affordance while preserving system tab behavior.
struct AppShellView: View {
    private enum Tab: Hashable { case keyboard, skills, settings }
    @EnvironmentObject private var accountStore: AccountActivityStore
    @EnvironmentObject private var shortcutRegistry: ShortcutRegistryStore
    @State private var selectedTab: Tab = .keyboard
    @State private var showBuilder = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                SkillKeysView().environmentObject(shortcutRegistry).toolbar { createToolbarItem }
            }
            .tabItem { Label("キーボード", systemImage: "keyboard") }.tag(Tab.keyboard)

            NavigationStack {
                AccountDashboardView()
                    .environmentObject(accountStore).environmentObject(shortcutRegistry)
                    .navigationTitle("Skills").toolbar { createToolbarItem }
            }
            .tabItem { Label("Skills", systemImage: "wand.and.stars") }.tag(Tab.skills)

            NavigationStack {
                KeyboardSettingsView()
                    .environmentObject(accountStore).environmentObject(shortcutRegistry)
                    .toolbar { createToolbarItem }
            }
            .tabItem { Label("設定", systemImage: "person.crop.circle") }.tag(Tab.settings)
        }
        .tint(.primary)
        .sheet(isPresented: $showBuilder) {
            NavigationStack {
                SkillBuilderView().environmentObject(accountStore).environmentObject(shortcutRegistry)
            }
        }
        .onAppear {
            accountStore.bindShortcutRegistry(shortcutRegistry)
            if !accountStore.state.account.canUseAuthenticatedFeatures {
                accountStore.send(.signInFixture(label: "このiPhone"))
            }
        }
    }

    @ToolbarContentBuilder private var createToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { showBuilder = true } label: {
                Image(systemName: "plus").font(.headline.weight(.bold))
                    .frame(width: 38, height: 38).background(Color.primary, in: Circle())
                    .foregroundStyle(Color(.systemBackground))
            }
            .accessibilityLabel("新しいSkillを作る")
            .accessibilityIdentifier("open-skill-builder")
        }
    }
}
