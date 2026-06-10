import Foundation

/// Localized string lookup against the SwiftPM resource bundle. SwiftUI's bare
/// `Text("key")` resolves against Bundle.main — useless for a SwiftPM target — so every
/// user-facing string goes through `L(...)` for grep-ability and a single lookup path.
func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: .module, comment: "")
}

/// Format-string variant, e.g. `L("result.deleted", count)`.
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), locale: .current, arguments: args)
}
