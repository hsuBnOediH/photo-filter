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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
            if vm.isZoomed, let asset = vm.selectedAsset {
                // .id() recreates the overlay when arrows move the cursor while zoomed,
                // so the displayed image follows the selection.
                ZoomOverlay(asset: asset, load: vm.loadImage)
                    .id(asset.localIdentifier)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .background(RawKeyCatcher(onKeyDown: handleKey))
        .onAppear { vm.requestAccess() }
    }

    // MARK: Keyboard

    private func handleKey(_ event: NSEvent) -> Bool {
        // Esc backs out one layer at a time: zoom → home.
        if event.keyCode == 53 {
            if vm.isZoomed {
                vm.isZoomed = false
            } else {
                onHome()
            }
            return true
        }
        // Groups stream in while the scan runs — keys work as soon as any exist.
        guard !vm.groups.isEmpty else { return false }
        if vm.queueFinished {
            if event.keyCode == 126 {                     // ↑ steps back into the queue
                vm.queueFinished = false
                return true
            }
            return false
        }
        switch event.keyCode {
        case 126: vm.selectPreviousGroup(); return true   // ↑ (browse back; no review mark)
        case 125: vm.selectNextGroup(); return true       // ↓ (browse ahead; no review mark)
        case 123: vm.selectPreviousPhoto(); return true   // ←
        case 124: vm.selectNextPhoto(); return true       // →
        case 49:  vm.isZoomed.toggle(); return true       // space
        case 51:  vm.toggleSelected(); return true        // ⌫ delete
        case 40:  vm.keepOnlySelected(); return true      // K
        case 36, 76: vm.finishCurrentGroup(); return true // Enter — done with this group
        default:  return false
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch vm.authStatus {
        case .notDetermined:
            ProgressView("正在请求照片访问权限…")
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
            Text("未知的授权状态").foregroundStyle(.white)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button("← 首页") { onHome() }
            Button(vm.phase == .idle ? "开始扫描" : "重新扫描") { vm.startScan() }
                .disabled(vm.isScanning || vm.isCommitting)
            // Settings stay clickable during a scan — startScan() snapshots its values,
            // so mid-scan changes only affect the NEXT scan (the hint says as much).
            Text("时间窗口")
                .font(.footnote)
                .foregroundStyle(.gray)
            Picker("", selection: Binding(get: { vm.timeWindow }, set: { vm.timeWindow = $0 })) {
                ForEach(TimeWindow.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            Text("相似度")
                .font(.footnote)
                .foregroundStyle(.gray)
            Picker("", selection: Binding(get: { vm.similarity }, set: { vm.similarity = $0 })) {
                ForEach(SimilarityLevel.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            Spacer()
            if !vm.groups.isEmpty {
                Text("第 \(min(vm.selectedGroup + 1, vm.groups.count)) / \(vm.groups.count) 组 · 已审 \(vm.reviewedGroupIDs.count)")
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            Button(vm.isCommitting ? "删除中…" : "删除已审待删 (\(vm.reviewedMarkedCount))") {
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
        Text("受限访问模式:仅扫描已授权的照片")
            .font(.footnote)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(.orange.opacity(0.12))
    }

    private var settingsChangedHint: some View {
        Text("设置已更改,重新扫描后生效")
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
            scanStatus("正在读取照片库…", progress: nil)
        case .analyzing(let done, let total):
            // Results stream in while the scan runs: once any group exists, the review
            // takes over and the progress collapses into a slim banner.
            if vm.groups.isEmpty {
                scanStatus("正在分析照片特征  \(done) / \(total) — 找到的组会立即显示",
                           progress: total > 0 ? Double(done) / Double(total) : nil)
            } else {
                VStack(spacing: 0) {
                    scanBanner(done: done, total: total)
                    reviewArea
                }
            }
        case .cancelled:
            VStack(spacing: 12) {
                Text("已取消 — 已分析的照片特征已缓存,下次扫描会更快。")
                    .foregroundStyle(.white)
                Button("重新扫描") { vm.startScan() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .done:
            if vm.groups.isEmpty {
                VStack(spacing: 12) {
                    Text("没有发现相似照片组 🎉")
                        .font(.title3)
                        .foregroundStyle(.white)
                    Text("可尝试放宽相似度或加大时间窗口后重新扫描。")
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
                Text("调整好去留后按 Enter 看下一组")
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
            Text(vm.isScanning ? "当前找到的组都看完了" : "这一轮已全部审阅 🎉")
                .font(.title3)
                .foregroundStyle(.white)
            if vm.isScanning {
                Text("扫描还在进行,新发现的组会自动续上。")
                    .foregroundStyle(.gray)
            }
            Button(vm.isCommitting ? "删除中…" : "删除已审待删 (\(vm.reviewedMarkedCount))") {
                vm.deleteReviewed()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled((vm.reviewedMarkedCount == 0 && vm.reviewedGroupIDs.isEmpty) || vm.isCommitting)
            Button("↑ 回看上一组") { vm.queueFinished = false }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var idleView: some View {
        VStack(spacing: 14) {
            Text("个人照片整理")
                .font(.title)
                .foregroundStyle(.white)
            Text("按拍摄时间和地点把相邻照片归组,再用本地视觉模型确认同一场景。\n一次只看一组:每组自动推荐保留最好的一张,你调整后按 Enter 看下一组,\n随时点「删除已审待删」清掉已审阅组的弃片 — 没看过的组绝不会被动到。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))
            Text("分析全部在本机完成,不会上传照片;在你确认删除之前不会改动照片库。")
                .font(.footnote)
                .foregroundStyle(.gray)
            Button("开始扫描") { vm.startScan() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Slim in-list progress strip shown while the review is already usable.
    private func scanBanner(done: Int, total: Int) -> some View {
        HStack(spacing: 12) {
            ProgressView(value: total > 0 ? Double(done) / Double(total) : 0)
                .frame(width: 180)
            Text("分析中 \(done) / \(total) — 可以边扫边审阅")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.gray)
            Spacer()
            Button("停止扫描") { vm.cancelScan() }
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
            Button("取消") { vm.cancelScan() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("←/→  选择照片      ⌫  切换保留/待删      K  仅保留这张      Enter  下一组      ↑/↓  前后翻组      空格  放大      Esc  返回")
                .font(.callout)
                .foregroundStyle(.gray)
            if !vm.groups.isEmpty {
                Text("删除会同步到所有设备;如启用 iCloud 共享图库,删除共享照片将对所有成员生效。")
                    .font(.footnote)
                    .foregroundStyle(.orange.opacity(0.85))
            }
            if vm.phase == .done && vm.skippedCount > 0 {
                Text("跳过 \(vm.skippedCount) 张(无法加载或无拍摄时间)")
                    .font(.footnote)
                    .foregroundStyle(.gray)
            }
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

    // MARK: Other states

    private var deniedView: some View {
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
        guard let first = group.assets.first?.creationDate else { return "未知时间" }
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
                Text("\(group.assets.count) 张 · 保留 \(keptCount) 张")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(keptCount == 0 ? .red : .gray)
                Spacer()
                Button("重置为推荐") { vm.resetToRecommendation(group) }
                    .font(.callout)
                // Immediate partial cleanup: clears this group on the spot.
                Button("立即删除本组待删 (\(group.assets.count - keptCount))") { vm.commitGroup(group) }
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
                Text(isMarked ? "待删" : "保留")
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
                        .help("推荐保留")
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
        .help("点一下切换保留/待删")
        .onAppear {
            guard image == nil else { return }
            load(asset, OrganizeViewModel.thumbPixelSize) { img in
                Task { @MainActor in self.image = img }
            }
        }
    }
}

// MARK: - Full-window zoom of the cursor photo

private struct ZoomOverlay: View {
    let asset: PHAsset
    let load: (PHAsset, @escaping (NSImage?) -> Void) -> Void
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Color.black.opacity(0.96).ignoresSafeArea()
            if let image {
                Image(nsImage: image).resizable().scaledToFit().padding(24)
            } else {
                ProgressView().tint(.white)
            }
        }
        .onAppear {
            // .opportunistic delivery may call back twice (fast low-res, then sharp);
            // each call just replaces what's shown.
            load(asset) { img in
                Task { @MainActor in self.image = img }
            }
        }
    }
}
