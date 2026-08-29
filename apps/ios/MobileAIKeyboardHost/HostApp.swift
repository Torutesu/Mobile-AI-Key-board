import SwiftUI

@main
struct MobileAIKeyboardHostApp: App {
    @StateObject private var accountStore = AccountActivityStore()
    @StateObject private var shortcutRegistry = ShortcutRegistryStore()

    var body: some Scene {
        WindowGroup {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-skill-keys-qa") || ProcessInfo.processInfo.arguments.contains("-trigger-key-sheet-qa") {
                NavigationStack { SkillKeysView() }
                    .environmentObject(shortcutRegistry)
                    .environment(\.dynamicTypeSize, ProcessInfo.processInfo.arguments.contains("-accessibility-text-size-qa") ? .accessibility3 : .large)
                    .onAppear {
                        do {
                            try shortcutRegistry.activateOwner(subject: "fixture-user:UI Test")
                        } catch {
                            fatalError("Skill Keys QA authority setup failed: \(error.localizedDescription)")
                        }
                        if ProcessInfo.processInfo.arguments.contains("-ui-test-reset") {
                            shortcutRegistry.resetForUITest()
                        }
                    }
            } else if ProcessInfo.processInfo.arguments.contains("-skill-builder-qa") {
                NavigationStack { SkillBuilderView() }
                    .environmentObject(accountStore)
                    .environmentObject(shortcutRegistry)
                    .environment(\.dynamicTypeSize, ProcessInfo.processInfo.arguments.contains("-accessibility-text-size-qa") ? .accessibility3 : .large)
                    .onAppear {
                        accountStore.bindShortcutRegistry(shortcutRegistry)
                        accountStore.send(.signInFixture(label: "UI Test"))
                        if ProcessInfo.processInfo.arguments.contains("-ui-test-reset") {
                            shortcutRegistry.resetForUITest()
                        }
                    }
            } else if ProcessInfo.processInfo.arguments.contains("-app-shell-qa") {
                AppShellView()
                    .environmentObject(accountStore)
                    .environmentObject(shortcutRegistry)
            } else {
                OnboardingView()
                    .environmentObject(accountStore)
                    .environmentObject(shortcutRegistry)
            }
#else
            OnboardingView()
                .environmentObject(accountStore)
                .environmentObject(shortcutRegistry)
#endif
        }
    }
}
