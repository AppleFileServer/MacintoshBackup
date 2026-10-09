import SwiftUI
import MacintoshBackupKit

/// Macintosh Backup Utility: one window, and Settings (Stage 3, W1-W14).
@main
struct MacintoshBackupApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

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
