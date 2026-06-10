import SwiftUI
import AppKit

@main
struct PhotoFilterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Window (not WindowGroup): a second window would spawn a second set of view
        // models and fight the first over keyboard focus and marks.
        Window("PhotoFilter", id: "main") {
            RootView()
        }
        .defaultSize(width: 1100, height: 800)
    }
}

/// SwiftUI apps built with plain SwiftPM (no Xcode app target) don't get a Dock icon or
/// proper key-window focus by default. Setting `.regular` activation policy and activating
/// on launch fixes keyboard focus — essential for the KeyCatcher to receive arrow keys.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
