import SwiftUI

struct AboutView: View {
    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("PhotoFilter")
                .font(.title.bold())
            Text(L("about.version", version))
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(L("about.tagline"))
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Link("GitHub", destination: URL(string: "https://github.com/\(UpdateChecker.repo)")!)
                Link(L("about.license"), destination: URL(string: "https://github.com/\(UpdateChecker.repo)/blob/main/LICENSE")!)
            }
            .font(.callout)
        }
        .padding(28)
        .frame(width: 340)
    }
}
