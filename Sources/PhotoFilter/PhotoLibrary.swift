import Photos
import AppKit

/// Which set of items to review.
enum PhotoSource: String, CaseIterable, Identifiable {
    case screenshots = "截图"
    case all = "全部"
    var id: String { rawValue }
}

/// Thin wrapper around PhotoKit. Operates on the System Photo Library, which is the
/// iCloud-Photos-synced library — so deletions here propagate to iCloud and the iPhone
/// (landing in "Recently Deleted" for 30 days).
///
/// Completion handlers are invoked on arbitrary queues; callers are responsible for
/// hopping back to the main actor.
final class PhotoLibrary {
    private let imageManager = PHCachingImageManager()

    func requestAuthorization(_ completion: @escaping (PHAuthorizationStatus) -> Void) {
        // .readWrite is required because we delete assets.
        PHPhotoLibrary.requestAuthorization(for: .readWrite, handler: completion)
    }

    func fetch(source: PhotoSource) -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result: PHFetchResult<PHAsset>
        switch source {
        case .screenshots:
            options.predicate = NSPredicate(
                format: "(mediaSubtype & %d) != 0",
                PHAssetMediaSubtype.photoScreenshot.rawValue
            )
            result = PHAsset.fetchAssets(with: .image, options: options)
        case .all:
            // No media-type filter → images, videos, Live Photos, screen recordings.
            result = PHAsset.fetchAssets(with: options)
        }
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    /// Requests a full-screen display image (poster frame for videos). With `.opportunistic`
    /// delivery the handler may be called more than once (fast low-res, then sharp) — callers
    /// should accept each call and just replace what they're showing.
    func requestImage(for asset: PHAsset, completion: @escaping (NSImage?) -> Void) {
        requestImage(for: asset, targetSize: Self.fullScreenSize(), contentMode: .aspectFit, completion: completion)
    }

    /// Smaller image for grid thumbnails (aspect-fill, cropped).
    func requestThumbnail(for asset: PHAsset, targetSize: CGSize, completion: @escaping (NSImage?) -> Void) {
        requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, completion: completion)
    }

    private func requestImage(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode,
        completion: @escaping (NSImage?) -> Void
    ) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true   // allow iCloud-optimized originals to download
        options.resizeMode = .fast
        options.isSynchronous = false
        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: contentMode,
            options: options
        ) { image, _ in
            completion(image)
        }
    }

    /// All non-screenshot still images (Live-Photo stills included), creationDate ASCENDING —
    /// the organize module's grouper sweeps chronologically. Screenshots belong to the
    /// screenshot module and videos to a future module, so both are excluded here.
    /// Scoped to the user's own library source: keeps old-style shared-album photos out.
    /// (iCloud "共享图库" photos are NOT separable — PhotoKit reports them as user-library
    /// assets with no public API to tell them apart; Apple confirmed this limitation.)
    func fetchPersonalImages() -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.includeAssetSourceTypes = [.typeUserLibrary]
        options.predicate = NSPredicate(
            format: "(mediaSubtype & %d) == 0",
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    /// Every iCloud shared album ("共享相册") the user participates in.
    func fetchSharedAlbums() -> [PHAssetCollection] {
        let result = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .albumCloudShared, options: nil
        )
        var albums: [PHAssetCollection] = []
        albums.reserveCapacity(result.count)
        result.enumerateObjects { album, _, _ in albums.append(album) }
        return albums
    }

    /// All assets (photos AND videos) inside one shared album, oldest first — matching
    /// how Photos presents shared albums.
    func fetchAssets(in album: PHAssetCollection) -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result = PHAsset.fetchAssets(in: album, options: options)
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    /// Removes assets from a shared album. Unlike deletion this shows NO system dialog
    /// and does NOT land in "Recently Deleted" — and PhotoKit only allows removing the
    /// user's own contributions; removing someone else's photo fails the whole batch.
    func removeFromSharedAlbum(
        _ assets: [PHAsset],
        album: PHAssetCollection,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        PHPhotoLibrary.shared().performChanges {
            PHAssetCollectionChangeRequest(for: album)?.removeAssets(assets as NSFastEnumeration)
        } completionHandler: { success, error in
            completion(success, error)
        }
    }

    /// Synchronous small-thumbnail fetch for the similarity scan. MUST be called off the
    /// main thread. ~300px requests are normally served from the local thumbnail cache even
    /// for iCloud-optimized libraries (network stays allowed as a fallback), and a slightly
    /// degraded thumb is fine for feature prints. Goes through the plain image manager so
    /// the flashcard module's prefetch cache is untouched.
    func requestScanImage(for asset: PHAsset, side: CGFloat) -> CGImage? {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        options.deliveryMode = .highQualityFormat
        var image: NSImage?
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: side, height: side),
            contentMode: .aspectFit,
            options: options
        ) { result, _ in
            image = result
        }
        guard let image else { return nil }
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    /// Prefetch the next handful of assets so advancing feels instant.
    func startCaching(_ assets: [PHAsset]) {
        guard !assets.isEmpty else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        imageManager.startCachingImages(
            for: assets,
            targetSize: Self.fullScreenSize(),
            contentMode: .aspectFit,
            options: options
        )
    }

    func resetCache() {
        imageManager.stopCachingImagesForAllAssets()
    }

    /// Prefetch grid-sized thumbnails (organize module group cards). Separate from
    /// `startCaching` — that one targets full-screen flashcard images and would make
    /// prefetching hundreds of grouped assets needlessly expensive.
    func startCachingThumbnails(for assets: [PHAsset], targetSize: CGSize) {
        guard !assets.isEmpty else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        imageManager.startCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        )
    }

    /// Deletes all given assets in a single change request, which triggers ONE system
    /// confirmation dialog for the whole batch. Confirmed deletions sync to iCloud/iPhone.
    func delete(_ assets: [PHAsset], completion: @escaping (Bool, Error?) -> Void) {
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSFastEnumeration)
        } completionHandler: { success, error in
            completion(success, error)
        }
    }

    /// Full-screen pixel size, used as the display-image request target.
    private static func fullScreenSize() -> CGSize {
        let screen = NSScreen.main
        let scale = screen?.backingScaleFactor ?? 2
        let size = screen?.frame.size ?? CGSize(width: 1440, height: 900)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}
