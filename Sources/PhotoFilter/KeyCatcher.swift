import SwiftUI
import AppKit

/// A full-window, invisible AppKit view that captures keys reliably via the responder
/// chain. SwiftUI's `.onKeyPress` can be flaky about focus for arrow keys on macOS, so this
/// is the single source of truth for keyboard culling. It reclaims first responder whenever
/// the view updates (e.g. after a button/picker briefly stole focus).
///
/// When `enabled` is false (the review grid is open) the culling keys are ignored and only
/// Escape is handled, so arrow presses can't mutate the underlying deck.
struct KeyCatcher: NSViewRepresentable {
    var enabled: Bool
    var onLeft: () -> Void
    var onRight: () -> Void
    var onUndo: () -> Void
    var onZoom: () -> Void
    var onEscape: () -> Void

    func makeNSView(context: Context) -> KeyCatcherView {
        let view = KeyCatcherView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: KeyCatcherView, context: Context) {
        apply(to: nsView)
        DispatchQueue.main.async {
            if nsView.window?.firstResponder !== nsView {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    private func apply(to view: KeyCatcherView) {
        view.enabled = enabled
        view.onLeft = onLeft
        view.onRight = onRight
        view.onUndo = onUndo
        view.onZoom = onZoom
        view.onEscape = onEscape
    }
}

final class KeyCatcherView: NSView {
    var enabled = true
    var onLeft: (() -> Void)?
    var onRight: (() -> Void)?
    var onUndo: (() -> Void)?
    var onZoom: (() -> Void)?
    var onEscape: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        // Escape always works (so it can dismiss the review grid).
        if event.keyCode == 53 { onEscape?(); return }

        guard enabled else { super.keyDown(with: event); return }

        switch event.keyCode {
        case 123: onLeft?()    // ← left arrow  → mark for deletion
        case 124: onRight?()   // → right arrow → keep
        case 126: onUndo?()    // ↑ up arrow    → undo
        case 49:  onZoom?()    // space         → toggle zoom
        case 6 where event.modifierFlags.contains(.command): onUndo?()  // ⌘Z → undo
        default: super.keyDown(with: event)
        }
    }
}
