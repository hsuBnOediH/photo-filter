import Photos
import Vision
import AppKit

/// Three similarity tiers mapping to Vision feature-print distance thresholds.
/// Raw values are stable English identifiers (persisted in UserDefaults/JSON);
/// display text comes from `label`.
enum SimilarityLevel: String, CaseIterable, Identifiable {
    case strict
    case standard
    case loose
    var id: String { rawValue }

    var label: String {
        switch self {
        case .strict: return L("similarity.strict")
        case .standard: return L("similarity.standard")
        case .loose: return L("similarity.loose")
        }
    }

    /// Revision-2 distances run roughly 0 (identical) … ~1+ (unrelated); a synthetic
    /// sanity check measured ~0.18 for a near-duplicate pair and ~0.86 for unrelated
    /// compositions. Starting points — tune here if grouping is too eager or too shy.
    var threshold: Float {
        switch self {
        case .strict: return 0.35
        case .standard: return 0.55
        case .loose: return 0.80
        }
    }
}

/// Computes and disk-caches Vision feature prints (a photo's content fingerprint).
/// Everything here is synchronous and must run on background threads — the scan
/// pipeline calls it from an OperationQueue and hops results back to the main actor.
/// @unchecked: immutable after init (cacheDir is let; file I/O is per-call atomic).
final class SimilarityEngine: @unchecked Sendable {
    /// Pinned revision: rev-1 and rev-2 prints live on different distance scales and
    /// can't be compared across revisions (computeDistance throws). The cache directory
    /// is namespaced by this constant, so bumping it auto-invalidates old prints.
    static let revision = VNGenerateImageFeaturePrintRequestRevision2
    static let thumbnailSide: CGFloat = 300

    private let cacheDir: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        cacheDir = support
            .appendingPathComponent("PhotoFilter", isDirectory: true)
            .appendingPathComponent("FeaturePrints", isDirectory: true)
            .appendingPathComponent("r\(Self.revision)", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    /// Cache-or-compute. Returns nil when the thumbnail can't be loaded or Vision fails;
    /// callers count those as skipped and the asset simply never joins a similarity group.
    func featurePrint(for asset: PHAsset, library: PhotoLibrary) -> VNFeaturePrintObservation? {
        let url = cacheURL(for: asset)
        let stamp = cacheStamp(for: asset)
        if let cached = loadCached(at: url, expectedStamp: stamp) { return cached }
        guard let cgImage = library.requestScanImage(for: asset, side: Self.thumbnailSide) else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = Self.revision
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first as? VNFeaturePrintObservation else { return nil }
        store(observation, stamp: stamp, at: url)
        return observation
    }

    func distance(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) -> Float? {
        var distance: Float = 0
        guard (try? a.computeDistance(&distance, to: b)) != nil else { return nil }
        return distance
    }

    // MARK: Disk cache

    // One archived {timestamp, observation} dictionary per asset, keyed by the asset's
    // localIdentifier alone and OVERWRITTEN when the photo is edited (modificationDate
    // moves → stamp mismatch → recompute). Vision exposes the print's raw floats
    // read-only with no way to rebuild an observation from them, so archiving the
    // observation object itself is the only way to persist it (~4 KB each).

    private func cacheURL(for asset: PHAsset) -> URL {
        // Identifiers look like "UUID/L0/001" — make them filesystem-safe.
        let name = asset.localIdentifier.replacingOccurrences(of: "/", with: "_")
        return cacheDir.appendingPathComponent(name + ".vnfp")
    }

    private func cacheStamp(for asset: PHAsset) -> Int {
        Int((asset.modificationDate ?? asset.creationDate ?? .distantPast).timeIntervalSince1970)
    }

    private func loadCached(at url: URL, expectedStamp: Int) -> VNFeaturePrintObservation? {
        guard let data = try? Data(contentsOf: url),
              let wrapper = try? NSKeyedUnarchiver.unarchivedObject(
                  ofClasses: [NSDictionary.self, NSNumber.self, NSString.self, VNFeaturePrintObservation.self],
                  from: data
              ) as? NSDictionary,
              let stamp = (wrapper["t"] as? NSNumber)?.intValue,
              stamp == expectedStamp,
              let observation = wrapper["fp"] as? VNFeaturePrintObservation
        else { return nil }
        return observation
    }

    private func store(_ observation: VNFeaturePrintObservation, stamp: Int, at url: URL) {
        let wrapper: NSDictionary = ["t": NSNumber(value: stamp), "fp": observation]
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: wrapper, requiringSecureCoding: true)
        else { return }
        try? data.write(to: url, options: .atomic)
    }
}
