import SwiftUI
import Photos

/// Drives the flashcard culling flow: holds the deck of assets, the current index, the
/// in-memory "marked for deletion" set, and an undo stack. No PhotoKit *writes* happen
/// until `commit()` — every keystroke only mutates in-memory state, which is what keeps
/// the review fast and makes undo trivial.
@MainActor
final class CullViewModel: ObservableObject {
    @Published var authStatus: PHAuthorizationStatus = .notDetermined
    @Published var source: PhotoSource = .screenshots
    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var index: Int = 0
    @Published private(set) var markedIDs: Set<String> = []
    @Published private(set) var currentImage: NSImage?
    @Published private(set) var isCommitting = false
    /// When true, the pre-commit thumbnail review grid is shown instead of the culling view.
    @Published var isReviewingMarked = false
    @Published var resultMessage: String?

    private let library = PhotoLibrary()
    private var undoStack: [UndoAction] = []

    /// Records enough to reverse a single keep/delete decision.
    private struct UndoAction {
        let index: Int
        let assetID: String
        let wasMarked: Bool   // whether the asset was marked-for-deletion *before* this action
    }

    // MARK: Derived state

    var total: Int { assets.count }
    var isFinished: Bool { !assets.isEmpty && index >= assets.count }
    var markedCount: Int { markedIDs.count }
    var canUndo: Bool { !undoStack.isEmpty }

    var currentAsset: PHAsset? {
        guard index >= 0, index < assets.count else { return nil }
        return assets[index]
    }

    var currentIsMarked: Bool {
        guard let asset = currentAsset else { return false }
        return markedIDs.contains(asset.localIdentifier)
    }

    /// Marked assets in deck order — feeds the review grid.
    var markedAssets: [PHAsset] {
        assets.filter { markedIDs.contains($0.localIdentifier) }
    }

    // MARK: Lifecycle

