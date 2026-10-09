import Foundation

/// What the app remembers (W11): the backup folder and thinning (W14).
public struct Preferences: Codable, Sendable, Equatable {
    /// Another backup folder; nil for ~/Mac Plus Backups.
    public var repositoryPath: String?
    /// W14: on by default (the owner's choice).
    public var thinning = true

    public init() {}

    public var repository: Repository {
        repositoryPath.map { Repository(root: URL(fileURLWithPath: $0, isDirectory: true)) } ?? Repository()
    }

    static let key = "MacintoshBackupUtility.preferences"

    public static func load(from defaults: UserDefaults = .standard) -> Preferences {
        guard let d = defaults.data(forKey: key), let p = try? JSONDecoder().decode(Preferences.self, from: d) else {
            return Preferences()
        }
        return p
    }

    public func save(to defaults: UserDefaults = .standard) {
        if let d = try? JSONEncoder().encode(self) { defaults.set(d, forKey: Preferences.key) }
    }
}
