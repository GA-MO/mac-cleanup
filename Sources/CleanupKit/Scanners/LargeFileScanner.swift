import Foundation

/// Finds large and/or old files in user folders so big space hogs surface
/// without manually digging through Finder.
public struct LargeFileScanner: Scanner {
    public let category: CleanupCategory = .largeFiles

    let searchRoots: [URL]
    let minSize: Int64
    /// Files older than this are flagged "old" even if not huge.
    let oldAfter: TimeInterval
    let maxResults: Int

    public init(
        searchRoots: [URL]? = nil,
        minSizeMB: Int = 100,
        oldAfterDays: Int = 180,
        maxResults: Int = 200
    ) {
        self.searchRoots = searchRoots ?? [
            FileSystem.home("Downloads"),
            FileSystem.home("Documents"),
            FileSystem.home("Desktop"),
            FileSystem.home("Movies"),
        ].filter(FileSystem.exists)
        self.minSize = Int64(minSizeMB) * 1_000_000
        self.oldAfter = TimeInterval(oldAfterDays) * 86_400
        self.maxResults = maxResults
    }

    public func scan(report: @Sendable (CleanupItem) -> Void) async {
        let now = Date()
        var found: [CleanupItem] = []

        for root in searchRoots {
            guard let enumerator = FileSystem.manager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            // nextObject() loop — NSEnumerator's for-in iterator is unavailable
            // from async contexts under Swift 6 concurrency checking.
            while let url = enumerator.nextObject() as? URL {
                guard let v = try? url.resourceValues(forKeys: [
                    .isRegularFileKey, .fileSizeKey, .contentModificationDateKey,
                ]), v.isRegularFile == true else { continue }

                let size = Int64(v.fileSize ?? 0)
                let modified = v.contentModificationDate
                let age = modified.map { now.timeIntervalSince($0) } ?? 0
                let isOld = age >= oldAfter

                guard size >= minSize else { continue }

                let detailBits = [
                    isOld ? "Old (\(Int(age / 86_400))d)" : nil,
                    "in \(root.lastPathComponent)",
                ].compactMap { $0 }

                found.append(CleanupItem(
                    url: url,
                    size: size,
                    category: category,
                    // Personal files: never auto-select, always make the user look.
                    safety: .caution,
                    label: url.lastPathComponent,
                    detail: detailBits.joined(separator: " · "),
                    lastModified: modified
                ))
            }
        }

        // Biggest first, capped — report only the top offenders.
        for item in found.sorted(by: { $0.size > $1.size }).prefix(maxResults) {
            report(item)
        }
    }
}
