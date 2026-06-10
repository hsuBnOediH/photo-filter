import SwiftUI

/// Menu-bar customizations: custom About window, update check, and a Help menu that
/// actually helps (cheat sheet + GitHub issues). Standard Edit/Window groups untouched.
struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(L("menu.about")) { openWindow(id: "about") }
            Button(L("menu.checkUpdates")) { UpdateChecker.checkInteractively() }
        }
        CommandGroup(replacing: .help) {
            Button(L("menu.cheatSheet")) { AppState.shared.showCheatSheet.toggle() }
                .keyboardShortcut("/", modifiers: [.command])
            Divider()
            Link(L("menu.github"), destination: URL(string: "https://github.com/\(UpdateChecker.repo)")!)
            Link(L("menu.reportIssue"), destination: URL(string: "https://github.com/\(UpdateChecker.repo)/issues")!)
        }
    }
}
