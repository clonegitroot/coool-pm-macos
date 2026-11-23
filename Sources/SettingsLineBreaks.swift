import SwiftUI

/// Route Command–Return to the active text editor, including an AppKit field editor.
struct SettingsLineBreaks: NSViewRepresentable {
    final class Host: NSView {
        private var monitor: Any?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let window = self?.window, event.window === window,
                      event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command,
                      [36, 76].contains(event.keyCode),
                      let editor = window.firstResponder as? NSTextView, editor.isEditable else { return event }
                editor.insertText("\n", replacementRange: editor.selectedRange())
                return nil
            }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
    func makeNSView(context: Context) -> Host { Host() }
    func updateNSView(_ view: Host, context: Context) {}
}
