import AppKit
import Foundation

/// Update check against GitHub Releases — deliberately NOT Sparkle for v1.0: Sparkle
/// can't install updates into an ad-hoc-signed app anyway (revisit once Developer ID
/// signing + notarization land), while "open the download page" works today and needs
/// no framework embedding.
@MainActor
enum UpdateChecker {
    static let repo = "hsuBnOediH/photo-filter"
    static var releasesPage: URL { URL(string: "https://github.com/\(repo)/releases/latest")! }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    enum Result {
        case upToDate
        case updateAvailable(version: String, url: URL)
        case failed(String)
    }

    /// Manual check (menu item) — always reports a result via alert.
    static func checkInteractively() {
        check { result in
            let alert = NSAlert()
            switch result {
            case .upToDate:
                alert.messageText = L("update.upToDate.title")
                alert.informativeText = L("update.upToDate.message", currentVersion)
                alert.runModal()
            case .updateAvailable(let version, let url):
                alert.messageText = L("update.available.title", version)
                alert.informativeText = L("update.available.message", currentVersion, version)
                alert.addButton(withTitle: L("update.available.download"))
                alert.addButton(withTitle: L("update.available.skip"))
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(url)
                }
            case .failed(let message):
                alert.messageText = L("update.failed.title")
                alert.informativeText = message
                alert.runModal()
            }
        }
    }

    /// Launch check — silent unless an update exists; gated by the Settings toggle and
    /// throttled to once per 24 h.
    static func checkOnLaunchIfEnabled() {
        guard UserDefaults.standard.object(forKey: "update.autoCheck") == nil
            || UserDefaults.standard.bool(forKey: "update.autoCheck") else { return }
        let last = UserDefaults.standard.double(forKey: "update.lastCheck")
        guard Date().timeIntervalSince1970 - last > 86_400 else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "update.lastCheck")
        check { result in
            if case .updateAvailable(let version, let url) = result {
                let alert = NSAlert()
                alert.messageText = L("update.available.title", version)
                alert.informativeText = L("update.available.message", currentVersion, version)
                alert.addButton(withTitle: L("update.available.download"))
                alert.addButton(withTitle: L("update.available.skip"))
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private static func check(completion: @escaping @MainActor (Result) -> Void) {
        let api = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        URLSession.shared.dataTask(with: api) { data, _, error in
            Task { @MainActor in
                if let error {
                    completion(.failed(error.localizedDescription))
                    return
                }
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String
                else {
                    completion(.failed(L("update.failed.parse")))
                    return
                }
                let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                let url = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? releasesPage
                if isNewer(latest, than: currentVersion) {
                    completion(.updateAvailable(version: latest, url: url))
                } else {
                    completion(.upToDate)
                }
            }
        }.resume()
    }

    /// Numeric dotted-version comparison ("1.10.0" > "1.9.2").
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let lhs = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(lhs.count, rhs.count) {
            let l = i < lhs.count ? lhs[i] : 0
            let r = i < rhs.count ? rhs[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}
