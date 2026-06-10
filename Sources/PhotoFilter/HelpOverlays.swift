import SwiftUI

/// App-wide UI state shared between the menu bar, the module key handlers, and
/// RootView (which hosts the overlays).
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    @Published var showCheatSheet = false
}

/// "?" overlay listing the LIVE shortcut bindings, grouped by module. Esc or "?" or a
/// click anywhere dismisses (handled by the hosting RootView).
struct CheatSheetView: View {
    @ObservedObject private var shortcuts = ShortcutManager.shared
    var onDismiss: () -> Void

    private func rows(_ scope: [ShortcutAction]) -> some View {
        ForEach(scope) { action in
            HStack {
                Text(shortcuts.combo(for: action).display)
                    .font(.body.monospaced().bold())
                    .frame(width: 70, alignment: .trailing)
                    .foregroundStyle(.white)
                Text(action.title)
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
            }
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 10) {
                Text(L("cheatsheet.title"))
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                HStack(alignment: .top, spacing: 40) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("home.card.screenshots.title")).font(.headline).foregroundStyle(.gray)
                        rows(ShortcutAction.cullScope.filter { $0 != .showCheatSheet })
                        HStack {
                            Text("⌘Z").font(.body.monospaced().bold())
                                .frame(width: 70, alignment: .trailing).foregroundStyle(.white)
                            Text(L("shortcut.action.undo")).foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("home.card.personal.title")).font(.headline).foregroundStyle(.gray)
                        rows(ShortcutAction.organizeScope.filter { $0 != .showCheatSheet && $0 != .zoom })
                    }
                }
                Text(L("cheatsheet.footer"))
                    .font(.footnote)
                    .foregroundStyle(.gray)
                    .padding(.top, 6)
            }
            .padding(32)
            .background(.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
    }
}

/// One-time first-launch sheet: the three things a new user must know.
struct OnboardingView: View {
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("onboarding.title"))
                .font(.title.bold())
            bullet("square.grid.2x2", L("onboarding.modules"))
            bullet("keyboard", L("onboarding.keyboard"))
            bullet("arrow.uturn.backward.circle", L("onboarding.safety"))
            HStack {
                Spacer()
                Button(L("onboarding.start")) { onDismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(32)
        .frame(width: 520)
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 32)
                .foregroundStyle(.blue)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
