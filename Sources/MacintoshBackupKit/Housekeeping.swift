import Foundation

/// Removing snapshots, only when the owner asks and confirms (brief §10,
/// §14): the folder must be one of this repository's own snapshot
/// folders, its manifest must name the snapshot asked for, and it goes to
/// the Trash, so a mistake can be undone. Nothing is ever removed by
/// itself.
public extension Repository {
    enum DeleteError: Error, Equatable, Sendable {
        case notConfirmed, notASnapshot(String), wrongSnapshot

        public var message: String {
            switch self {
            case .notConfirmed: "The deletion wasn't confirmed."
            case .notASnapshot(let n): "\(n) isn't one of this backup folder's snapshots."
            case .wrongSnapshot: "That folder holds a different snapshot."
            }
        }
    }

    /// Moves a snapshot folder (by its folder name in Snapshots) to the
    /// Trash. `id` must be its manifest's snapshot ID, if it has one.
    /// How a folder is removed: to the Trash (the app), or elsewhere (the
    /// tests, which mustn't fill the owner's Trash).
    typealias Remover = @Sendable (URL) throws -> URL?
    static let toTrash: Remover = { url in
        var trashed: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
        return trashed as URL?
    }

    @discardableResult
    func delete(folder name: String, id: UUID?, confirmed: Bool, remover: Remover = Repository.toTrash) throws -> URL? {
        guard confirmed else { throw DeleteError.notConfirmed }
        guard !name.contains("/"), name != ".", name != "..",
              Catalog.folders(self).contains(name) else { throw DeleteError.notASnapshot(name) }
        let url = snapshots.appendingPathComponent(name, isDirectory: true)
        let m = try? Manifest.read(url.appendingPathComponent(Manifest.fileName))
        if let id { guard m?.snapshotID == id else { throw DeleteError.wrongSnapshot } }
        else if m != nil, !name.hasPrefix(".incomplete-") { throw DeleteError.wrongSnapshot }
        let removed = try remover(url)
        _ = try? Catalog.rebuild(self)
        return removed
    }

    /// The card's verified snapshots other than `name`: none means deleting
    /// it leaves the card with no backup (the window warns).
    func otherRestorePoints(than name: String, volumeUUID: String?, cardID: UUID? = nil) throws -> [Catalog.Summary] {
        try Catalog.load(self).restorePoints.filter {
            $0.folder != name && $0.isOfCard(cardID, volumeUUID: volumeUUID, volumeName: nil)
        }
    }
}