    func requestAccess() {
        library.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                self.authStatus = status
                // Only load the deck if it isn't loaded yet. requestAccess() runs on
                // every onAppear — since the module home screen was added that means
                // every re-entry into this module, and an unconditional reload() would
                // wipe the user's marks and deck progress.
                if status == .authorized || status == .limited, self.assets.isEmpty {
                    self.reload(resume: true)
                }
            }
        }
    }

    func setSource(_ newSource: PhotoSource) {
        guard newSource != source else { return }
        source = newSource
        reload(resume: true)
    }

    /// `resume: true` (module entry, source switch) continues from the position saved
    /// on disk, so a session that ended mid-deck picks up where it stopped. The plain
    /// `reload()` of the 「重新加载」 button starts over and clears that saved position.
    func reload(resume: Bool = false) {
        library.resetCache()
        assets = library.fetch(source: source)
        index = 0
        markedIDs = []
        undoStack = []
        isReviewingMarked = false
        resultMessage = nil
        if resume {
            restoreProgress()
        } else {
            UserDefaults.standard.removeObject(forKey: progressKey)
        }
        loadCurrent()
        prefetch()
    }

    // MARK: Culling actions (keyboard-driven)

    /// `←` — mark the current photo for deletion and advance.
    func markDelete() {
        guard let asset = currentAsset else { return }
        pushUndo(asset)
        markedIDs.insert(asset.localIdentifier)
        advance()
    }

    /// `→` — keep the current photo and advance.
    func keep() {
        guard let asset = currentAsset else { return }
        pushUndo(asset)
        markedIDs.remove(asset.localIdentifier)
        advance()
    }

    /// `↑` / `⌘Z` — step back to the previous photo and restore its prior marked state.
    func undo() {
        guard let last = undoStack.popLast() else { return }
        index = last.index
        if last.wasMarked {
            markedIDs.insert(last.assetID)
        } else {
            markedIDs.remove(last.assetID)
        }
        loadCurrent()
        prefetch()
        saveProgress()
    }

    // MARK: Review + commit

    /// Open the pre-commit review grid (only if there's something marked).
    func beginReview() {
        guard markedCount > 0 else { return }
        resultMessage = nil
        isReviewingMarked = true
    }

    /// Remove an asset from the marked set (used by the review grid).
    func unmark(_ asset: PHAsset) {
        markedIDs.remove(asset.localIdentifier)
        if markedIDs.isEmpty { isReviewingMarked = false }
    }

    /// Deletes every marked asset in one batch → one system confirmation → syncs to iPhone.
    func commit() {
        let toDelete = assets.filter { markedIDs.contains($0.localIdentifier) }
        guard !toDelete.isEmpty, !isCommitting else { return }
        isCommitting = true
        library.delete(toDelete) { [weak self] success, error in
            Task { @MainActor in
                guard let self else { return }
                self.isCommitting = false
                if success {
                    let count = toDelete.count
                    let deletedIDs = Set(toDelete.map { $0.localIdentifier })
                    self.assets.removeAll { deletedIDs.contains($0.localIdentifier) }
                    self.markedIDs = []
                    self.undoStack = []
                    self.isReviewingMarked = false
                    if self.index > self.assets.count { self.index = self.assets.count }
                    self.resultMessage = "已删除 \(count) 项,正在通过 iCloud 同步到 iPhone(进入「最近删除」,可在 30 天内恢复)。"
                    self.loadCurrent()
                    self.saveProgress()
                } else {
                    self.resultMessage = "未删除(已取消或出错):\(error?.localizedDescription ?? "用户取消")"
                }
            }
        }
    }

    // MARK: Image loading (exposed for the review-grid thumbnails)

    func loadThumbnail(for asset: PHAsset, size: CGSize, completion: @escaping (NSImage?) -> Void) {
        library.requestThumbnail(for: asset, targetSize: size, completion: completion)
    }

    // MARK: Progress persistence (one position per source, survives app relaunch)

    private var progressKey: String { "cullProgress-\(source.rawValue)" }

    /// Remember where the user is so the next launch resumes here. Saves the current
    /// asset's id (exact match) plus its date (fallback for when that asset has been
    /// deleted by the time we come back — the deck is newest-first, so we resume at the
    /// first asset no newer than it).
    private func saveProgress() {
        if let asset = currentAsset {
            UserDefaults.standard.set(
                ["id": asset.localIdentifier,
                 "date": asset.creationDate?.timeIntervalSince1970 ?? 0],
                forKey: progressKey
            )
        } else if isFinished {
            UserDefaults.standard.removeObject(forKey: progressKey)
        }
    }

    private func restoreProgress() {
        guard let saved = UserDefaults.standard.dictionary(forKey: progressKey) else { return }
        if let id = saved["id"] as? String,
           let savedIndex = assets.firstIndex(where: { $0.localIdentifier == id }) {
            index = savedIndex
        } else if let time = saved["date"] as? TimeInterval, time > 0,
                  let savedIndex = assets.firstIndex(where: {
                      ($0.creationDate?.timeIntervalSince1970 ?? 0) <= time
                  }) {
            index = savedIndex
        }
    }

    // MARK: Private helpers

    private func pushUndo(_ asset: PHAsset) {
        undoStack.append(UndoAction(
            index: index,
            assetID: asset.localIdentifier,
            wasMarked: markedIDs.contains(asset.localIdentifier)
        ))
    }

    private func advance() {
        index += 1
        if index < assets.count {
            loadCurrent()
            prefetch()
        } else {
            currentImage = nil   // reached the end of the deck
        }
        saveProgress()
    }

    /// Clears the shown image and requests the current asset's image. Clearing first is a
    /// correctness guard: we must never show the *previous* photo while the user is judging
    /// the current one. The guard on `localIdentifier` drops any stale (late) image result.
    private func loadCurrent() {
        currentImage = nil
        guard let asset = currentAsset else { return }
        let targetID = asset.localIdentifier
        library.requestImage(for: asset) { [weak self] image in
            Task { @MainActor in
                guard let self,
                      self.currentAsset?.localIdentifier == targetID else { return }
                self.currentImage = image
            }
        }
    }

    private func prefetch() {
        let start = min(index + 1, assets.count)
        let end = min(index + 6, assets.count)
        guard start < end else { return }
        library.startCaching(Array(assets[start..<end]))
    }
}
