// swift-tools-version: 6.0
// Macintosh Backup Utility (Documentation/SPECIFICATION.md §20): the
// engine as a library, its tests, the developer's tool (Stages 1-2) and
// the SwiftUI app (Stage 3; tools/build-app.sh wraps it).
import PackageDescription

let package = Package(
    name: "MacintoshBackup",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "MacintoshBackupKit", targets: ["MacintoshBackupKit"]),
        .executable(name: "mbu", targets: ["mbu"]),
        .executable(name: "MacintoshBackup", targets: ["MacintoshBackup"]),
    ],
    targets: [
        .target(name: "MacintoshBackupKit"),
        .executableTarget(name: "mbu", dependencies: ["MacintoshBackupKit"]),
        // The SwiftUI app (Stage 3): the window, over the library.
        .executableTarget(name: "MacintoshBackup", dependencies: ["MacintoshBackupKit"]),
        .testTarget(name: "MacintoshBackupKitTests", dependencies: ["MacintoshBackupKit"]),
    ]
)
