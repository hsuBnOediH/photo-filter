import SwiftUI
import Photos

/// The organize module, built around ONE group on screen at a time: decide keep/delete
/// inside the group, press Enter to move to the next, and at any point hit
/// "删除已审待删" to delete the rejects of everything reviewed so far — unreviewed
/// groups are untouched, so a later session resumes right where this one stopped.
///
/// Keyboard model differs from the flashcard module on purpose: arrows NAVIGATE and the
/// destructive toggle gets its own key (⌫), so flashcard muscle memory (← = delete)
/// can't accidentally mark photos here.
struct OrganizeView: View {
    @ObservedObject var vm: OrganizeViewModel
    var onHome: () -> Void
    @ObservedObject private var shortcuts = ShortcutManager.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
            if vm.isComparing, let reference = vm.compareReference, let selected = vm.selectedAsset {
                // .id() rebuilds the overlay when arrows move the cursor, so the right
                // pane follows the selection.
                CompareOverlay(vm: vm, reference: reference, selected: selected)
                    .id(selected.localIdentifier + reference.localIdentifier)
            } else if vm.isZoomed, let asset = vm.selectedAsset {
                ZoomOverlay(vm: vm, asset: asset)
                    .id(asset.localIdentifier)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .background(RawKeyCatcher(onKeyDown: handleKey))
        .onAppear { vm.requestAccess() }
        // Reaching the end of the queue while zoomed/comparing: surface the queue-done
        // screen instead of a dangling overlay.
        .onChange(of: vm.queueFinished) { _, finished in
            if finished {
                vm.isZoomed = false
                vm.isComparing = false
            }
        }
    }

    // MARK: Keyboard

