import Foundation
import CryptoKit

/// Finds duplicate files by content. Three-stage funnel keeps it fast on big
/// trees: group by size → compare a cheap head hash → confirm with a full
/// hash. Only files that pass all three are reported as duplicates.
public struct DuplicateScanner: Scanner {
    public let category: CleanupCategory = .duplicates

    let searchRoots: [URL]
    let minSize: Int64

    public init(searchRoots: [URL]? = nil, minSizeMB: Int = 5) {
        self.searchRoots = searchRoots ?? [
            FileSystem.home("Downloads"),
            FileSystem.home("Documents"),
            FileSystem.home("Desktop"),
            FileSystem.home("Pictures"),
        ].filter(FileSystem.exists)
        self.minSize = Int64(minSizeMB) * 1_000_000
    }

    public func scan(report: @Sendable (CleanupItem) -> Void) async {
        // Stage 1: bucket candidate files by exact size.
        var bySize: [Int64: [URL]] = [:]
        for root in searchRoots {
            guard let enumerator = FileSystem.manager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            // nextObject() loop — NSEnumerator's for-in iterator is unavailable
            // from async contexts under Swift 6 concurrency checking.
            while let url = enumerator.nextObject() as? URL {
                guard let v = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                      v.isRegularFile == true else { continue }
                let size = Int64(v.fileSize ?? 0)
                guard size >= minSize else { continue }
                bySize[size, default: []].append(url)
            }
        }

        // Stages 2 & 3: only sizes with collisions are worth hashing.
        for (size, urls) in bySize where urls.count > 1 {
            var byContent: [String: [URL]] = [:]
            for url in urls {
                guard let head = Self.headHash(of: url) else { continue }
                byContent[head, default: []].append(url)
            }

            for (_, sameHead) in byContent where sameHead.count > 1 {
                var byFull: [String: [URL]] = [:]
                for url in sameHead {
                    guard let full = Self.fullHash(of: url) else { continue }
                    byFull[full, default: []].append(url)
                }

                for (digest, dupes) in byFull where dupes.count > 1 {
                    reportGroup(dupes, size: size, digest: digest, report: report)
                }
            }
        }
    }

    /// Emit a duplicate set. The oldest copy is treated as the "keeper"
    /// (safety .review) and the rest as removable (safety .safe), so the
    /// default selection frees space without losing the file entirely.
    private func reportGroup(
        _ urls: [URL],
        size: Int64,
        digest: String,
        report: @Sendable (CleanupItem) -> Void
    ) {
        let sorted = urls.sorted {
            (FileSystem.modificationDate(of: $0) ?? .distantFuture)
                < (FileSystem.modificationDate(of: $1) ?? .distantFuture)
        }
        let groupKey = "dup-\(digest.prefix(12))"
        for (idx, url) in sorted.enumerated() {
            let isKeeper = idx == 0
            report(CleanupItem(
                url: url,
                size: size,
                category: category,
                safety: isKeeper ? .review : .safe,
                label: url.lastPathComponent,
                detail: isKeeper
                    ? "Keep (oldest copy) · \(url.deletingLastPathComponent().lastPathComponent)/"
                    : "Duplicate · \(url.deletingLastPathComponent().lastPathComponent)/",
                lastModified: FileSystem.modificationDate(of: url),
                groupKey: groupKey
            ))
        }
    }

    /// Hash of the first 64KB — cheap discriminator before reading whole files.
    private static func headHash(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 65_536) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Full-content SHA-256, streamed so large files don't blow up memory.
    private static func fullHash(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
