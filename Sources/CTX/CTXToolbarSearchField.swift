import AppKit
import SwiftUI

/// Native toolbar fields need to request the field editor after window attachment.
struct CTXToolbarSearchField: NSViewRepresentable {
    let prompt: String
    @Binding var text: String
    let onFocusChanged: (Bool) -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> FocusedField {
        let field = FocusedField()
        field.placeholderString = prompt
        field.setAccessibilityLabel(prompt)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.submit)
        field.onFocusAcquired = { context.coordinator.parent.onFocusChanged(true) }
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: FocusedField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    final class FocusedField: NSTextField {
        var onFocusAcquired: (() -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                if window.makeFirstResponder(self) { self.onFocusAcquired?() }
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CTXToolbarSearchField
        init(_ parent: CTXToolbarSearchField) { self.parent = parent }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.onFocusChanged(true)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            let movement = notification.userInfo?["NSTextMovement"] as? Int
            if movement != NSReturnTextMovement { parent.onFocusChanged(false) }
        }

        @objc func submit() { parent.onSubmit() }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
            parent.onCancel()
            return true
        }
    }
}
