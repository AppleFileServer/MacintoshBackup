import Foundation

public enum BackupError: Error, Equatable, Sendable {
    case sourceUnreadable(String)
    case repositoryUnavailable(String)
    case insufficientSpace(needed: Int64, available: Int64)
    case snapshotExists(String)
    case manifestInvalid(String)

    public var message: String {
        switch self {
        case .sourceUnreadable(let p): "The card couldn't be read: \(p)"
        case .repositoryUnavailable(let p): "The backup folder isn't available, or can't be written to: \(p)"
        case .insufficientSpace(let n, let a):
            "There isn't room for the backup: it needs about \(n / 1_000_000) MB, and \(a / 1_000_000) MB is free."
        case .snapshotExists(let n): "A snapshot called \(n) is already there, so this one wasn't saved."
        case .manifestInvalid(let why): "The snapshot's manifest isn't valid: \(why)"
        }
    }
}
