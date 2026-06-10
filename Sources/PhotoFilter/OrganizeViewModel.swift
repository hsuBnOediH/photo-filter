import SwiftUI
import Photos
import Vision

/// Drives the organize module: scans the library for groups of similar photos
/// (time+location buckets refined by Vision feature prints), recommends one keeper per
/// group, and tracks the user's keep/delete decisions. Fully self-contained — own auth,
/// own marks, own commit — so it can never destabilize the screenshot module. Like the
/// flashcard flow, no PhotoKit *writes* happen until `commit()`.
@MainActor
final class OrganizeViewModel: ObservableObject {
    enum ScanPhase: Equatable {
        case idle
        case fetching
        case analyzing(done: Int, total: Int)
        case done
        case cancelled
    }

    @Published var authStatus: PHAuthorizationStatus = .notDetermined
    @Published private(set) var phase: ScanPhase = .idle
    @Published private(set) var groups: [PhotoGroup] = []
    @Published var timeWindow: TimeWindow {
        didSet { UserDefaults.standard.set(timeWindow.rawValue, forKey: "organize.timeWindow") }
    }
    @Published var similarity: SimilarityLevel {
        didSet { UserDefaults.standard.set(similarity.rawValue, forKey: "organize.similarity") }
    }
    @Published private(set) var markedIDs: Set<String> = []
    @Published private(set) var selectedGroup = 0
    @Published private(set) var selectedPhoto = 0
    @Published var isZoomed = false {
        didSet { if !isZoomed { isPixelZoomed = false } }
    }
    /// Actual-pixels pan inside the zoom overlay (toggled by the pixelZoom shortcut or
    /// clicking the image). Survives cursor moves so a whole group can be flipped
    /// through at full magnification; resets when the overlay closes.
    @Published var isPixelZoomed = false
    /// Side-by-side compare of the cursor photo vs the group's keeper. Mutually
    /// exclusive with the zoom overlay.
    @Published var isComparing = false
    /// Summary of a persisted session found on disk, shown on the idle screen.
    @Published private(set) var pendingSession: ScanSession?
    /// Session-cumulative delete counter, appended to result messages.
    @Published private(set) var deletedThisSession = 0
    /// Groups the user finished with Enter. Their marked photos are what the
    /// "删除已审待删" button deletes — unreviewed groups are never touched, so the user
    /// can stop anytime and resume with the next unreviewed group later.
    @Published private(set) var reviewedGroupIDs: Set<String> = []
    /// True once Enter is pressed on the last known group ("这轮看完了" state).
    @Published var queueFinished = false
    @Published private(set) var isCommitting = false
    @Published var resultMessage: String?
    /// Photos the scan had to skip: no creationDate (can't bucket) or thumbnail/Vision failure.
    @Published private(set) var skippedCount = 0
    /// Settings as of the last scan — drives the "设置已更改,重新扫描后生效" hint.
    @Published private(set) var appliedTimeWindow: TimeWindow?
    @Published private(set) var appliedSimilarity: SimilarityLevel?

