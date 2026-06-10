import SwiftUI
import AppKit

/// The ⌘, settings window: General / Shortcuts / Cache.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label(L("settings.general"), systemImage: "gearshape") }
            ShortcutSettings()
                .tabItem { Label(L("settings.shortcuts"), systemImage: "keyboard") }
            CacheSettings()
                .tabItem { Label(L("settings.cache"), systemImage: "internaldrive") }
        }
        .frame(width: 520)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @AppStorage("update.autoCheck") private var autoCheck = true
    @AppStorage("organize.timeWindow") private var timeWindowRaw = TimeWindow.fiveMinutes.rawValue
    @AppStorage("organize.similarity") private var similarityRaw = SimilarityLevel.standard.rawValue

    var body: some View {
        Form {
            Section {
                Picker(L("organize.setting.timeWindow"), selection: $timeWindowRaw) {
                    ForEach(TimeWindow.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Picker(L("organize.setting.similarity"), selection: $similarityRaw) {
                    ForEach(SimilarityLevel.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Text(L("settings.general.scanNote"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle(L("settings.general.autoUpdate"), isOn: $autoCheck)
            }
            Section {
                Text(L("settings.general.languageNote"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(L("settings.general.openLanguageSettings")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}

// MARK: - Shortcuts

private struct ShortcutSettings: View {
    @ObservedObject private var shortcuts = ShortcutManager.shared
    /// The action currently being recorded, if any.
    @State private var recording: ShortcutAction?
    @State private var conflictMessage: String?
    @State private var monitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(L("settings.shortcuts.cull")) {
                    ForEach(ShortcutAction.cullScope) { action in row(action) }
                }
                Section(L("settings.shortcuts.organize")) {
                    ForEach(ShortcutAction.organizeScope.filter { !ShortcutAction.cullScope.contains($0) }) { action in
                        row(action)
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                if let conflictMessage {
                    Text(conflictMessage).font(.footnote).foregroundStyle(.red)
                } else {
                    Text(L("settings.shortcuts.hint")).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L("settings.shortcuts.reset")) {
                    stopRecording()
                    shortcuts.resetToDefaults()
                }
            }
            .padding()
        }
        .onDisappear { stopRecording() }
    }

    private func row(_ action: ShortcutAction) -> some View {
        HStack {
            Text(action.title)
            Spacer()
            Button(recording == action ? L("settings.shortcuts.recording") : shortcuts.combo(for: action).display) {
                recording == action ? stopRecording() : startRecording(action)
            }
            .frame(minWidth: 110)
        }
    }

    /// Swallows the next keyDown and records it for `action`. Esc cancels (it's
    /// reserved for navigation and may not be bound).
    private func startRecording(_ action: ShortcutAction) {
        stopRecording()
        recording = action
        conflictMessage = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            defer { stopRecording() }
            guard event.keyCode != 53 else { return nil }  // Esc cancels
            let combo = KeyCombo(
                keyCode: event.keyCode,
                modifiers: event.modifierFlags.intersection([.command, .option, .control, .shift]).rawValue,
                display: KeyCombo.describe(event)
            )
            if let conflict = shortcuts.conflict(for: combo, excluding: action) {
                conflictMessage = L("settings.shortcuts.conflict", combo.display, conflict.title)
            } else {
                shortcuts.set(combo, for: action)
            }
            return nil  // consumed
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
    }
}

// MARK: - Cache

private struct CacheSettings: View {
    @State private var cacheInfo: (count: Int, bytes: Int64) = (0, 0)
    @State private var hasSession = false

    private var cacheDir: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("PhotoFilter", isDirectory: true)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent(L("settings.cache.featurePrints")) {
                    Text(L("settings.cache.size", cacheInfo.count,
                           ByteCountFormatter.string(fromByteCount: cacheInfo.bytes, countStyle: .file)))
                }
                Text(L("settings.cache.note"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(L("settings.cache.clear")) {
                    try? FileManager.default.removeItem(at: cacheDir.appendingPathComponent("FeaturePrints"))
                    refresh()
                }
                .disabled(cacheInfo.count == 0)
            }
            Section {
                Button(L("settings.cache.clearSession")) {
                    ScanSessionStore.clear()
                    refresh()
                }
                .disabled(!hasSession)
                Text(L("settings.cache.sessionNote"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .onAppear { refresh() }
    }

    private func refresh() {
        hasSession = ScanSessionStore.load() != nil
        let prints = cacheDir.appendingPathComponent("FeaturePrints")
        var count = 0
        var bytes: Int64 = 0
        if let walker = FileManager.default.enumerator(at: prints, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let url as URL in walker {
                guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { continue }
                count += 1
                bytes += Int64(size)
            }
        }
        cacheInfo = (count, bytes)
    }
}
