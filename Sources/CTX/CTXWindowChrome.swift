import AppKit
import SwiftUI

/// Which windows get CTX's chromeless, vibrant treatment.
///
/// Opt-in on purpose. The app delegate used to clear the background of every
/// titled window that became key, so the Settings window was transparent too —
/// and an `NSOpenPanel` run over it had the desktop showing through behind it.
/// Only the windows CTX actually designs ask for that treatment; everything
/// else, now and later, is a normal macOS window.
@MainActor
enum CTXWindowChrome {
    private static var chromeless = Set<ObjectIdentifier>()

    static func markChromeless(_ window: NSWindow) {
        chromeless.insert(ObjectIdentifier(window))
        apply(to: window)
    }

    static func apply(to window: NSWindow) {
        guard window.styleMask.contains(.titled),
              chromeless.contains(ObjectIdentifier(window)) else { return }

        // Ensure all standard window controls (close, minimize, zoom/fullscreen)
        // are enabled in the styleMask so macOS renders the traffic lights.
        window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        // Ensure native traffic light buttons (Close, Minimize, Zoom) remain
        // visible, enabled, and interactive regardless of window dimensions or state.
        ensureStandardButtonsVisible(on: window)

        // Let AppKit reserve dragging for the real title-bar area. Enabling
        // background dragging on a full-size SwiftUI content view can consume
        // mouse-down events before plain buttons, menus, list rows and toggles
        // receive them, making otherwise enabled controls appear intermittent.
        window.isMovableByWindowBackground = false

        // A real backing color gives SwiftUI/AppKit something deterministic to
        // repaint when translucent list rows move. The visual-effect view still
        // supplies the material above it.
        window.backgroundColor = .windowBackgroundColor
        window.titlebarSeparatorStyle = .none
        if let toolbar = window.toolbar, toolbar.items.isEmpty {
            window.toolbar = nil
        }
    }

    /// Verifies and forces the standard window buttons (close, minimize, zoom)
    /// to remain visible and fully interactive in the window's titlebar hierarchy.
    static func ensureStandardButtonsVisible(on window: NSWindow) {
        let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for buttonType in buttonTypes {
            guard let button = window.standardWindowButton(buttonType) else { continue }
            button.isHidden = false
            button.isEnabled = true
            button.alphaValue = 1.0

            // Ensure container hierarchy leading to the buttons is not hidden
            var ancestor: NSView? = button.superview
            while let current = ancestor, current !== window.contentView?.superview {
                current.isHidden = false
                current.alphaValue = 1.0
                ancestor = current.superview
            }
        }
    }
}

private struct ChromelessWindowMarker: NSViewRepresentable {
    let title: String?
    let removeToolbar: Bool

    init(title: String? = nil, removeToolbar: Bool = false) {
        self.title = title
        self.removeToolbar = removeToolbar
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // The view has no window until it is in the hierarchy.
        DispatchQueue.main.async {
            if let window = view.window {
                CTXWindowChrome.markChromeless(window)
                if let title, !title.isEmpty {
                    window.title = title
                }
                if removeToolbar {
                    window.toolbar = nil
                    window.titlebarSeparatorStyle = .none
                }
                CTXWindowChrome.ensureStandardButtonsVisible(on: window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            CTXWindowChrome.markChromeless(window)
            if let title, !title.isEmpty {
                window.title = title
            }
            if removeToolbar {
                window.toolbar = nil
                window.titlebarSeparatorStyle = .none
            }
            CTXWindowChrome.ensureStandardButtonsVisible(on: window)
        }
    }
}

extension View {
    /// Marks this view's window as one of CTX's own designed windows.
    func ctxChromelessWindow(title: String? = nil, removeToolbar: Bool = false) -> some View {
        background(ChromelessWindowMarker(title: title, removeToolbar: removeToolbar))
    }
}
