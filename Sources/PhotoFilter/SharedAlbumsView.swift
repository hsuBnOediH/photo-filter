import SwiftUI
import Photos

/// The shared-albums module: pick a shared album, mark photos, remove your own posts.
/// Mouse-driven v1 — only Esc (back to home) is on the keyboard.
struct SharedAlbumsView: View {
    @ObservedObject var vm: SharedAlbumsViewModel
    var onHome: () -> Void
    @State private var isConfirmingRemoval = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
        }
        .frame(minWidth: 700, minHeight: 500)
        .background(RawKeyCatcher(onKeyDown: { event in
            guard event.keyCode == 53 else { return false }
            onHome()
            return true
        }))
        .onAppear { vm.requestAccess() }
        .alert(L("shared.confirm.title", vm.markedCount), isPresented: $isConfirmingRemoval) {
            Button(L("shared.confirm.remove"), role: .destructive) { vm.commitRemoval() }
            Button(L("common.cancel"), role: .cancel) {}
        } message: {
            Text(L("shared.confirm.message"))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.authStatus {
        case .notDetermined:
            ProgressView(L("common.requestingAccess"))
                .tint(.white)
                .foregroundStyle(.white)
        case .denied, .restricted:
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
        case .authorized, .limited:
            if vm.albums.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    header
                    Divider()
                    photoGrid
                    footer
                }
            }
        @unknown default:
            Text(L("common.unknownAuth")).foregroundStyle(.white)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            HStack {
                Button(L("common.backHome")) { onHome() }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 10)
            Spacer()
            Text(L("shared.empty.title")).font(.title3).foregroundStyle(.white)
            Text(L("shared.empty.body"))
                .font(.callout)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
            Button(L("shared.empty.recheck")) { vm.reloadAlbums() }
            Spacer()
        }
        .padding()
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(L("common.backHome")) { onHome() }
            Picker("", selection: Binding(get: { vm.selectedAlbumIndex }, set: { vm.selectAlbum($0) })) {
                ForEach(Array(vm.albums.enumerated()), id: \.offset) { pair in
                    Text(pair.element.localizedTitle ?? L("shared.album.untitled")).tag(pair.offset)
                }
            }
            .fixedSize()
            Text(L("shared.header.count", vm.assets.count))
                .monospacedDigit()
                .foregroundStyle(.gray)
            Spacer()
            Text(L("shared.header.marked", vm.markedCount))
                .monospacedDigit()
                .foregroundStyle(vm.markedCount > 0 ? .red : .gray)
            Button(vm.isCommitting ? L("shared.header.removing") : L("shared.header.removeButton")) { isConfirmingRemoval = true }
                .disabled(vm.markedCount == 0 || vm.isCommitting)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.black)
    }

    private var photoGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                ForEach(vm.assets, id: \.localIdentifier) { asset in
                    SharedThumb(
                        asset: asset,
                        isMarked: vm.isMarked(asset),
                        cached: vm.cachedThumbnail(for: asset),
                        load: vm.loadThumbnail,
                        onTap: { vm.toggle(asset) }
                    )
                }
            }
            .padding()
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text(L("shared.footer.hint"))
                .font(.callout)
                .foregroundStyle(.gray)
            if let message = vm.resultMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(vm.lastRemovalFailed ? .orange : .green)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }
}

/// One cell in the shared-album grid: click toggles the removal mark.
private struct SharedThumb: View {
    let asset: PHAsset
    let isMarked: Bool
    let cached: NSImage?
    let load: (PHAsset, CGSize, @escaping (NSImage?) -> Void) -> Void
    let onTap: () -> Void
    @State private var image: NSImage?

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let shown = image ?? cached {
                        Image(nsImage: shown).resizable().scaledToFill()
                    } else {
                        Color.gray.opacity(0.25)
                    }
                }
                .frame(width: 140, height: 140)
                .clipped()
                .opacity(isMarked ? 0.45 : 1)
                .overlay(alignment: .bottomLeading) {
                    if asset.mediaType == .video {
                        Image(systemName: "play.circle.fill")
                            .foregroundStyle(.white)
                            .padding(4)
                    }
                }
                if isMarked {
                    Text(L("thumb.toRemove"))
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.red)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .padding(5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isMarked ? .red.opacity(0.8) : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .onAppear {
            guard image == nil else { return }
            load(asset, OrganizeViewModel.thumbPixelSize) { img in
                Task { @MainActor in self.image = img }
            }
        }
    }
}
