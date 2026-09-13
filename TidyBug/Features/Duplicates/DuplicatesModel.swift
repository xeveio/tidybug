import AppKit
import QuickLookThumbnailing
import SwiftUI
import TidyBugCore

/// State for the Twins pane: exact duplicate files and similar photos.
@MainActor @Observable
final class DuplicatesModel {
    static let shared = DuplicatesModel()

    enum Mode: String, CaseIterable, Identifiable {
        case files = "Files", photos = "Photos"
        var id: String { rawValue }
        var symbol: String { self == .files ? "doc.on.doc" : "photo.on.rectangle.angled" }
    }

    var mode: Mode = .files
    var roots: [String] {
        didSet { UserDefaults.standard.set(roots, forKey: "twinsRoots") }
    }
    var minimumSize: Int64 = 1 << 20
    /// 0 loose … 1 strict.
    var strictness: Double = 0.5

    // Files
    var groups: [DuplicateGroup] = []
    var fileProgress: DuplicateProgress?
    var filesScanning = false
    var filesScanned = false
    var fileSelection: Set<String> = []

    // Photos
    var clusters: [PhotoCluster] = []
    var photoProgress: PhotoProgress?
    var photosScanning = false
    var photosScanned = false
    var photoSelection: Set<String> = []

    /// User-chosen keeper per group/cluster id.
    var keeperOverrides: [String: String] = [:]

    private var flag: CancelFlag?

    init() {
        roots = UserDefaults.standard.stringArray(forKey: "twinsRoots") ?? Self.defaultRoots
    }

    static var defaultRoots: [String] {
        ["Downloads", "Desktop", "Documents", "Pictures"]
            .map { "\(NSHomeDirectory())/\($0)" }
            .filter { FileManager.default.fileExists(atPath: $0) }
    }

    // MARK: Derived

    var isScanning: Bool { mode == .files ? filesScanning : photosScanning }
    var hasScanned: Bool { mode == .files ? filesScanned : photosScanned }
    var resultCount: Int { mode == .files ? groups.count : clusters.count }

    var wastedTotal: Int64 {
        mode == .files ? groups.reduce(0) { $0 + $1.wasted } : clusters.reduce(0) { $0 + $1.wasted }
    }

    var selectedItems: [CleanItem] {
        switch mode {
        case .files: groups.flatMap { $0.files.filter { fileSelection.contains($0.id) }.map(\.item) }
        case .photos: clusters.flatMap { $0.photos.filter { photoSelection.contains($0.id) }.map(\.item) }
        }
    }

    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    func keeperID(_ group: DuplicateGroup) -> String { keeperOverrides[group.id] ?? group.keeperID }
    func keeperID(_ cluster: PhotoCluster) -> String { keeperOverrides[cluster.id] ?? cluster.keeperID }

    // MARK: Scanning

    func scan() {
        switch mode {
        case .files: scanFiles()
        case .photos: scanPhotos()
        }
    }

    func cancel() {
        flag?.set()
        withAnimation(.tidy) {
            filesScanning = false
            photosScanning = false
        }
    }

    func scanFiles() {
        flag?.set()
        let flag = CancelFlag()
        self.flag = flag
        let roots = roots, minimum = minimumSize, safety = AppModel.shared.safetyGuard
        withAnimation(.tidy) {
            filesScanning = true
            filesScanned = true
            groups = []
            fileSelection = []
            fileProgress = nil
        }
        Task.detached(priority: .userInitiated) { [weak self] in
            var last = Date.distantPast
            let result = DuplicateFinder.scan(roots: roots, minimumSize: minimum, guard: safety,
                                              isCancelled: { flag.isSet }) { p in
                guard p.phase == .done || Date().timeIntervalSince(last) > 0.06 else { return }
                last = Date()
                Task { @MainActor in self?.fileProgress = p }
            }
            await MainActor.run {
                guard let self, !flag.isSet else { return }
                withAnimation(.bouncy) {
                    self.groups = result
                    self.fileSelection = Set(result.flatMap { g in
                        g.files.filter { $0.id != g.keeperID && $0.autoSelectable }.map(\.id)
                    })
                    self.filesScanning = false
                }
            }
        }
    }

