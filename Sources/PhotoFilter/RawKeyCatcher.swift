import SwiftUI
import AppKit

/// Generic full-window key capture for the organize module. The original `KeyCatcher`
/// hard-codes the five flashcard closures and belongs to the screenshot module, which
/// stays untouched — so the organize module gets this variant that forwards every
/// keyDown to one handler. The two catchers are never in the view hierarchy at the same
/// time (modules are exclusive screens), so they can't fight over first responder.
struct RawKeyCatcher: NSViewRepresentable {
    /// Return true if the event was consumed; false lets AppKit handle it normally
    /// (needed so e.g. Return still reaches a SwiftUI `.keyboardShortcut` button).
    var onKeyDown: (NSEvent) -> Bool

    func makeNSView(context: Context) -> RawKeyCatcherView {
        let view = RawKeyCatcherView()
        view.onKeyDown = onKeyDown
        return view
    }

    func updateNSView(_ nsView: RawKeyCatcherView, context: Context) {
        nsView.onKeyDown = onKeyDown
        // Reclaim first responder after a button/picker briefly stole focus.
        DispatchQueue.main.async {
            if nsView.window?.firstResponder !== nsView {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

final class RawKeyCatcherView: NSView {
    var onKeyDown: ((NSEvent) -> Bool)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) != true {
            super.keyDown(with: event)
        }
    }
}
