import SwiftUI
import MacintoshBackupKit

/// Macintosh Backup Utility: one window, and Settings (Stage 3, W1-W14).
@main
struct MacintoshBackupApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    /// `--self-test` (Stage 6): no window; a test card in a temporary
    /// folder only; prints the report and quits, 0 if it passed.
    init() {
        guard CommandLine.arguments.contains("--self-test") else { return }
        Task.detached {
            let (passed, report) = await SelfTest.run()
            for line in report { print(line) }
            exit(passed ? 0 : 1)
        }
        DispatchSemaphore(value: 0).wait()          // until the test exits
    }

    var body: some Scene {
        Window("Macintosh Backup Utility", id: "main") {
            MainWindowView(model: model)
                .onAppear { delegate.model = model }
                .background(WindowFinder { delegate.watch($0) })
        }
        .defaultSize(width: 1000, height: 700)
        .windowResizability(.contentMinSize)
        Settings { SettingsView(model: model) }
    }
}
