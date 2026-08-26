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
                        if ProcessInfo.processInfo.arguments.contains("-ui-test-reset") {
                            shortcutRegistry.resetForUITest()
                        }
                    }
            } else if ProcessInfo.processInfo.arguments.contains("-skill-builder-qa") {
                NavigationStack { SkillBuilderView() }
                    .environmentObject(accountStore)
                    .environmentObject(shortcutRegistry)
                    .onAppear {
                        if ProcessInfo.processInfo.arguments.contains("-ui-test-reset") {
                            shortcutRegistry.resetForUITest()
                        }
                        accountStore.send(.signInFixture(label: "UI Test"))
                    }
            } else {
                OnboardingView()
            }
#else
            OnboardingView()
#endif
        }
    }
}