    func scanPhotos() {
        flag?.set()
        let flag = CancelFlag()
        self.flag = flag
        let roots = roots, safety = AppModel.shared.safetyGuard
        let threshold = SimilarImageFinder.threshold(strictness: strictness)
        withAnimation(.tidy) {
            photosScanning = true
            photosScanned = true
            clusters = []
            photoSelection = []
            photoProgress = nil
        }
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = await SimilarImageFinder.scan(
                roots: roots, threshold: threshold, guard: safety,
                isCancelled: { flag.isSet },
                progress: { p in Task { @MainActor in self?.photoProgress = p } })
            await MainActor.run {
                guard let self, !flag.isSet else { return }
                withAnimation(.bouncy) {
                    self.clusters = result
                    // Only near-identical photos are preselected; look-alikes are the user's call.
                    self.photoSelection = Set(result.filter(\.isNearIdentical).flatMap { c in
                        c.photos.filter { $0.id != c.keeperID }.map(\.id)
                    })
                    self.photosScanning = false
                }
            }
        }
    }

    // MARK: Selection

    func toggleFile(_ file: DuplicateFile, in group: DuplicateGroup) {
        guard file.id != keeperID(group) else { return }
        withAnimation(.snappy) {
            if fileSelection.contains(file.id) { fileSelection.remove(file.id) } else { fileSelection.insert(file.id) }
        }
    }

    func togglePhoto(_ photo: SimilarPhoto, in cluster: PhotoCluster) {
        guard photo.id != keeperID(cluster) else { return }
        withAnimation(.snappy) {
            if photoSelection.contains(photo.id) { photoSelection.remove(photo.id) } else { photoSelection.insert(photo.id) }
        }
    }

    /// Promote a copy to keeper; the old keeper becomes a removable twin.
    func makeKeeper(_ file: DuplicateFile, in group: DuplicateGroup) {
        let old = keeperID(group)
        withAnimation(.bouncy) {
            keeperOverrides[group.id] = file.id
            fileSelection.remove(file.id)
            if let oldFile = group.files.first(where: { $0.id == old }), oldFile.autoSelectable {
                fileSelection.insert(old)
            }
        }
    }

    func makeKeeper(_ photo: SimilarPhoto, in cluster: PhotoCluster) {
        let old = keeperID(cluster)
        withAnimation(.bouncy) {
            keeperOverrides[cluster.id] = photo.id
            photoSelection.remove(photo.id)
            photoSelection.insert(old)
        }
    }

    func selectSuggested() {
        withAnimation(.snappy) {
            switch mode {
            case .files:
                fileSelection = Set(groups.flatMap { g in
                    g.files.filter { $0.id != keeperID(g) && $0.autoSelectable }.map(\.id)
                })
            case .photos:
                photoSelection = Set(clusters.flatMap { c in c.photos.filter { $0.id != keeperID(c) }.map(\.id) })
            }
        }
    }

    func selectNone() {
        withAnimation(.snappy) {
            if mode == .files { fileSelection = [] } else { photoSelection = [] }
        }
    }

    // MARK: Removal

    func trashSelected() {
        let items = selectedItems
        guard !items.isEmpty else { return }
        let noun = mode == .files ? "duplicate" : "photo"
        AppModel.shared.requestTrash(items, title: "Move \(items.count) \(noun)\(items.count == 1 ? "" : "s") to Trash",
                                     source: "duplicates") { [weak self] outcome in
            guard let self else { return }
            let removed = Set(outcome.removed.map(\.id))
            withAnimation(.bouncy) {
                self.groups = self.groups.compactMap { g in g.removing(removed) }
                // Drop overrides whose chosen keeper no longer exists.
                self.keeperOverrides = self.keeperOverrides.filter { !removed.contains($0.value) }
                self.clusters = self.clusters.compactMap { $0.removing(removed) }
                self.fileSelection.subtract(removed)
                self.photoSelection.subtract(removed)
            }
        }
    }
}

/// Cached QuickLook thumbnails for the photo grid.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    init() { cache.countLimit = 600 }

    func image(for url: URL, side: CGFloat = 320) async -> NSImage? {
        let key = "\(url.path)#\(Int(side))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side), scale: 2,
                                                   representationTypes: .thumbnail)
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        let image = rep.nsImage
        cache.setObject(image, forKey: key)
        return image
    }
}