    /// Esc is reserved and backs out one layer at a time (compare → zoom → home);
    /// everything else resolves through the user's ShortcutManager bindings — including
    /// inside the zoom/compare overlays, which is what makes fully-zoomed triage work.
    private func handleKey(_ event: NSEvent) -> Bool {
        // While the cheat sheet is up it owns the keyboard: Esc/? close it,
        // everything else is swallowed so review state can't change underneath it.
        if AppState.shared.showCheatSheet {
            if event.keyCode == 53
                || shortcuts.action(for: event, among: ShortcutAction.organizeScope) == .showCheatSheet {
                AppState.shared.showCheatSheet = false
            }
            return true
        }
        if event.keyCode == 53 {  // Esc
            if vm.isComparing {
                vm.isComparing = false
            } else if vm.isZoomed {
                vm.isZoomed = false
            } else {
                onHome()
            }
            return true
        }
        // Groups stream in while the scan runs — keys work as soon as any exist.
        guard !vm.groups.isEmpty else { return false }
        guard let action = shortcuts.action(for: event, among: ShortcutAction.organizeScope) else { return false }
        if vm.queueFinished {
            // Only "step back into the queue" applies on the done screen.
            if action == .prevGroup {
                vm.queueFinished = false
                return true
            }
            return false
        }
        switch action {
        case .prevGroup: vm.selectPreviousGroup()
        case .nextGroup: vm.selectNextGroup()
        case .prevPhoto: vm.selectPreviousPhoto()
        case .nextPhoto: vm.selectNextPhoto()
        case .toggleMark: vm.toggleSelected()
        case .keepOnly: vm.keepOnlySelected()
        case .finishGroup: vm.finishCurrentGroup()  // overlays stay open → zoomed triage
        case .zoom:
            vm.isComparing = false
            vm.isZoomed.toggle()
        case .compare:
            guard vm.compareReference != nil else { return true }
            vm.isZoomed = false
            vm.isComparing.toggle()
        case .pixelZoom:
            if vm.isZoomed { vm.isPixelZoomed.toggle() }
        case .showCheatSheet:
            AppState.shared.showCheatSheet = true
        default: return false
        }
        return true
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch vm.authStatus {
        case .notDetermined:
            ProgressView(L("common.requestingAccess"))
                .tint(.white)
                .foregroundStyle(.white)
        case .denied, .restricted:
            deniedView
        case .authorized, .limited:
            VStack(spacing: 0) {
                header
                if vm.authStatus == .limited { limitedBanner }
                if vm.settingsChangedSinceScan { settingsChangedHint }
                mainArea
                footer
            }
        @unknown default:
            Text(L("common.unknownAuth")).foregroundStyle(.white)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(L("common.backHome")) { onHome() }
            Button(vm.phase == .idle ? L("organize.scan.start") : L("organize.scan.again")) { vm.startScan() }
                .disabled(vm.isScanning || vm.isCommitting)
            // Settings stay clickable during a scan — startScan() snapshots its values,
            // so mid-scan changes only affect the NEXT scan (the hint says as much).
            Text(L("organize.setting.timeWindow"))
                .font(.footnote)
                .foregroundStyle(.gray)
            Picker("", selection: Binding(get: { vm.timeWindow }, set: { vm.timeWindow = $0 })) {
                ForEach(TimeWindow.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            Text(L("organize.setting.similarity"))
                .font(.footnote)
                .foregroundStyle(.gray)
            Picker("", selection: Binding(get: { vm.similarity }, set: { vm.similarity = $0 })) {
                ForEach(SimilarityLevel.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            Spacer()
            if !vm.groups.isEmpty {
                Text(L("organize.header.progress",
                       min(vm.selectedGroup + 1, vm.groups.count), vm.groups.count, vm.reviewedGroupIDs.count))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            Button(vm.isCommitting ? L("review.deleting") : L("organize.header.deleteReviewed", vm.reviewedMarkedCount)) {
                vm.deleteReviewed()
            }
            .buttonStyle(.borderedProminent)
            .disabled((vm.reviewedMarkedCount == 0 && vm.reviewedGroupIDs.isEmpty)
                      || vm.isCommitting || vm.groups.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.black)
    }

    private var limitedBanner: some View {
        Text(L("organize.limitedBanner"))
            .font(.footnote)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(.orange.opacity(0.12))
    }

    private var settingsChangedHint: some View {
        Text(L("organize.settingsChanged"))
            .font(.footnote)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
    }

    @ViewBuilder
    private var mainArea: some View {
        switch vm.phase {
        case .idle:
            idleView
        case .fetching:
            scanStatus(L("organize.phase.fetching"), progress: nil)
        case .analyzing(let done, let total):
            // Results stream in while the scan runs: once any group exists, the review
            // takes over and the progress collapses into a slim banner.
            if vm.groups.isEmpty {
                scanStatus(L("organize.phase.analyzing", done, total),
                           progress: total > 0 ? Double(done) / Double(total) : nil)
            } else {
                VStack(spacing: 0) {
                    scanBanner(done: done, total: total)
                    reviewArea
                }
            }
        case .cancelled:
            VStack(spacing: 12) {
                Text(L("organize.cancelled.message"))
                    .foregroundStyle(.white)
                Button(L("organize.scan.again")) { vm.startScan() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .done:
            if vm.groups.isEmpty {
                VStack(spacing: 12) {
                    Text(L("organize.empty.title"))
                        .font(.title3)
                        .foregroundStyle(.white)
                    Text(L("organize.empty.hint"))
                        .foregroundStyle(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                reviewArea
            }
        }
    }

    // MARK: Single-group review

    @ViewBuilder
    private var reviewArea: some View {
        if vm.queueFinished {
            queueFinishedView
        } else if let group = vm.currentGroup {
            VStack(spacing: 0) {
                Spacer(minLength: 8)
                GroupCard(group: group, groupIndex: vm.selectedGroup, thumbSide: 240, vm: vm)
                    .padding(.horizontal)
                Text(L("organize.review.enterHint"))
                    .font(.callout)
                    .foregroundStyle(.gray)
                    .padding(.top, 12)
                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var queueFinishedView: some View {
        VStack(spacing: 14) {
            Text(vm.isScanning ? L("organize.queueDone.scanning") : L("organize.queueDone.title"))
                .font(.title3)
                .foregroundStyle(.white)
            if vm.isScanning {
                Text(L("organize.queueDone.streamHint"))
                    .foregroundStyle(.gray)
            }
            Button(vm.isCommitting ? L("review.deleting") : L("organize.header.deleteReviewed", vm.reviewedMarkedCount)) {
                vm.deleteReviewed()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled((vm.reviewedMarkedCount == 0 && vm.reviewedGroupIDs.isEmpty) || vm.isCommitting)
            Button(L("organize.queueDone.back")) { vm.queueFinished = false }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var idleView: some View {
        VStack(spacing: 14) {
            Text(L("organize.idle.title"))
                .font(.title)
                .foregroundStyle(.white)
            Text(L("organize.idle.body"))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))
            Text(L("organize.idle.privacy"))
                .font(.footnote)
                .foregroundStyle(.gray)
            if let session = vm.pendingSession {
                // A saved session resumes instantly; a fresh scan is the secondary path.
                Button(L("organize.resume.button", session.groups.count, session.reviewedGroupIDs.count)) {
                    vm.resumeSession()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Text(L("organize.resume.savedAt", session.savedAt.formatted(date: .abbreviated, time: .shortened)))
                    .font(.footnote)
                    .foregroundStyle(.gray)
                Button(L("organize.scan.start")) { vm.startScan() }
            } else {
                Button(L("organize.scan.start")) { vm.startScan() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Slim in-list progress strip shown while the review is already usable.
    private func scanBanner(done: Int, total: Int) -> some View {
        HStack(spacing: 12) {
            ProgressView(value: total > 0 ? Double(done) / Double(total) : 0)
                .frame(width: 180)
            Text(L("organize.banner.analyzing", done, total))
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.gray)
            Spacer()
            Button(L("organize.banner.stop")) { vm.cancelScan() }
                .controlSize(.small)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.white.opacity(0.04))
    }

    private func scanStatus(_ label: String, progress: Double?) -> some View {
        VStack(spacing: 16) {
            if let progress {
                ProgressView(value: progress)
                    .frame(width: 360)
            } else {
                ProgressView().tint(.white)
            }
            Text(label)
                .monospacedDigit()
                .foregroundStyle(.white)
            Button(L("common.cancel")) { vm.cancelScan() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Built from live bindings so customized shortcuts show up here immediately.
    private var footerLegend: String {
        let combo = { (action: ShortcutAction) in shortcuts.combo(for: action).display }
        return [
            "\(combo(.prevPhoto))/\(combo(.nextPhoto))  \(L("legend.selectPhoto"))",
            "\(combo(.toggleMark))  \(L("legend.toggleMark"))",
            "\(combo(.keepOnly))  \(L("legend.keepOnly"))",
            "\(combo(.finishGroup))  \(L("legend.nextGroup"))",
            "\(combo(.prevGroup))/\(combo(.nextGroup))  \(L("legend.browseGroups"))",
            "\(combo(.compare))  \(L("legend.compare"))",
            "\(combo(.zoom))  \(L("legend.zoom"))",
            "Esc  \(L("legend.back"))",
        ].joined(separator: "      ")
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text(footerLegend)
                .font(.callout)
                .foregroundStyle(.gray)
            if !vm.groups.isEmpty {
                Text(L("organize.footer.sharedWarning"))
                    .font(.footnote)
                    .foregroundStyle(.orange.opacity(0.85))
            }
            if vm.phase == .done && vm.skippedCount > 0 {
                Text(L("organize.footer.skipped", vm.skippedCount))
                    .font(.footnote)
                    .foregroundStyle(.gray)
            }
            if let message = vm.resultMessage {
                HStack(spacing: 10) {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.green)
                        .multilineTextAlignment(.center)
                    if vm.deletedThisSession > 0 {
                        Button(L("common.openPhotos")) {
                            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Photos.app"))
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }

    // MARK: Other states

    private var deniedView: some View {
        VStack(spacing: 16) {
            Text(L("denied.title")).font(.title2).foregroundStyle(.white)
            Text(L("denied.message"))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Button(L("denied.openSettings")) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding()
    }
}

// MARK: - Group card

private struct GroupCard: View {
    let group: PhotoGroup
    let groupIndex: Int
    var thumbSide: CGFloat = 160
    @ObservedObject var vm: OrganizeViewModel

    private var keptCount: Int {
        group.assets.filter { !vm.isMarked($0) }.count
    }

    private var dateRange: String {
        guard let first = group.assets.first?.creationDate else { return L("group.dateUnknown") }
        var text = first.formatted(date: .abbreviated, time: .shortened)
        if let last = group.assets.last?.creationDate, last != first {
            text += " – " + last.formatted(date: .omitted, time: .shortened)
        }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(dateRange)
                    .font(.callout)
                    .foregroundStyle(.white)
                Text(L("group.summary", group.assets.count, keptCount))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(keptCount == 0 ? .red : .gray)
                Spacer()
                Button(L("group.reset")) { vm.resetToRecommendation(group) }
                    .font(.callout)
                // Immediate partial cleanup: clears this group on the spot.
                Button(L("group.deleteNow", group.assets.count - keptCount)) { vm.commitGroup(group) }
                    .font(.callout)
                    .disabled(group.assets.count - keptCount == 0 || vm.isCommitting)
            }
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 10) {
                    ForEach(Array(group.assets.enumerated()), id: \.element.localIdentifier) { pair in
                        OrganizeThumb(
                            asset: pair.element,
                            isMarked: vm.isMarked(pair.element),
                            isRecommended: pair.element.localIdentifier == group.recommendedID,
                            isCursor: groupIndex == vm.selectedGroup && pair.offset == vm.selectedPhoto,
                            side: thumbSide,
                            cached: vm.cachedThumbnail(for: pair.element),
                            load: vm.loadThumbnail,
                            onTap: {
                                vm.select(groupIndex: groupIndex, photoIndex: pair.offset)
                                vm.toggle(pair.element)
                            }
                        )
                    }
                }
                .padding(4)
            }
        }
        .padding(14)
        .background(.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - One thumbnail in a group card

private struct OrganizeThumb: View {
    let asset: PHAsset
    let isMarked: Bool
    let isRecommended: Bool
    let isCursor: Bool
    var side: CGFloat = 160
    /// Pre-resolved cache hit — shown from the very first frame, so revisiting an
    /// already-seen photo never flashes gray.
    let cached: NSImage?
    let load: (PHAsset, CGSize, @escaping (NSImage?) -> Void) -> Void
    let onTap: () -> Void
    @State private var image: NSImage?

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Group {
                    if let shown = image ?? cached {
                        Image(nsImage: shown).resizable().scaledToFill()
                    } else {
                        Color.gray.opacity(0.25)
                    }
                }
                .frame(width: side, height: side)
                .clipped()
                .opacity(isMarked ? 0.45 : 1)
            }
            .overlay(alignment: .topTrailing) {
                Text(isMarked ? L("thumb.marked") : L("thumb.kept"))
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(isMarked ? .red : .green)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .padding(5)
            }
            .overlay(alignment: .topLeading) {
                if isRecommended {
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.yellow)
                        .shadow(radius: 2)
                        .padding(5)
                        .help(L("thumb.recommended.help"))
                }
            }
            .overlay(alignment: .bottomLeading) {
                if asset.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .padding(5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isCursor ? .white : (isMarked ? .red.opacity(0.8) : .clear),
                            lineWidth: isCursor ? 3 : 2)
            )
        }
        .buttonStyle(.plain)
        .help(L("thumb.toggle.help"))
        .onAppear {
            guard image == nil else { return }
            load(asset, OrganizeViewModel.thumbPixelSize) { img in
                Task { @MainActor in self.image = img }
            }
        }
    }
}

// MARK: - Full-window zoom of the cursor photo

/// All review keys keep working while this is open (the key catcher sits below every
/// overlay), so an entire group — or the whole queue via Enter — can be triaged without
/// ever leaving the zoom.
private struct ZoomOverlay: View {
    @ObservedObject var vm: OrganizeViewModel
    let asset: PHAsset
    @State private var image: NSImage?

    private var statusCapsule: some View {
        HStack(spacing: 8) {
            if asset.localIdentifier == vm.currentGroup?.recommendedID {
                Image(systemName: "star.circle.fill").foregroundStyle(.yellow)
            }
            Text(vm.isMarked(asset) ? L("thumb.marked") : L("thumb.kept"))
                .font(.callout.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(vm.isMarked(asset) ? .red : .green)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            Text("\(vm.selectedPhoto + 1) / \(vm.currentGroup?.assets.count ?? 0)")
                .monospacedDigit()
                .foregroundStyle(.white)
        }
    }

    private var hintBar: String {
        let shortcuts = ShortcutManager.shared
        let combo = { (action: ShortcutAction) in shortcuts.combo(for: action).display }
        return [
            "\(combo(.toggleMark))  \(L("legend.toggleMark"))",
            "\(combo(.keepOnly))  \(L("legend.keepOnly"))",
            "\(combo(.finishGroup))  \(L("legend.nextGroup"))",
            "\(combo(.pixelZoom))  \(L("legend.pixelZoom"))",
            "Esc  \(L("legend.back"))",
        ].joined(separator: "      ")
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.96).ignoresSafeArea()
            GeometryReader { geo in
                Group {
                    if let image {
                        if vm.isPixelZoomed {
                            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                                Image(nsImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: geo.size.width * 2.5, height: geo.size.height * 2.5)
                            }
                        } else {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .padding(24)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else {
                        ProgressView().tint(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { vm.isPixelZoomed.toggle() }
            }
            VStack {
                HStack {
                    Spacer()
                    statusCapsule.padding()
                }
                Spacer()
                Text(hintBar)
                    .font(.callout)
                    .foregroundStyle(.gray)
                    .padding(.bottom, 10)
            }
        }
        .onAppear {
            // .opportunistic delivery may call back twice (fast low-res, then sharp);
            // each call just replaces what's shown.
            vm.loadImage(for: asset) { img in
                Task { @MainActor in self.image = img }
            }
        }
    }
}

// MARK: - Side-by-side compare (cursor photo vs the group's keeper)

private struct CompareOverlay: View {
    @ObservedObject var vm: OrganizeViewModel
    let reference: PHAsset
    let selected: PHAsset

    var body: some View {
        ZStack {
            Color.black.opacity(0.96).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 2) {
                    ComparePane(vm: vm, asset: reference, titleKey: "compare.reference")
                    ComparePane(vm: vm, asset: selected, titleKey: "compare.selection")
                }
                Text("\(ShortcutManager.shared.combo(for: .compare).display) / Esc  \(L("legend.back"))")
                    .font(.callout)
                    .foregroundStyle(.gray)
                    .padding(.vertical, 8)
            }
        }
    }
}

private struct ComparePane: View {
    @ObservedObject var vm: OrganizeViewModel
    let asset: PHAsset
    let titleKey: String
    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                if asset.localIdentifier == vm.currentGroup?.recommendedID {
                    Image(systemName: "star.circle.fill").foregroundStyle(.yellow)
                }
                Text(L(titleKey))
                    .foregroundStyle(.white)
                Text(vm.isMarked(asset) ? L("thumb.marked") : L("thumb.kept"))
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(vm.isMarked(asset) ? .red : .green)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .padding(.top, 12)
            Group {
                if let image {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(10)
        }
        .onAppear {
            vm.loadImage(for: asset) { img in
                Task { @MainActor in self.image = img }
            }
        }
    }
}
