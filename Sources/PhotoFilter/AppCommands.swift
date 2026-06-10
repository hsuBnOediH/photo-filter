import SwiftUI

/// Menu-bar customizations: custom About window, update check, and a Help menu that
/// actually helps (cheat sheet + GitHub issues). Standard Edit/Window groups untouched.
/// Button actions hop to the main actor explicitly — `Commands` bodies are not
/// main-actor-isolated on older SDKs.
struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(L("menu.about")) { openWindow(id: "about") }
            Button(L("menu.checkUpdates")) {
                Task { @MainActor in UpdateChecker.checkInteractively() }
            }
        }
        CommandGroup(replacing: .help) {
            Button(L("menu.cheatSheet")) {
                Task { @MainActor in AppState.shared.showCheatSheet.toggle() }
            }
            .keyboardShortcut("/", modifiers: [.command])
            Divider()
            Link(L("menu.github"), destination: AppInfo.repoURL)
            Link(L("menu.reportIssue"), destination: AppInfo.issuesURL)
        }
    }
}
