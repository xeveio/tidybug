import Accelerate
import Foundation
import ImageIO
import Vision

public struct SimilarPhoto: Sendable, Identifiable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public let size: Int64
    public let modified: Date
    public let pixelWidth: Int
    public let pixelHeight: Int

    public init(url: URL, size: Int64, modified: Date, pixelWidth: Int, pixelHeight: Int) {
        self.url = url
        self.size = size
        self.modified = modified
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    public var name: String { url.lastPathComponent }
    public var pixels: Int { pixelWidth * pixelHeight }
    public var item: CleanItem { CleanItem(url: url, size: size, modified: modified) }
}

public struct PhotoCluster: Sendable, Identifiable, Hashable {
    public let id: String
    public let photos: [SimilarPhoto]     // keeper first
    public let keeperID: String
    /// Largest distance from the keeper — 0 means pixel-identical.
    public let spread: Float

    public init(id: String, photos: [SimilarPhoto], keeperID: String, spread: Float) {
        self.id = id
        self.photos = photos
        self.keeperID = keeperID
        self.spread = spread
    }

    /// Same cluster without the given paths; nil once fewer than two photos remain.
    public func removing(_ paths: Set<String>) -> PhotoCluster? {
        let left = photos.filter { !paths.contains($0.id) }
        guard left.count > 1 else { return nil }
        let keeper = left.contains { $0.id == keeperID } ? keeperID : SimilarImageFinder.chooseKeeper(left).id
        return PhotoCluster(id: id, photos: left, keeperID: keeper, spread: spread)
    }

    /// Human label for how alike the cluster is.
    public var likeness: String {
        spread < 0.02 ? "Identical" : (isNearIdentical ? "Near-identical" : "Look-alikes")
    }

    /// Close enough to preselect the extras (re-saves, resizes, tiny edits).
    public var isNearIdentical: Bool { spread < 0.25 }

    public var keeper: SimilarPhoto { photos.first { $0.id == keeperID } ?? photos[0] }
    public var wasted: Int64 { photos.filter { $0.id != keeperID }.reduce(0) { $0 + $1.size } }
}

public struct PhotoProgress: Sendable {
    public var found: Int
    public var analyzed: Int
    public var currentPath: String
}

