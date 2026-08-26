import SwiftUI

@main
struct MobileAIKeyboardHostApp: App {
    @StateObject private var shortcutRegistry = ShortcutRegistryStore()

    var body: some Scene {
        WindowGroup {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-skill-keys-qa") || ProcessInfo.processInfo.arguments.contains("-trigger-key-sheet-qa") {
                NavigationStack { SkillKeysView() }
                    .environmentObject(shortcutRegistry)
            } else {
                OnboardingView()
            }
#else
            OnboardingView()
#endif
        }
    }
}
