import Photos
import Vision
import CoreLocation

/// A cluster of visually similar photos shot around the same time and place.
struct PhotoGroup: Identifiable {
    let id: String            // keeper's localIdentifier — stable for one scan's lifetime
    var assets: [PHAsset]     // creationDate ascending
    let recommendedID: String // the photo the heuristic suggests keeping
}

/// Adjustable "同一时间" bucketing window.
enum TimeWindow: Int, CaseIterable, Identifiable {
    case oneMinute = 60
    case fiveMinutes = 300
    case thirtyMinutes = 1800
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .oneMinute: return "1 分钟"
        case .fiveMinutes: return "5 分钟"
        case .thirtyMinutes: return "30 分钟"
        }
    }
}

/// Pure grouping logic — no UI, no PhotoKit writes. Runs on background threads.
enum AssetGrouper {

    /// Stage A — time+location bucketing. Sweeps chronologically (input must be
    /// creationDate ASCENDING) comparing each asset to the PREVIOUS one: a new bucket
    /// starts when the time gap exceeds the window, or both assets carry GPS and are
    /// farther apart than `radiusMeters`. Chaining to the previous asset (not the bucket
    /// anchor) keeps burst granularity while letting a continuous shoot form one long
    /// bucket — the CV stage splits scenes inside it. Assets with no creationDate can't
    /// be bucketed and are skipped (returned as a count for the scan summary).
    static func bucket(
        _ assets: [PHAsset],
        window: TimeInterval,
        radiusMeters: Double = 100
    ) -> (buckets: [[PHAsset]], skippedNoDate: Int) {
        var buckets: [[PHAsset]] = []
        var current: [PHAsset] = []
        var previous: PHAsset?
        var skipped = 0

        for asset in assets {
            guard let date = asset.creationDate else {
                skipped += 1
                continue
            }
            if let prev = previous, let prevDate = prev.creationDate {
                var sameBucket = date.timeIntervalSince(prevDate) <= window
                if sameBucket, let loc = asset.location, let prevLoc = prev.location {
                    // Only enforce distance when BOTH have GPS; otherwise time decides.
                    sameBucket = loc.distance(from: prevLoc) <= radiusMeters
                }
                if !sameBucket {
                    buckets.append(current)
                    current = []
                }
            }
            current.append(asset)
            previous = asset
        }
        if !current.isEmpty { buckets.append(current) }
        return (buckets, skipped)
    }

    /// Stage B — split one time bucket into clusters of visually similar photos.
    /// Buckets are small (rarely >100), so O(n²) pairwise distances + union-find is
    /// fine. Assets without a feature print stay singletons. Only clusters of ≥2 are
    /// returned — a photo with no similar neighbor isn't interesting to the organizer.
    static func cluster(
        bucket: [PHAsset],
        prints: [String: VNFeaturePrintObservation],
        threshold: Float,
        engine: SimilarityEngine
    ) -> [[PHAsset]] {
        guard bucket.count >= 2 else { return [] }
        var unionFind = UnionFind(count: bucket.count)
        for i in 0..<bucket.count {
            guard let printI = prints[bucket[i].localIdentifier] else { continue }
            for j in (i + 1)..<bucket.count {
                guard let printJ = prints[bucket[j].localIdentifier],
                      let distance = engine.distance(printI, printJ),
                      distance <= threshold else { continue }
                unionFind.union(i, j)
            }
        }
        var clusters: [Int: [PHAsset]] = [:]
        for i in 0..<bucket.count {
            clusters[unionFind.find(i), default: []].append(bucket[i])
        }
        // Bucket order is chronological, so each cluster stays creationDate-ascending.
        return clusters.values.filter { $0.count >= 2 }
    }

    /// Which photo of a cluster to keep: favorite > edited > pixel count > newest.
    /// The edited check hits the Photos DB (asset resources), so it only ever runs here,
    /// for the handful of photos that actually clustered — never during the bulk scan.
    /// Sharpness scoring is a possible later upgrade (the 300px thumb is already in hand
    /// during print computation; a Laplacian-variance pass would slot in cheaply).
    static func recommendKeeper(in cluster: [PHAsset]) -> PHAsset {
        func score(_ asset: PHAsset) -> (Int, Int, Int, TimeInterval) {
            (
                asset.isFavorite ? 1 : 0,
                isEdited(asset) ? 1 : 0,
                asset.pixelWidth * asset.pixelHeight,
                asset.creationDate?.timeIntervalSince1970 ?? 0
            )
        }
        let scored = cluster.map { (asset: $0, score: score($0)) }
        return scored.max { $0.score < $1.score }!.asset
    }

    private static func isEdited(_ asset: PHAsset) -> Bool {
        PHAssetResource.assetResources(for: asset).contains { $0.type == .adjustmentData }
    }
}

/// Minimal union-find with path compression — plenty for per-bucket clustering.
private struct UnionFind {
    private var parent: [Int]

    init(count: Int) {
        parent = Array(0..<count)
    }

    mutating func find(_ x: Int) -> Int {
        var root = x
        while parent[root] != root { root = parent[root] }
        var current = x
        while parent[current] != root {
            let next = parent[current]
            parent[current] = root
            current = next
        }
        return root
    }

    mutating func union(_ a: Int, _ b: Int) {
        let rootA = find(a), rootB = find(b)
        if rootA != rootB { parent[rootB] = rootA }
    }
}
