import SwiftUI
import Photos

struct CullView: View {
    @ObservedObject var vm: CullViewModel
    /// Optional route back to the module home screen — Esc triggers it when the review
    /// grid isn't open. Optional (default nil) so the view also works standalone.
    var onHome: (() -> Void)? = nil
    @State private var isZoomed = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
        }
        .frame(minWidth: 700, minHeight: 500)
        // KeyCatcher sits behind everything, full-window, and owns keyboard input.
        .background(
            KeyCatcher(
                enabled: !vm.isReviewingMarked,
                onLeft: { vm.markDelete() },
                onRight: { vm.keep() },
                onUndo: { vm.undo() },
                onZoom: { isZoomed.toggle() },
                onEscape: {
                    if vm.isReviewingMarked {
                        vm.isReviewingMarked = false
                    } else {
                        onHome?()
                    }
                }
            )
        )
        .onChange(of: vm.index) { _, _ in isZoomed = false }
        .onChange(of: vm.isReviewingMarked) { _, _ in isZoomed = false }
        .onAppear { vm.requestAccess() }
    }

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
            if vm.assets.isEmpty {
                emptyView
            } else if vm.isReviewingMarked {
                reviewGrid
            } else if vm.isFinished {
                finishedView
            } else {
                cullingView
            }
        @unknown default:
            Text(L("common.unknownAuth")).foregroundStyle(.white)
        }
    }

    // MARK: Culling

    private var cullingView: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { geo in
                ZStack {
                    imageArea(geo: geo)
                    if let asset = vm.currentAsset {
                        if asset.mediaType == .video { playBadge }
                        if vm.currentIsMarked { markedBadge }
                        infoOverlay(asset)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            footer
        }
    }

    @ViewBuilder
    private func imageArea(geo: GeometryProxy) -> some View {
        if let image = vm.currentImage {
            if isZoomed {
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
                    .padding(20)
            }
        } else {
            ProgressView().tint(.white)
        }
    }

    private var markedBadge: some View {
        VStack {
            HStack {
                Spacer()
                Text(L("cull.marked.badge"))
                    .font(.headline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.red)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .padding()
            }
            Spacer()
        }
    }

    private var playBadge: some View {
        Image(systemName: "play.circle.fill")
            .font(.system(size: 56))
            .foregroundStyle(.white.opacity(0.85))
            .shadow(radius: 4)
    }

    private func infoOverlay(_ asset: PHAsset) -> some View {
        VStack {
            Spacer()
            HStack {
                HStack(spacing: 6) {
                    if asset.isFavorite {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                    }
                    Text(infoText(for: asset))
                }
                .font(.callout)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.black.opacity(0.5))
                .clipShape(Capsule())
                Spacer()
            }
            .padding()
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            sourcePicker
            Spacer()
            Text("\(min(vm.index + 1, vm.total)) / \(vm.total)")
                .monospacedDigit()
                .foregroundStyle(.white)
            Text(L("common.markedCount", vm.markedCount))
                .monospacedDigit()
                .foregroundStyle(vm.markedCount > 0 ? .red : .gray)
            Button(L("cull.header.review")) { vm.beginReview() }
                .disabled(vm.markedCount == 0 || vm.isCommitting)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.black)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text(L("cull.footer.keys"))
                .font(.callout)
                .foregroundStyle(.gray)
            if let message = vm.resultMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.green)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }

    // MARK: Pre-commit review grid

    private var reviewGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text(L("review.title", vm.markedCount))
                    .foregroundStyle(.white)
                Spacer()
                Button(L("review.back")) { vm.isReviewingMarked = false }
                Button(vm.isCommitting ? L("review.deleting") : L("review.confirm", vm.markedCount)) { vm.commit() }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.markedCount == 0 || vm.isCommitting)
            }
            .padding()
            Divider()
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                    ForEach(vm.markedAssets, id: \.localIdentifier) { asset in
                        MarkedThumb(
                            asset: asset,
                            isVideo: asset.mediaType == .video,
                            load: vm.loadThumbnail,
                            onUnmark: { vm.unmark(asset) }
                        )
                    }
                }
                .padding()
            }
            if let message = vm.resultMessage {
                Text(message).font(.footnote).foregroundStyle(.green).padding()
            }
        }
        .background(Color.black)
    }

    // MARK: Other states

    private var emptyView: some View {
        VStack(spacing: 12) {
            Text(vm.source == .screenshots ? L("cull.empty.screenshots") : L("cull.empty.all"))
                .foregroundStyle(.white)
            sourcePicker
        }
    }

    private var finishedView: some View {
        VStack(spacing: 16) {
            Text(L("cull.finished.title")).font(.title).foregroundStyle(.white)
            Text(L("cull.finished.marked", vm.markedCount)).foregroundStyle(.white)
            if vm.markedCount > 0 {
                Button(L("cull.finished.review", vm.markedCount)) { vm.beginReview() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(vm.isCommitting)
            }
            Button(L("cull.finished.reload")) { vm.reload() }
            Text(L("cull.finished.undoHint")).font(.footnote).foregroundStyle(.gray)
            if let message = vm.resultMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.green)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding()
    }

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

    private var sourcePicker: some View {
        Picker("", selection: Binding(get: { vm.source }, set: { vm.setSource($0) })) {
            ForEach(PhotoSource.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }

    // MARK: Formatting helpers

    private func infoText(for asset: PHAsset) -> String {
        var parts: [String] = []
        if let date = asset.creationDate {
            parts.append(date.formatted(date: .abbreviated, time: .shortened))
        }
        parts.append(typeLabel(for: asset))
        return parts.joined(separator: "  ·  ")
    }

    private func typeLabel(for asset: PHAsset) -> String {
        if asset.mediaType == .video { return L("type.video") + " " + durationString(asset.duration) }
        if asset.mediaSubtypes.contains(.photoScreenshot) { return L("type.screenshot") }
        if asset.mediaSubtypes.contains(.photoLive) { return L("type.live") }
        return L("type.photo")
    }

    private func durationString(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// One cell in the review grid: a thumbnail you click to move the item out of the delete set.
private struct MarkedThumb: View {
    let asset: PHAsset
    let isVideo: Bool
    let load: (PHAsset, CGSize, @escaping (NSImage?) -> Void) -> Void
    let onUnmark: () -> Void
    @State private var image: NSImage?

    var body: some View {
        Button(action: onUnmark) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image {
                        Image(nsImage: image).resizable().scaledToFill()
                    } else {
                        Color.gray.opacity(0.25)
                    }
                }
                .frame(width: 140, height: 140)
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    if isVideo {
                        Image(systemName: "play.circle.fill")
                            .foregroundStyle(.white)
                            .padding(4)
                    }
                }
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.white, .red)
                    .padding(4)
            }
        }
        .buttonStyle(.plain)
        .help(L("thumb.unmark.help"))
        .onAppear {
            load(asset, CGSize(width: 280, height: 280)) { img in
                Task { @MainActor in self.image = img }
            }
        }
    }
}
