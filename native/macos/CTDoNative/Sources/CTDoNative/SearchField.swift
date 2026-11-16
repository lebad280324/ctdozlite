import AppKit
import SwiftUI

/// A toolbar search field requests AppKit focus after it has joined its window.
struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    var focusRequest: UUID
    var onSubmit: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> TypingSearchField {
        let field = TypingSearchField()
        field.placeholderString = "Tìm kiếm"
        field.font = .systemFont(ofSize: 14)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        field.setAccessibilityLabel("Tìm kiếm")
        field.requestTypingFocus()
        return field
    }
    func updateNSView(_ field: TypingSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text, (field.currentEditor() as? NSTextView)?.hasMarkedText() != true {
            field.stringValue = text
        }
        if context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
            field.requestTypingFocus()
        }
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NativeSearchField
        var focusRequest: UUID?
        init(_ parent: NativeSearchField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { parent.text = field.stringValue }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.cancelOperation(_:)) { parent.onCancel(); return true }
            if selector == #selector(NSResponder.insertNewline(_:)), !textView.hasMarkedText() { parent.onSubmit(); return true }
            return false
        }
    }
}

final class TypingSearchField: NSTextField {
    private var needsTypingFocus = false
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if needsTypingFocus { requestTypingFocus() }
    }
    func requestTypingFocus() {
        needsTypingFocus = true
        DispatchQueue.main.async { [weak self] in
            guard let self, self.needsTypingFocus, let window = self.window else { return }
            if window.makeFirstResponder(self) { self.needsTypingFocus = false }
        }
    }
}