/// Groups visually similar photos using Vision feature prints.
public enum SimilarImageFinder {
    public static let extensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "webp", "bmp",
        "dng", "cr2", "cr3", "nef", "arw", "raf", "orf", "rw2",
    ]

    public static var defaultRoots: [String] {
        ["Pictures", "Downloads", "Desktop", "Documents"]
            .map { "\(NSHomeDirectory())/\($0)" }
            .filter { FileManager.default.fileExists(atPath: $0) }
    }

    /// Distance threshold for a given strictness in 0 (loose) … 1 (strict).
    /// Calibrated on normalised revision-2 feature prints: an edited, resized,
    /// re-encoded copy lands around 0.48; unrelated pictures around 0.9.
    public static func threshold(strictness: Double) -> Float {
        Float(0.75 - 0.45 * max(0, min(1, strictness)))
    }

    public static let defaultThreshold = threshold(strictness: 0.5)

    public static func scan(
        roots: [String] = defaultRoots,
        minimumSize: Int64 = 20_000,
        threshold: Float = defaultThreshold,
        guard safety: SafetyGuard = SafetyGuard(),
        isCancelled: @escaping @Sendable () -> Bool = { Task.isCancelled },
        progress: @escaping @Sendable (PhotoProgress) -> Void = { _ in }
    ) async -> [PhotoCluster] {
        // 1. Collect image files.
        var files: [(url: URL, size: Int64, modified: Date)] = []
        var seenIDs = Set<FileID>()
        var counter = 0
        for root in DuplicateFinder.normalizedRoots(roots) {
            FileWalker.walk(root) { e in
                counter += 1
                if counter & 0x3FF == 0, isCancelled() { return .stop }
                switch e.kind {
                case .directory:
                    return e.level > 0 && DuplicateFinder.shouldSkip(directory: e.name) ? .skipChildren : .proceed
                case .file:
                    let name = e.name
                    guard let dot = name.lastIndex(of: "."),
                          extensions.contains(name[name.index(after: dot)...].lowercased()),
                          e.allocatedSize >= minimumSize,
                          seenIDs.insert(e.fileID).inserted else { return .proceed }
                    let url = URL(fileURLWithPath: e.path)
                    guard safety.isAllowed(url) else { return .proceed }
                    files.append((url, e.allocatedSize, e.modified))
                    if files.count % 50 == 0 {
                        progress(PhotoProgress(found: files.count, analyzed: 0, currentPath: e.path))
                    }
                    return .proceed
                default:
                    return .proceed
                }
            }
        }
        if isCancelled() { return [] }
        progress(PhotoProgress(found: files.count, analyzed: 0, currentPath: ""))

        // 2. Feature prints in parallel (bounded).
        let width = max(2, ProcessInfo.processInfo.activeProcessorCount)
        var prints: [(photo: SimilarPhoto, vector: [Float])] = []
        prints.reserveCapacity(files.count)
        await withTaskGroup(of: (SimilarPhoto, [Float])?.self) { group in
            var next = 0
            func enqueue() {
                guard next < files.count else { return }
                let f = files[next]
                next += 1
                group.addTask(priority: .utility) {
                    if isCancelled() { return nil }
                    return analyze(f.url, size: f.size, modified: f.modified)
                }
            }
            for _ in 0..<width { enqueue() }
            var analyzed = 0
            for await result in group {
                analyzed += 1
                if let result { prints.append(result) }
                if analyzed % 8 == 0 || analyzed == files.count {
                    progress(PhotoProgress(found: files.count, analyzed: analyzed,
                                           currentPath: result?.0.url.path ?? ""))
                }
                if isCancelled() { group.cancelAll() } else { enqueue() }
            }
        }
        if isCancelled() { return [] }

        return cluster(prints, threshold: threshold)
    }

    // MARK: Analysis

    static func analyze(_ url: URL, size: Int64, modified: Date) -> (SimilarPhoto, [Float])? {
        autoreleasepool {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let w = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
            let h = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 512,
            ]
            guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            guard let vector = featureVector(thumb) else { return nil }
            return (SimilarPhoto(url: url, size: size, modified: modified, pixelWidth: w, pixelHeight: h), vector)
        }
    }

    static func featureVector(_ image: CGImage) -> [Float]? {
        let request = VNGenerateImageFeaturePrintRequest()
        request.imageCropAndScaleOption = .scaleFill
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch { return nil }
        guard let obs = request.results?.first else { return nil }
        let count = obs.elementCount
        guard count > 0 else { return nil }
        var v = [Float](repeating: 0, count: count)
        switch obs.elementType {
        case .float:
            obs.data.withUnsafeBytes { raw in
                let src = raw.bindMemory(to: Float.self)
                for i in 0..<count { v[i] = src[i] }
            }
        case .double:
            obs.data.withUnsafeBytes { raw in
                let src = raw.bindMemory(to: Double.self)
                for i in 0..<count { v[i] = Float(src[i]) }
            }
        default:
            return nil
        }
        // Normalise so distances are comparable across revisions (0 … 2).
        var norm: Float = 0
        vDSP_svesq(v, 1, &norm, vDSP_Length(count))
        norm = sqrt(norm)
        if norm > 0 { vDSP_vsdiv(v, 1, &norm, &v, 1, vDSP_Length(count)) }
        return v
    }

    static func distance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return .infinity }
        var d: Float = 0
        vDSP_distancesq(a, 1, b, 1, &d, vDSP_Length(a.count))
        return sqrt(d)
    }

    // MARK: Clustering

    /// Clusters around a seed: a photo joins a cluster only when it is within
    /// `threshold` of the cluster's first member, which prevents long chains of
    /// merely-related photos from collapsing into one group.
    static func cluster(_ prints: [(photo: SimilarPhoto, vector: [Float])], threshold: Float) -> [PhotoCluster] {
        // Deterministic order: biggest first so the likely keeper seeds the cluster.
        let items = prints.sorted { $0.photo.pixels != $1.photo.pixels ? $0.photo.pixels > $1.photo.pixels : $0.photo.id < $1.photo.id }
        var assigned = [Bool](repeating: false, count: items.count)
        var clusters: [PhotoCluster] = []
        for i in items.indices where !assigned[i] {
            var members = [i]
            var spread: Float = 0
            for j in (i + 1)..<items.count where !assigned[j] {
                let d = distance(items[i].vector, items[j].vector)
                if d <= threshold {
                    members.append(j)
                    spread = max(spread, d)
                }
            }
            guard members.count > 1 else { continue }
            for m in members { assigned[m] = true }
            let photos = members.map { items[$0].photo }
            let keeper = chooseKeeper(photos)
            let ordered = [keeper] + photos.filter { $0.id != keeper.id }.sorted { $0.size > $1.size }
            clusters.append(PhotoCluster(id: keeper.id, photos: ordered, keeperID: keeper.id, spread: spread))
        }
        return clusters.sorted { $0.wasted > $1.wasted }
    }

    /// Highest resolution, then largest file, then newest.
    public static func chooseKeeper(_ photos: [SimilarPhoto]) -> SimilarPhoto {
        photos.max { a, b in
            if a.pixels != b.pixels { return a.pixels < b.pixels }
            if a.size != b.size { return a.size < b.size }
            return a.modified < b.modified
        }!
    }
}
