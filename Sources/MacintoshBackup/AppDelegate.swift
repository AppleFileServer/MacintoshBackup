import AppKit
import MacintoshBackupKit

/// Quitting safely (W12): closing the window quits; during a backup, it
/// asks first, and cancels the backup, which then isn't a restore point.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private var quitting = false
    private var guards: [CloseGuard] = []

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if quitting || !(model?.running ?? false) { return .terminateNow }
        return confirmStop() ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) { model?.cancel() }

    func confirmStop() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Stop the backup and quit?"
        alert.informativeText = "The snapshot being made won't be kept as a restore point. Your earlier backups aren't affected, and nothing on the card has been changed."
        alert.addButton(withTitle: "Keep Backing Up")
        alert.addButton(withTitle: "Stop and Quit")
        alert.buttons[1].hasDestructiveAction = true
        guard alert.runModal() == .alertSecondButtonReturn else { return false }
        quitting = true
        model?.cancel()
        return true
    }

    func watch(_ window: NSWindow) {
        guard !guards.contains(where: { $0.window === window }) else { return }
        let g = CloseGuard(window: window) { [weak self] in
            guard let self, self.model?.running == true, !self.quitting else { return true }
            if self.confirmStop() { DispatchQueue.main.async { NSApp.terminate(nil) } }
            return false
        }
        guards.append(g)
    }
}
/// Stands in front of a window's delegate (SwiftUI's), to ask before the
/// window closes; everything else is passed on to the real delegate.
final class CloseGuard: NSObject, NSWindowDelegate {
    weak var window: NSWindow?
    weak var original: NSWindowDelegate?
    let shouldClose: @MainActor () -> Bool

    @MainActor
    init(window: NSWindow, shouldClose: @escaping @MainActor () -> Bool) {
        self.window = window
        self.original = window.delegate
        self.shouldClose = shouldClose
        super.init()
        window.delegate = self
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let allowed = MainActor.assumeIsolated { shouldClose() }
        guard allowed else { return false }
        return original?.windowShouldClose?(sender) ?? true
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (original?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        original?.responds(to: aSelector) == true ? original : super.forwardingTarget(for: aSelector)
    }
}
