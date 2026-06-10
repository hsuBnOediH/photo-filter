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
        .alert("从共享相册移除 \(vm.markedCount) 项?", isPresented: $isConfirmingRemoval) {
            Button("移除", role: .destructive) { vm.commitRemoval() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("移除立即对所有成员生效,且不会进入「最近删除」、无法恢复。只能移除你自己发布的照片。")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.authStatus {
        case .notDetermined:
            ProgressView("正在请求照片访问权限…")
                .tint(.white)
                .foregroundStyle(.white)
        case .denied, .restricted:
            VStack(spacing: 16) {
                Text("没有照片访问权限").font(.title2).foregroundStyle(.white)
                Text("请在系统设置中授予「完全访问」,然后重新打开 App。")
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Button("打开系统设置 → 隐私与安全性 → 照片") {
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
            Text("未知的授权状态").foregroundStyle(.white)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            HStack {
                Button("← 首页") { onHome() }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 10)
            Spacer()
            Text("没有找到共享相册").font(.title3).foregroundStyle(.white)
            Text("""
            这里展示的是 iCloud「共享相册」。如果这里是空的、但「个人照片」里仍能看到家人的照片,
            说明你们使用的是 iCloud「共享图库」—— Apple 没有提供 API 区分共享图库中的照片,
            App 无法把它们和你自己拍的分开,只能在删除前提醒(删除会对所有成员生效)。
            """)
            .font(.callout)
            .foregroundStyle(.gray)
            .multilineTextAlignment(.center)
            Button("重新检查") { vm.reloadAlbums() }
            Spacer()
        }
        .padding()
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button("← 首页") { onHome() }
            Picker("", selection: Binding(get: { vm.selectedAlbumIndex }, set: { vm.selectAlbum($0) })) {
                ForEach(Array(vm.albums.enumerated()), id: \.offset) { pair in
                    Text(pair.element.localizedTitle ?? "未命名相册").tag(pair.offset)
                }
            }
            .fixedSize()
            Text("\(vm.assets.count) 项")
                .monospacedDigit()
                .foregroundStyle(.gray)
            Spacer()
            Text("待移除 \(vm.markedCount)")
                .monospacedDigit()
                .foregroundStyle(vm.markedCount > 0 ? .red : .gray)
            Button(vm.isCommitting ? "移除中…" : "移除所选") { isConfirmingRemoval = true }
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
            Text("点缩略图标记/取消标记 — 只能移除你自己发布的照片;移除对所有成员生效,不可恢复")
                .font(.callout)
                .foregroundStyle(.gray)
            if let message = vm.resultMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(message.contains("失败") ? .orange : .green)
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
                    Text("待移除")
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
