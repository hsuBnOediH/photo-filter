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
                    Text(L("home.subtitle"))
                        .font(.title3)
                        .foregroundStyle(.gray)
                }
                LazyVGrid(columns: [GridItem(.fixed(260)), GridItem(.fixed(260))], spacing: 16) {
                    ModuleCard(
                        icon: "camera.viewfinder",
                        title: L("home.card.screenshots.title"),
                        subtitle: L("home.card.screenshots.subtitle"),
                        action: { section = .screenshots }
                    )
                    ModuleCard(
                        icon: "photo.stack",
                        title: L("home.card.personal.title"),
                        subtitle: L("home.card.personal.subtitle"),
                        action: { section = .personal }
                    )
                    ModuleCard(
                        icon: "person.2.crop.square.stack",
                        title: L("home.card.shared.title"),
                        subtitle: L("home.card.shared.subtitle"),
                        action: { section = .sharedAlbums }
                    )
                    ModuleCard(
                        icon: "video",
                        title: L("home.card.videos.title"),
                        subtitle: L("home.card.videos.subtitle"),
                        action: nil
                    )
                }
            }
            .padding(40)
        }
        .frame(minWidth: 700, minHeight: 500)
    }

    private var backBar: some View {
        HStack(spacing: 10) {
            Button(action: { section = .home }) {
                Label(L("nav.backHome.button"), systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)
            Text(L("nav.escHint"))
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
                        Text(L("home.card.comingSoon"))
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
