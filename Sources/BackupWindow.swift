import AppKit
import SwiftUI

@MainActor
final class BackupQuitDelegate: NSObject, NSApplicationDelegate {
    static weak var library: BackupWindow.Coordinator?
    static var templateSampleFolders: [URL] = []

    func applicationWillTerminate(_ notification: Notification) {
        for folder in Self.templateSampleFolders {
            try? FileManager.default.removeItem(at: folder)
        }
        Self.templateSampleFolders.removeAll()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Self.library?.allowClose() == false ? .terminateCancel : .terminateNow
    }
}

/// Keep the standard SwiftUI window delegate for all window behavior except the backup prompt.
struct BackupWindow: NSViewRepresentable {
    let allowClose: () -> Bool

    final class Coordinator: NSObject, NSWindowDelegate {
        weak var window: NSWindow?
        var original: NSWindowDelegate?
        var allowClose: () -> Bool

        init(_ action: @escaping () -> Bool) { allowClose = action }

        @MainActor func attach(_ newWindow: NSWindow?) {
            guard let newWindow, window !== newWindow else { return }
            detach()
            original = newWindow.delegate
            window = newWindow
            newWindow.delegate = self
            BackupQuitDelegate.library = self
        }
        @MainActor func detach() {
            if window?.delegate === self { window?.delegate = original }
            if BackupQuitDelegate.library === self { BackupQuitDelegate.library = nil }
            original = nil
            window = nil
        }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard original?.windowShouldClose?(sender) != false else { return false }
            return allowClose()
        }
        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || original?.responds(to: selector) == true
        }
        override func forwardingTarget(for selector: Selector!) -> Any? {
            original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector)
        }
    }

    final class Anchor: NSView {
        weak var owner: Coordinator?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            owner?.attach(window)
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(allowClose) }
    func makeNSView(context: Context) -> Anchor {
        let view = Anchor()
        view.owner = context.coordinator
        return view
    }
    func updateNSView(_ view: Anchor, context: Context) { context.coordinator.allowClose = allowClose }
    static func dismantleNSView(_ view: Anchor, coordinator: Coordinator) { coordinator.detach() }
}

private struct BackUpNowKey: FocusedValueKey { typealias Value = () -> Void }
extension FocusedValues {
    var backUpNow: (() -> Void)? {
        get { self[BackUpNowKey.self] }
        set { self[BackUpNowKey.self] = newValue }
    }
}

struct BackupCommands: Commands {
    let locale: Locale
    @FocusedValue(\.backUpNow) private var backUpNow
    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Button(AppLanguage.text("Create Backup Now", fallback: "Create Backup Now", locale: locale)) { backUpNow?() }
                .keyboardShortcut("b", modifiers: [.command, .option])
                .disabled(backUpNow == nil)
        }
    }
}
