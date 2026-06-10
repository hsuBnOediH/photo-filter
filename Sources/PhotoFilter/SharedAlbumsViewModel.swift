import SwiftUI
import Photos

/// Drives the shared-albums module: browse each iCloud shared album ("共享相册") and
/// remove the user's own contributions. Self-contained like the other modules.
///
/// Removal semantics differ from library deletion in two ways the UI must surface:
/// no system confirmation dialog appears (so the module shows its own), and removed
/// photos do NOT go to "Recently Deleted" — removal is immediate for every member.
/// PhotoKit only permits removing the user's own posts; a batch containing someone
/// else's photo fails as a whole.
@MainActor
final class SharedAlbumsViewModel: ObservableObject {
    @Published var authStatus: PHAuthorizationStatus = .notDetermined
    @Published private(set) var albums: [PHAssetCollection] = []
    @Published private(set) var selectedAlbumIndex = 0
    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var markedIDs: Set<String> = []
    @Published private(set) var isCommitting = false
    @Published var resultMessage: String?
    /// Drives the result line's color — checking message text would break across locales.
    @Published private(set) var lastRemovalFailed = false

    private let library = PhotoLibrary()
    private let thumbCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 800
        return cache
    }()

    var markedCount: Int { markedIDs.count }

    var selectedAlbum: PHAssetCollection? {
        albums.indices.contains(selectedAlbumIndex) ? albums[selectedAlbumIndex] : nil
    }

    func isMarked(_ asset: PHAsset) -> Bool {
        markedIDs.contains(asset.localIdentifier)
    }

    // MARK: Lifecycle

    func requestAccess() {
        library.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                self.authStatus = status
                if status == .authorized || status == .limited, self.albums.isEmpty {
                    self.reloadAlbums()
                }
            }
        }
    }

    func reloadAlbums() {
        albums = library.fetchSharedAlbums()
        selectAlbum(0)
    }

    func selectAlbum(_ index: Int) {
        selectedAlbumIndex = index
        markedIDs = []
        resultMessage = nil
        if let album = selectedAlbum {
            assets = library.fetchAssets(in: album)
        } else {
            assets = []
        }
    }

    // MARK: Marking + removal

    func toggle(_ asset: PHAsset) {
        if markedIDs.contains(asset.localIdentifier) {
            markedIDs.remove(asset.localIdentifier)
        } else {
            markedIDs.insert(asset.localIdentifier)
        }
    }

    /// Removes the marked assets from the current shared album (after the module's own
    /// confirmation — PhotoKit shows none for album removal).
    func commitRemoval() {
        guard let album = selectedAlbum else { return }
        let toRemove = assets.filter { markedIDs.contains($0.localIdentifier) }
        guard !toRemove.isEmpty, !isCommitting else { return }
        isCommitting = true
        library.removeFromSharedAlbum(toRemove, album: album) { [weak self] success, error in
            Task { @MainActor in
                guard let self else { return }
                self.isCommitting = false
                if success {
                    let removedIDs = Set(toRemove.map(\.localIdentifier))
                    self.assets.removeAll { removedIDs.contains($0.localIdentifier) }
                    self.markedIDs = []
                    self.lastRemovalFailed = false
                    self.resultMessage = L("shared.result.removed",
                                           album.localizedTitle ?? L("shared.album.untitled"), toRemove.count)
                } else {
                    self.lastRemovalFailed = true
                    self.resultMessage = L("shared.result.failed",
                                           error?.localizedDescription ?? L("shared.error.unknown"))
                }
            }
        }
    }

    // MARK: Thumbnails (same cache pattern as the organize module)

    func cachedThumbnail(for asset: PHAsset) -> NSImage? {
        thumbCache.object(forKey: asset.localIdentifier as NSString)
    }

    func loadThumbnail(for asset: PHAsset, size: CGSize, completion: @escaping (NSImage?) -> Void) {
        if let cached = cachedThumbnail(for: asset) {
            completion(cached)
            return
        }
        let cache = thumbCache
        library.requestThumbnail(for: asset, targetSize: size) { image in
            if let image {
                cache.setObject(image, forKey: asset.localIdentifier as NSString)
            }
            completion(image)
        }
    }
}
