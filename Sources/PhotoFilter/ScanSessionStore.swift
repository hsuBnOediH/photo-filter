import Foundation
import Photos

/// Persists organize-module scan results across launches so a half-finished review
/// session resumes instead of rescanning. Stores asset *identifiers* only — assets are
/// re-fetched on restore and anything deleted in the meantime silently drops out.
struct ScanSession: Codable {
    struct Group: Codable {
        var recommendedID: String     // == PhotoGroup.id
        var assetIDs: [String]
    }

    var version = 1
    /// Feature-print revision the groups were computed with — a Vision upgrade
    /// invalidates the session along with the print cache.
    var engineRevision: Int
    var savedAt: Date
    var timeWindow: Int
    var similarity: String
    var groups: [Group]
    var reviewedGroupIDs: [String]
    var markedIDs: [String]
    var cursorGroup: Int
    var cursorPhoto: Int
}

enum ScanSessionStore {
    private static var fileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = support.appendingPathComponent("PhotoFilter", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ScanSession.json")
    }

    static func save(_ session: ScanSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func load() -> ScanSession? {
        guard let data = try? Data(contentsOf: fileURL),
              let session = try? JSONDecoder().decode(ScanSession.self, from: data),
              session.version == 1,
              session.engineRevision == SimilarityEngine.revision
        else { return nil }
        return session
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Re-resolve a stored session against the live photo library: one batched fetch,
    /// vanished assets dropped, groups that fall below 2 members dropped with them.
    static func rebuildGroups(from session: ScanSession) -> [PhotoGroup] {
        let allIDs = session.groups.flatMap(\.assetIDs)
        guard !allIDs.isEmpty else { return [] }
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: allIDs, options: nil)
        var byID: [String: PHAsset] = [:]
        fetched.enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }

        return session.groups.compactMap { stored in
            let assets = stored.assetIDs.compactMap { byID[$0] }
            guard assets.count >= 2 else { return nil }
            // If the stored keeper vanished, recompute the recommendation.
            let recommendedID = byID[stored.recommendedID] != nil
                ? stored.recommendedID
                : AssetGrouper.recommendKeeper(in: assets).localIdentifier
            return PhotoGroup(id: stored.recommendedID, assets: assets, recommendedID: recommendedID)
        }
    }
}