    private let library = PhotoLibrary()
    private let engine = SimilarityEngine()
    /// In-memory thumbnails keyed by asset id — without this, re-showing a photo
    /// re-requests PhotoKit and the review feels sluggish. NSCache is thread-safe and
    /// evicts under memory pressure on its own.
    private let thumbCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 300
        return cache
    }()
    /// Thumbnail pixel size for the single-group review (240pt @2x) — prefetch uses the
    /// same size so PHCachingImageManager hits are exact.
    static let thumbPixelSize = CGSize(width: 480, height: 480)
    /// 4-wide: PHImageManager sync fetches + Vision both saturate quickly; more workers
    /// just makes the machine (and the UI) sluggish.
    private let scanQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 4
        queue.qualityOfService = .userInitiated
        return queue
    }()
    /// Bumped on every scan/cancel so completions from a superseded scan are ignored.
    private var scanGeneration = 0
    private var currentCancelFlag: CancelFlag?
    /// Debounces session saves — every toggle would otherwise hit the disk.
    private var sessionSaveTimer: Timer?

    init() {
        timeWindow = TimeWindow(rawValue: UserDefaults.standard.integer(forKey: "organize.timeWindow")) ?? .fiveMinutes
        similarity = SimilarityLevel(rawValue: UserDefaults.standard.string(forKey: "organize.similarity") ?? "") ?? .standard
        pendingSession = ScanSessionStore.load()
    }

    /// Thread-safe cancellation signal polled by worker operations between assets —
    /// the operations can't read the main-actor `scanGeneration` themselves.
    /// @unchecked: the only state is a bool guarded by the lock.
    private final class CancelFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        var isCancelled: Bool {
            lock.lock(); defer { lock.unlock() }
            return cancelled
        }
        func cancel() {
            lock.lock(); cancelled = true; lock.unlock()
        }
    }

    // MARK: Derived state

    var isScanning: Bool {
        switch phase {
        case .fetching, .analyzing: return true
        default: return false
        }
    }

    var markedCount: Int { markedIDs.count }

    /// Marked photos in reviewed groups plus the group currently on screen — exactly
    /// what the "删除已审待删" button will delete.
    var reviewedMarkedCount: Int {
        reviewedMarkedAssets.count
    }

    private var reviewedMarkedAssets: [PHAsset] {
        var ids = reviewedGroupIDs
        if let current = currentGroup { ids.insert(current.id) }
        return groups.filter { ids.contains($0.id) }
            .flatMap(\.assets)
            .filter { markedIDs.contains($0.localIdentifier) }
    }

    var settingsChangedSinceScan: Bool {
        // Once any scan has captured its settings, flag a mismatch in every phase —
        // including mid-scan, where the running scan keeps its snapshotted values.
        guard appliedTimeWindow != nil else { return false }
        return appliedTimeWindow != timeWindow || appliedSimilarity != similarity
    }

    var currentGroup: PhotoGroup? {
        groups.indices.contains(selectedGroup) ? groups[selectedGroup] : nil
    }

    var selectedAsset: PHAsset? {
        guard let group = currentGroup, group.assets.indices.contains(selectedPhoto) else { return nil }
        return group.assets[selectedPhoto]
    }

    func isMarked(_ asset: PHAsset) -> Bool {
        markedIDs.contains(asset.localIdentifier)
    }

    /// Left pane of the compare overlay: the group's keeper — or, when the cursor IS
    /// the keeper, the nearest other unmarked photo (nil → nothing to compare against).
    var compareReference: PHAsset? {
        guard let group = currentGroup, let selected = selectedAsset else { return nil }
        if selected.localIdentifier != group.recommendedID {
            return group.assets.first { $0.localIdentifier == group.recommendedID }
        }
        let others = group.assets.enumerated().filter {
            $0.element.localIdentifier != selected.localIdentifier && !isMarked($0.element)
        }
        return others.min { abs($0.offset - selectedPhoto) < abs($1.offset - selectedPhoto) }?.element
    }

    // MARK: Lifecycle

    func requestAccess() {
        library.requestAuthorization { [weak self] status in
            Task { @MainActor in
                self?.authStatus = status
            }
        }
    }

    // MARK: Session persistence

    /// Restores the on-disk session: groups rebuilt against the live library, review
    /// progress and marks intersected with what still exists.
    func resumeSession() {
        guard let session = pendingSession else { return }
        let rebuilt = ScanSessionStore.rebuildGroups(from: session)
        pendingSession = nil
        guard !rebuilt.isEmpty else {
            ScanSessionStore.clear()
            return
        }
        groups = rebuilt
        let validIDs = Set(rebuilt.flatMap(\.assets).map(\.localIdentifier))
        markedIDs = Set(session.markedIDs).intersection(validIDs)
        reviewedGroupIDs = Set(session.reviewedGroupIDs).intersection(Set(rebuilt.map(\.id)))
        timeWindow = TimeWindow(rawValue: session.timeWindow) ?? timeWindow
        similarity = SimilarityLevel(rawValue: session.similarity) ?? similarity
        appliedTimeWindow = timeWindow
        appliedSimilarity = similarity
        selectedGroup = min(session.cursorGroup, groups.count - 1)
        selectedPhoto = min(session.cursorPhoto, max((currentGroup?.assets.count ?? 1) - 1, 0))
        queueFinished = false
        phase = .done
        library.startCachingThumbnails(
            for: Array(groups.flatMap(\.assets).prefix(200)),
            targetSize: Self.thumbPixelSize
        )
    }

    /// Debounced (0.5 s) so rapid toggling doesn't hammer the disk; `immediately`
    /// forces a write (used after deletes and scan completion).
    private func scheduleSessionSave(immediately: Bool = false) {
        sessionSaveTimer?.invalidate()
        if immediately {
            saveSessionNow()
        } else {
            sessionSaveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in self?.saveSessionNow() }
            }
        }
    }

    private func saveSessionNow() {
        guard !groups.isEmpty else {
            ScanSessionStore.clear()
            return
        }
        ScanSessionStore.save(ScanSession(
            engineRevision: SimilarityEngine.revision,
            savedAt: Date(),
            timeWindow: appliedTimeWindow?.rawValue ?? timeWindow.rawValue,
            similarity: (appliedSimilarity ?? similarity).rawValue,
            groups: groups.map { ScanSession.Group(recommendedID: $0.id, assetIDs: $0.assets.map(\.localIdentifier)) },
            reviewedGroupIDs: Array(reviewedGroupIDs),
            markedIDs: Array(markedIDs),
            cursorGroup: selectedGroup,
            cursorPhoto: selectedPhoto
        ))
    }

    // MARK: Scan pipeline

    func startScan() {
        guard !isScanning, !isCommitting else { return }
        // A new scan supersedes any stored session.
        pendingSession = nil
        ScanSessionStore.clear()
        scanGeneration += 1
        let generation = scanGeneration
        let flag = CancelFlag()
        currentCancelFlag = flag
        // Capture everything the background work needs up front — worker code below
        // never touches main-actor state directly, only hops back via Task { @MainActor }.
        let window = TimeInterval(timeWindow.rawValue)
        let threshold = similarity.threshold
        let library = self.library
        let engine = self.engine
        let queue = self.scanQueue

        groups = []
        markedIDs = []
        reviewedGroupIDs = []
        queueFinished = false
        selectedGroup = 0
        selectedPhoto = 0
        skippedCount = 0
        resultMessage = nil
        isZoomed = false
        appliedTimeWindow = timeWindow
        appliedSimilarity = similarity
        library.resetCache()
        phase = .fetching

        // Workers capture `self` STRONGLY on purpose: a @MainActor class is Sendable, so
        // strong (immutable) captures compile clean on every toolchain, while `[weak
        // self]` bindings are mutable captures that older compilers reject inside
        // @Sendable closures. No leak: the VM outlives scans anyway (owned by RootView)
        // and operations release their captures on completion/cancellation.
        let progress = Tally()
        DispatchQueue.global(qos: .userInitiated).async {
            let assets = library.fetchPersonalImages()
            let (allBuckets, skippedNoDate) = AssetGrouper.bucket(assets, window: window)
            // Only multi-photo buckets ever reach Vision — scattered single shots cost
            // zero CV work, which is the bulk of a typical library. Newest buckets are
            // processed first so the most recent groups stream in right away.
            let buckets = allBuckets.filter { $0.count >= 2 }.sorted {
                ($0.last?.creationDate ?? .distantPast) > ($1.last?.creationDate ?? .distantPast)
            }
            let total = buckets.reduce(0) { $0 + $1.count }

            Task { @MainActor in
                guard self.scanGeneration == generation else { return }
                self.skippedCount += skippedNoDate
                self.phase = .analyzing(done: 0, total: total)
            }
            guard !flag.isCancelled else { return }

            // STREAMING: one operation per bucket — each computes its own prints,
            // clusters immediately, and publishes any found groups right away, so the
            // user can review and delete groups while the rest of the library is still
            // being analyzed.
            for bucket in buckets {
                queue.addOperation {
                    if flag.isCancelled { return }
                    var prints: [String: VNFeaturePrintObservation] = [:]
                    var failed = 0
                    for asset in bucket {
                        if flag.isCancelled { return }
                        if let observation = engine.featurePrint(for: asset, library: library) {
                            prints[asset.localIdentifier] = observation
                        } else {
                            failed += 1
                        }
                        let reported = progress.increment()
                        // Throttle progress: one @Published update per asset would
                        // hammer SwiftUI tens of thousands of times.
                        if reported % 25 == 0 || reported == total {
                            Task { @MainActor in
                                guard self.scanGeneration == generation else { return }
                                self.phase = .analyzing(done: reported, total: total)
                            }
                        }
                    }
                    let clusters = AssetGrouper.cluster(
                        bucket: bucket, prints: prints, threshold: threshold, engine: engine
                    )
                    let newGroups = clusters.map { cluster -> PhotoGroup in
                        let keeper = AssetGrouper.recommendKeeper(in: cluster)
                        return PhotoGroup(
                            id: keeper.localIdentifier,
                            assets: cluster,
                            recommendedID: keeper.localIdentifier
                        )
                    }
                    guard !newGroups.isEmpty || failed > 0 else { return }
                    let finalFailed = failed  // immutable copy crosses into the Task
                    Task { @MainActor in
                        guard self.scanGeneration == generation else { return }
                        self.skippedCount += finalFailed
                        if !newGroups.isEmpty { self.appendGroups(newGroups) }
                    }
                }
            }

            queue.addBarrierBlock {
                guard !flag.isCancelled else { return }
                Task { @MainActor in
                    guard self.scanGeneration == generation else { return }
                    self.phase = .done
                    self.scheduleSessionSave(immediately: true)
                }
            }
        }
    }

    /// Lock-guarded counter shared by worker operations — mutable locals can't cross
    /// @Sendable closure boundaries. @unchecked: single Int behind the lock.
    private final class Tally: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func increment() -> Int {
            lock.lock(); defer { lock.unlock() }
            value += 1
            return value
        }
    }

    /// Merge freshly-found groups into the published list (keeping newest-first order),
    /// pre-mark their non-keepers, and warm their thumbnails. Runs on the main actor as
    /// buckets finish, so results stream in while the scan continues.
    private func appendGroups(_ newGroups: [PhotoGroup]) {
        for group in newGroups {
            for asset in group.assets where asset.localIdentifier != group.recommendedID {
                markedIDs.insert(asset.localIdentifier)
            }
        }
        let selectedID = currentGroup?.id
        groups.append(contentsOf: newGroups)
        groups.sort {
            ($0.assets.last?.creationDate ?? .distantPast) > ($1.assets.last?.creationDate ?? .distantPast)
        }
        // Inserts above the cursor shift indices — keep the cursor on the same group.
        if let selectedID, let index = groups.firstIndex(where: { $0.id == selectedID }) {
            selectedGroup = index
        }
        // If the user had caught up with the queue, the fresh groups reopen it.
        queueFinished = false
        library.startCachingThumbnails(for: newGroups.flatMap(\.assets), targetSize: Self.thumbPixelSize)
        scheduleSessionSave()
    }

    /// Stops the scan but KEEPS every group found so far — the user can process those
    /// immediately. Prints computed so far are in the on-disk cache, so the next scan
    /// resumes nearly where this one stopped.
    func cancelScan() {
        guard isScanning else { return }
        currentCancelFlag?.cancel()
        scanQueue.cancelAllOperations()
        scanGeneration += 1
        if groups.isEmpty {
            phase = .cancelled
        } else {
            phase = .done
            resultMessage = L("organize.result.stopped")
            scheduleSessionSave(immediately: true)
        }
    }

    // MARK: Keep/delete decisions (in-memory only, like the flashcard module)

    /// Restore one group to its recommended state (keep the suggestion, drop the rest).
    func resetToRecommendation(_ group: PhotoGroup) {
        for asset in group.assets {
            if asset.localIdentifier == group.recommendedID {
                markedIDs.remove(asset.localIdentifier)
            } else {
                markedIDs.insert(asset.localIdentifier)
            }
        }
        scheduleSessionSave()
    }

    func toggle(_ asset: PHAsset) {
        if markedIDs.contains(asset.localIdentifier) {
            markedIDs.remove(asset.localIdentifier)
        } else {
            markedIDs.insert(asset.localIdentifier)
        }
        scheduleSessionSave()
    }

    func toggleSelected() {
        guard let asset = selectedAsset else { return }
        toggle(asset)
    }

    /// Keep only the cursor photo: everything else in its group gets marked.
    func keepOnlySelected() {
        guard let group = currentGroup, let selected = selectedAsset else { return }
        for asset in group.assets {
            if asset.localIdentifier == selected.localIdentifier {
                markedIDs.remove(asset.localIdentifier)
            } else {
                markedIDs.insert(asset.localIdentifier)
            }
        }
        scheduleSessionSave()
    }

    // MARK: Selection cursor

    func select(groupIndex: Int, photoIndex: Int) {
        guard groups.indices.contains(groupIndex),
              groups[groupIndex].assets.indices.contains(photoIndex) else { return }
        selectedGroup = groupIndex
        selectedPhoto = photoIndex
    }

    func selectNextGroup() {
        guard !groups.isEmpty else { return }
        selectedGroup = min(selectedGroup + 1, groups.count - 1)
        selectedPhoto = 0
    }

    func selectPreviousGroup() {
        guard !groups.isEmpty else { return }
        selectedGroup = max(selectedGroup - 1, 0)
        selectedPhoto = 0
    }

    func selectNextPhoto() {
        guard let group = currentGroup else { return }
        selectedPhoto = min(selectedPhoto + 1, group.assets.count - 1)
    }

    func selectPreviousPhoto() {
        guard currentGroup != nil else { return }
        selectedPhoto = max(selectedPhoto - 1, 0)
    }

    // MARK: Single-group review queue

    /// Enter — the user is done deciding this group; move to the next one.
    func finishCurrentGroup() {
        guard let group = currentGroup else { return }
        reviewedGroupIDs.insert(group.id)
        if selectedGroup < groups.count - 1 {
            selectedGroup += 1
            selectedPhoto = 0
        } else {
            queueFinished = true
        }
        scheduleSessionSave()
    }

    /// "删除已审待删" — deletes the marked photos of every reviewed group (the one on
    /// screen counts as reviewed), then drops those groups from the queue entirely, so
    /// the session resumes at the first unreviewed group. Pre-marks in unreviewed
    /// groups are NEVER deleted by this.
    func deleteReviewed() {
        if let current = currentGroup { reviewedGroupIDs.insert(current.id) }
        let toDelete = reviewedMarkedAssets
        if toDelete.isEmpty {
            removeReviewedGroups()
            resultMessage = L("organize.result.reviewedEmpty")
        } else {
            performDelete(toDelete, thenRemoveReviewed: true)
        }
    }

    /// Immediate partial cleanup: delete just this group's marked photos right now.
    func commitGroup(_ group: PhotoGroup) {
        performDelete(group.assets.filter { markedIDs.contains($0.localIdentifier) })
    }

    /// `thenRemoveReviewed` is only set by deleteReviewed() — a per-group delete must
    /// not silently drop OTHER reviewed groups whose marks haven't been deleted yet.
    private func performDelete(_ toDelete: [PHAsset], thenRemoveReviewed: Bool = false) {
        guard !toDelete.isEmpty, !isCommitting else { return }
        isCommitting = true
        library.delete(toDelete) { [weak self] success, error in
            Task { @MainActor in
                guard let self else { return }
                self.isCommitting = false
                if success {
                    let deletedIDs = Set(toDelete.map(\.localIdentifier))
                    self.pruneDeleted(deletedIDs)
                    self.markedIDs.subtract(deletedIDs)
                    if thenRemoveReviewed { self.removeReviewedGroups() }
                    self.deletedThisSession += toDelete.count
                    self.resultMessage = L("result.deleted", toDelete.count)
                        + " " + L("result.sessionTotal", self.deletedThisSession)
                    self.scheduleSessionSave(immediately: true)
                } else {
                    self.resultMessage = L("result.failed", error?.localizedDescription ?? L("result.userCancelled"))
                }
            }
        }
    }

    /// Reviewed groups leave the queue once their deletions are done — what the user
    /// kept stays in the library, the group just stops appearing. Resume = index 0,
    /// which is now the first unreviewed group.
    private func removeReviewedGroups() {
        guard !reviewedGroupIDs.isEmpty else { return }
        let leftoverMarks = groups.filter { reviewedGroupIDs.contains($0.id) }
            .flatMap(\.assets).map(\.localIdentifier)
        markedIDs.subtract(leftoverMarks)
        groups.removeAll { reviewedGroupIDs.contains($0.id) }
        reviewedGroupIDs = []
        selectedGroup = 0
        selectedPhoto = 0
        if !groups.isEmpty { queueFinished = false }
    }

    /// Drop deleted assets from all groups; a group below 2 members has nothing left to
    /// compare against, so it disappears entirely.
    private func pruneDeleted(_ ids: Set<String>) {
        for index in groups.indices {
            groups[index].assets.removeAll { ids.contains($0.localIdentifier) }
        }
        groups.removeAll { $0.assets.count < 2 }
        selectedGroup = min(selectedGroup, max(groups.count - 1, 0))
        selectedPhoto = min(selectedPhoto, max((currentGroup?.assets.count ?? 1) - 1, 0))
    }

    // MARK: Image loading (exposed for thumbnails and the zoom overlay)

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
            // .opportunistic may deliver twice (fast low-res, then sharp) — keep the latest.
            if let image {
                cache.setObject(image, forKey: asset.localIdentifier as NSString)
            }
            completion(image)
        }
    }

    func loadImage(for asset: PHAsset, completion: @escaping (NSImage?) -> Void) {
        library.requestImage(for: asset, completion: completion)
    }
}
