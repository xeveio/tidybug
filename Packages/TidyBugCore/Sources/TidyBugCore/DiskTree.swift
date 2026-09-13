import Foundation

/// A node in the disk map. Built once on a background thread, then only read.
public final class DiskNode: Identifiable, @unchecked Sendable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
    public let name: String
    public let path: String
    public let isDirectory: Bool
    /// Synthetic node that stands for many small files.
    public let isAggregate: Bool
    public internal(set) var size: Int64
    public internal(set) var fileCount: Int
    public internal(set) var children: [DiskNode] = []
    public internal(set) var unreadable = false
    public internal(set) weak var parent: DiskNode?

    init(name: String, path: String, isDirectory: Bool, isAggregate: Bool = false, size: Int64 = 0, fileCount: Int = 0) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.isAggregate = isAggregate
        self.size = size
        self.fileCount = fileCount
    }

    public var url: URL { URL(fileURLWithPath: path) }

    public var ancestors: [DiskNode] {
        var chain: [DiskNode] = []
        var n: DiskNode? = self
        while let c = n { chain.insert(c, at: 0); n = c.parent }
        return chain
    }

    /// Remove a child after it was deleted, propagating the size change upward.
    public func remove(_ child: DiskNode) {
        guard let i = children.firstIndex(where: { $0 === child }) else { return }
        children.remove(at: i)
        var n: DiskNode? = self
        while let c = n {
            c.size -= child.size
            c.fileCount -= child.fileCount
            n = c.parent
        }
    }
}

public struct ScanProgress: Sendable {
    public var bytes: Int64
    public var files: Int
    public var currentPath: String
}

public enum DiskTreeBuilder {
    /// Files at least this big get their own node; smaller ones are folded.
    static let fileThreshold: Int64 = 4 << 20
    /// Directories smaller than this keep no children (saves memory on huge trees).
    static let collapseThreshold: Int64 = 1 << 20

    public static func build(
        root: String,
        isCancelled: @escaping () -> Bool = { Task.isCancelled },
        progress: (ScanProgress) -> Void
    ) -> DiskNode? {
        var stack: [(node: DiskNode, small: Int64, smallCount: Int)] = []
        var seen = Set<FileID>()
        var result: DiskNode?
        var totalBytes: Int64 = 0
        var totalFiles = 0
        var counter = 0

        FileWalker.walk(root) { e in
            counter += 1
            if counter & 0xFFF == 0 {
                if isCancelled() { return .stop }
                progress(ScanProgress(bytes: totalBytes, files: totalFiles, currentPath: e.path))
            }
            switch e.kind {
            case .directory:
                let node = DiskNode(name: e.level == 0 ? (root as NSString).lastPathComponent : e.name,
                                    path: e.path, isDirectory: true, size: e.allocatedSize)
                stack.append((node, 0, 0))
            case .directoryEnd:
                guard let top = stack.popLast() else { return .proceed }
                let node = top.node
                if top.small > 0 {
                    if node.children.isEmpty {
                        // Nothing big inside: the folder is just its files.
                    } else {
                        let agg = DiskNode(name: "\(top.smallCount) smaller files", path: node.path,
                                           isDirectory: false, isAggregate: true,
                                           size: top.small, fileCount: top.smallCount)
                        agg.parent = node
                        node.children.append(agg)
                    }
                }
                if node.size < collapseThreshold {
                    node.children.removeAll()
                } else {
                    node.children.sort { $0.size > $1.size }
                }
                if let parentIndex = stack.indices.last {
                    let parent = stack[parentIndex].node
                    node.parent = parent
                    parent.children.append(node)
                    parent.size += node.size
                    parent.fileCount += node.fileCount
                } else {
                    result = node
                }
            case .unreadable:
                if e.level == 0 { return .stop }
                if let parent = stack.last?.node {
                    let node = DiskNode(name: e.name, path: e.path, isDirectory: true)
                    node.unreadable = true
                    node.parent = parent
                    parent.children.append(node)
                }
            case .file, .symlink, .other:
                guard let i = stack.indices.last else { return .proceed }
                if e.linkCount > 1, !seen.insert(e.fileID).inserted { return .proceed }
                let size = e.allocatedSize
                totalBytes += size
                totalFiles += 1
                let parent = stack[i].node
                parent.size += size
                parent.fileCount += 1
                if size >= fileThreshold {
                    let node = DiskNode(name: e.name, path: e.path, isDirectory: false, size: size, fileCount: 1)
                    node.parent = parent
                    parent.children.append(node)
                } else {
                    stack[i].small += size
                    stack[i].smallCount += 1
                }
            }
            return .proceed
        }
        progress(ScanProgress(bytes: totalBytes, files: totalFiles, currentPath: root))
        return isCancelled() ? nil : result
    }
}
