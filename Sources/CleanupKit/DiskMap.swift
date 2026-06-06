import Foundation

/// A node in the disk-usage tree. Immutable and `Sendable` so it can cross
/// actor boundaries to the UI. Children below the display threshold are rolled
/// up into a single synthetic "Other" node.
public struct DiskNode: Identifiable, Sendable, Hashable {
    public let id: String          // standardized path (unique)
    public let name: String
    public let url: URL?           // nil for the synthetic "Other" aggregate
    public let size: Int64
    public let isDirectory: Bool
    public let children: [DiskNode]

    public var isAggregate: Bool { url == nil }
}

/// Builds a bounded disk-usage tree for visualization (treemap / list).
public enum DiskMap {

    /// Build the tree rooted at `url`. Recurses to `maxDepth`; directories
    /// deeper than that are summarized by their total size only. Children
    /// smaller than `minSize` are aggregated so the map stays legible.
    public static func build(
        at url: URL,
        maxDepth: Int = 3,
        minSize: Int64 = 50_000_000
    ) -> DiskNode {
        build(at: url, depth: 0, maxDepth: maxDepth, minSize: minSize)
    }

    private static func build(at url: URL, depth: Int, maxDepth: Int, minSize: Int64) -> DiskNode {
        let path = url.standardizedFileURL.path
        let name = url.lastPathComponent

        guard FileSystem.isDirectory(url) else {
            return DiskNode(id: path, name: name, url: url,
                            size: FileSystem.size(of: url),
                            isDirectory: false, children: [])
        }

        // At the depth limit, report the subtree's size without listing it.
        guard depth < maxDepth else {
            return DiskNode(id: path, name: name, url: url,
                            size: FileSystem.size(of: url),
                            isDirectory: true, children: [])
        }

        let childNodes = FileSystem.children(of: url)
            .map { build(at: $0, depth: depth + 1, maxDepth: maxDepth, minSize: minSize) }
        let total = childNodes.reduce(Int64(0)) { $0 + $1.size }

        // Keep the big children; aggregate the long tail into "Other".
        let big = childNodes.filter { $0.size >= minSize }
            .sorted { $0.size > $1.size }
        let remainder = total - big.reduce(Int64(0)) { $0 + $1.size }

        var display = big
        if remainder > 0 {
            display.append(DiskNode(id: path + "/·other", name: "Other",
                                    url: nil, size: remainder,
                                    isDirectory: true, children: []))
        }

        return DiskNode(id: path, name: name, url: url, size: total,
                        isDirectory: true, children: display)
    }
}
