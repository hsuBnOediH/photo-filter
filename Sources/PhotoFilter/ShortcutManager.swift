import AppKit
import SwiftUI

extension Notification.Name {
    /// Posted by any module's "?" binding (and the Help menu); RootView shows the
    /// cheat-sheet overlay.
    static let showCheatSheet = Notification.Name("PhotoFilter.showCheatSheet")
}

/// Every rebindable action in the app. Esc is deliberately NOT here — it's reserved
/// navigation (back out of overlays / back home) and must always work; same for the
/// review grid's Return (a SwiftUI .keyboardShortcut) and ⌘Z (hardcoded undo alias).
enum ShortcutAction: String, CaseIterable, Codable, Identifiable {
    // Screenshot module
    case markDelete, keep, undo
    // Organize module
    case prevGroup, nextGroup, prevPhoto, nextPhoto
    case toggleMark, keepOnly, finishGroup, compare, pixelZoom
    // Shared across modules
    case zoom, showCheatSheet

    var id: String { rawValue }
    var title: String { L("shortcut.action.\(rawValue)") }

    /// Actions live per module so e.g. ↑ can mean undo in the screenshot module and
    /// previous-group in organize without conflicting.
    static let cullScope: [ShortcutAction] = [.markDelete, .keep, .undo, .zoom, .showCheatSheet]
    static let organizeScope: [ShortcutAction] = [
        .prevGroup, .nextGroup, .prevPhoto, .nextPhoto,
        .toggleMark, .keepOnly, .finishGroup, .compare, .pixelZoom, .zoom, .showCheatSheet,
    ]
}

/// One recorded key binding. `display` is captured at record time so the UI never has
/// to reverse-map keyCodes.
struct KeyCombo: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt   // NSEvent.ModifierFlags filtered to ⌘⌥⌃⇧
    var display: String

    static func normalize(_ code: UInt16) -> UInt16 { code == 76 ? 36 : code }  // keypad-Enter → Enter

    func matches(_ event: NSEvent) -> Bool {
        Self.normalize(event.keyCode) == Self.normalize(keyCode)
            && event.modifierFlags
                .intersection([.command, .option, .control, .shift])
                .rawValue == modifiers
    }

    /// Human-readable form of an event, for the recorder.
    static func describe(_ event: NSEvent) -> String {
        var parts: [String] = []
        if event.modifierFlags.contains(.control) { parts.append("⌃") }
        if event.modifierFlags.contains(.option) { parts.append("⌥") }
        if event.modifierFlags.contains(.shift) { parts.append("⇧") }
        if event.modifierFlags.contains(.command) { parts.append("⌘") }
        let glyphs: [UInt16: String] = [
            123: "←", 124: "→", 125: "↓", 126: "↑", 49: "Space",
            51: "⌫", 117: "⌦", 36: "⏎", 76: "⏎", 48: "⇥",
        ]
        if let glyph = glyphs[event.keyCode] {
            parts.append(glyph)
        } else {
            parts.append((event.charactersIgnoringModifiers ?? "?").uppercased())
        }
        return parts.joined()
    }
}

/// Default bindings + user overrides (UserDefaults, JSON). Views dispatch through
/// `action(for:among:)`; the Settings pane records new combos per action.
@MainActor
final class ShortcutManager: ObservableObject {
    static let shared = ShortcutManager()
    private static let defaultsKey = "shortcuts.v1"

    @Published private(set) var bindings: [ShortcutAction: KeyCombo]

    static let defaultBindings: [ShortcutAction: KeyCombo] = [
        .markDelete: KeyCombo(keyCode: 123, modifiers: 0, display: "←"),
        .keep: KeyCombo(keyCode: 124, modifiers: 0, display: "→"),
        .undo: KeyCombo(keyCode: 126, modifiers: 0, display: "↑"),
        .prevGroup: KeyCombo(keyCode: 126, modifiers: 0, display: "↑"),
        .nextGroup: KeyCombo(keyCode: 125, modifiers: 0, display: "↓"),
        .prevPhoto: KeyCombo(keyCode: 123, modifiers: 0, display: "←"),
        .nextPhoto: KeyCombo(keyCode: 124, modifiers: 0, display: "→"),
        .toggleMark: KeyCombo(keyCode: 51, modifiers: 0, display: "⌫"),
        .keepOnly: KeyCombo(keyCode: 40, modifiers: 0, display: "K"),
        .finishGroup: KeyCombo(keyCode: 36, modifiers: 0, display: "⏎"),
        .compare: KeyCombo(keyCode: 8, modifiers: 0, display: "C"),
        .pixelZoom: KeyCombo(keyCode: 6, modifiers: 0, display: "Z"),
        .zoom: KeyCombo(keyCode: 49, modifiers: 0, display: "Space"),
        .showCheatSheet: KeyCombo(keyCode: 44, modifiers: UInt(NSEvent.ModifierFlags.shift.rawValue), display: "?"),
    ]

    private init() {
        var merged = Self.defaultBindings
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode([ShortcutAction: KeyCombo].self, from: data) {
            merged.merge(saved) { _, override in override }
        }
        bindings = merged
    }

    func combo(for action: ShortcutAction) -> KeyCombo {
        bindings[action] ?? Self.defaultBindings[action]!
    }

    /// Scoped dispatch: first action in `scope` whose combo matches the event.
    func action(for event: NSEvent, among scope: [ShortcutAction]) -> ShortcutAction? {
        scope.first { combo(for: $0).matches(event) }
    }

    /// Another action in any overlapping scope already using this combo, if any.
    func conflict(for combo: KeyCombo, excluding action: ShortcutAction) -> ShortcutAction? {
        let scopes = [ShortcutAction.cullScope, ShortcutAction.organizeScope]
            .filter { $0.contains(action) }
        return scopes.joined().first {
            $0 != action && self.combo(for: $0).keyCode == combo.keyCode
                && self.combo(for: $0).modifiers == combo.modifiers
                && KeyCombo.normalize(self.combo(for: $0).keyCode) == KeyCombo.normalize(combo.keyCode)
        }
    }

    func set(_ combo: KeyCombo, for action: ShortcutAction) {
        bindings[action] = combo
        persist()
    }

    func resetToDefaults() {
        bindings = Self.defaultBindings
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
    }

    private func persist() {
        // Only store entries that differ from the defaults, so future default
        // changes reach users who never customized that action.
        let overrides = bindings.filter { $0.value != Self.defaultBindings[$0.key] }
        if let data = try? JSONEncoder().encode(overrides) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
