// swift-tools-version: 6.0
// Macintosh Backup Utility (Documentation/SPECIFICATION.md §20): the
// engine as a library, its tests, and the developer's tool (Stages 1-2).
import PackageDescription

let package = Package(
    name: "MacintoshBackup",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "MacintoshBackupKit", targets: ["MacintoshBackupKit"]),
        .executable(name: "mbu", targets: ["mbu"]),
    ],
    targets: [
        .target(name: "MacintoshBackupKit"),
        .executableTarget(name: "mbu", dependencies: ["MacintoshBackupKit"]),
        .testTarget(name: "MacintoshBackupKitTests", dependencies: ["MacintoshBackupKit"]),
    ]
)
