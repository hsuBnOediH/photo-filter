import SwiftUI

/// App entry screen: a home page where the user picks a module. Each module is fully
/// independent (own view model, own marks, own commit) — that separation is deliberate,
/// so a new module can never destabilize an existing one. The screenshot module embeds
/// the original CullView untouched; its back bar lives here for the same reason.
struct RootView: View {
    enum Section {
        case home
        case screenshots
        case personal
        case sharedAlbums
    }

    @State private var section: Section = .home
    // VMs live here so module state (deck progress, scan results, marks) survives
    // switching back to the home screen. They are only torn down when the app quits.
    @StateObject private var cullVM = CullViewModel()
    @StateObject private var organizeVM = OrganizeViewModel()
    @StateObject private var sharedVM = SharedAlbumsViewModel()

    var body: some View {
        switch section {
        case .home:
            homeView
        case .screenshots:
            VStack(spacing: 0) {
                backBar
                CullView(vm: cullVM, onHome: { section = .home })
            }
            .background(Color.black)
        case .personal:
            OrganizeView(vm: organizeVM, onHome: { section = .home })
        case .sharedAlbums:
            SharedAlbumsView(vm: sharedVM, onHome: { section = .home })
        }
    }

    // MARK: Home

    private var homeView: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Text("PhotoFilter")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(.white)
                    Text("选择要整理的内容")
                        .font(.title3)
                        .foregroundStyle(.gray)
                }
                LazyVGrid(columns: [GridItem(.fixed(260)), GridItem(.fixed(260))], spacing: 16) {
                    ModuleCard(
                        icon: "camera.viewfinder",
                        title: "截图清理",
                        subtitle: "逐张刷卡,快速清掉没用的截图",
                        action: { section = .screenshots }
                    )
                    ModuleCard(
                        icon: "photo.stack",
                        title: "个人照片",
                        subtitle: "只扫自己拍的照片,按时间地点 + 相似度分组",
                        action: { section = .personal }
                    )
                    ModuleCard(
                        icon: "person.2.crop.square.stack",
                        title: "共享相册",
                        subtitle: "浏览家人共享的相册,移除你自己发布的内容",
                        action: { section = .sharedAlbums }
                    )
                    ModuleCard(icon: "video", title: "视频", subtitle: "清理重复和废片视频", action: nil)
                }
            }
            .padding(40)
        }
        .frame(minWidth: 700, minHeight: 500)
    }

    private var backBar: some View {
        HStack(spacing: 10) {
            Button(action: { section = .home }) {
                Label("返回首页", systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)
            Text("按 Esc 也可返回")
                .font(.footnote)
                .foregroundStyle(.gray)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color.black)
    }
}

/// One module entry on the home screen. `action == nil` means the module isn't built
/// yet — shown dimmed with a "敬请期待" badge.
private struct ModuleCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: (() -> Void)?

    var body: some View {
        Button(action: { action?() }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 28))
                        .foregroundStyle(action != nil ? .white : .gray)
                    Spacer()
                    if action == nil {
                        Text("敬请期待")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.gray.opacity(0.3))
                            .foregroundStyle(.gray)
                            .clipShape(Capsule())
                    }
                }
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(action != nil ? .white : .gray)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(width: 260, height: 140, alignment: .topLeading)
            .background(.white.opacity(action != nil ? 0.08 : 0.04))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.white.opacity(action != nil ? 0.15 : 0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}
