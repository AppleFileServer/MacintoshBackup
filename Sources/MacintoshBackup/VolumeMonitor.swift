import AppKit
import MacintoshBackupKit

/// macOS's word that a disk has appeared or gone (C1), handed to the
/// model; and the disks already there at launch.
@MainActor
final class VolumeMonitor {
    nonisolated static func url(_ n: Notification, _ key: String = NSWorkspace.volumeURLUserInfoKey) -> URL? {
        n.userInfo?[key] as? URL
    }

    private var observers: [NSObjectProtocol] = []

    init(mounted: @escaping @MainActor (URL) -> Void, unmounted: @escaping @MainActor (URL) -> Void) {
        let centre = NSWorkspace.shared.notificationCenter
        observers.append(centre.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { n in
            if let u = VolumeMonitor.url(n) { MainActor.assumeIsolated { mounted(u) } }
        })
        observers.append(centre.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { n in
            if let u = VolumeMonitor.url(n) { MainActor.assumeIsolated { unmounted(u) } }
        })
        observers.append(centre.addObserver(forName: NSWorkspace.didRenameVolumeNotification, object: nil, queue: .main) { n in
            let old = VolumeMonitor.url(n, NSWorkspace.oldVolumeURLUserInfoKey), new = VolumeMonitor.url(n)
            MainActor.assumeIsolated {
                if let old { unmounted(old) }
                if let new { mounted(new) }
            }
        })
        for u in FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? [] {
            mounted(u)
        }
    }
}
