import Foundation

/// Result of removing one item.
public struct RemovalResult: Sendable {
    public let item: CleanupItem
    public let succeeded: Bool
    public let error: String?
    /// Where the item went in Trash (nil on dry-run or failure).
    public let trashedTo: URL?

    /// Recoverable items are those actually trashed (not dry-run) whose Trash
    /// location we know.
    public var canRestore: Bool { succeeded && trashedTo != nil }
}

/// Result of restoring one previously-removed item.
public struct RestoreResult: Sendable {
    public let originalURL: URL
    public let succeeded: Bool
    public let error: String?
}

/// Orchestrates the scanners and performs deletions. The single rule: nothing
/// is ever destroyed — items are moved to the Trash so the user can recover.
public actor CleanupEngine {
    private let scanners: [any Scanner]

    public init(scanners: [any Scanner]? = nil) {
        self.scanners = scanners ?? [
            DeveloperJunkScanner(),
            CacheScanner(),
            AppLeftoverScanner(),
            LargeFileScanner(),
            DuplicateScanner(),
            DownloadsScanner(),
        ]
    }

    /// Run every scanner concurrently, streaming items via `onItem` as they're
    /// found. Returns the full list when done.
    public func scan(onItem: @Sendable @escaping (CleanupItem) -> Void) async -> [CleanupItem] {
        let box = ItemBox()
        await withTaskGroup(of: Void.self) { group in
            for scanner in scanners {
                group.addTask {
                    await scanner.scan { item in
                        box.append(item)
                        onItem(item)
                    }
                }
            }
        }
        return Self.deduped(box.items)
    }

    /// Collapse items that point at the same path (different scanners can claim
    /// the same dir, e.g. a package cache under ~/Library/Caches). The earliest
    /// category in `allCases` wins, so the more specific label is kept and the
    /// total isn't inflated by double counting.
    static func deduped(_ items: [CleanupItem]) -> [CleanupItem] {
        let priority = Dictionary(
            uniqueKeysWithValues: CleanupCategory.allCases.enumerated().map { ($1, $0) })
        var best: [String: CleanupItem] = [:]
        for item in items {
            let key = item.url.standardizedFileURL.path
            guard let existing = best[key] else { best[key] = item; continue }
            if (priority[item.category] ?? .max) < (priority[existing.category] ?? .max) {
                best[key] = item
            }
        }
        return Array(best.values)
    }

    /// Move the given items to Trash. When `dryRun` is true, computes what
    /// *would* happen without touching the filesystem — always preview first.
    public func remove(_ items: [CleanupItem], dryRun: Bool) -> [RemovalResult] {
        items.map { item in
            guard FileSystem.exists(item.url) else {
                return RemovalResult(item: item, succeeded: false,
                                     error: "No longer exists", trashedTo: nil)
            }
            if dryRun {
                return RemovalResult(item: item, succeeded: true, error: nil, trashedTo: nil)
            }
            do {
                var trashURL: NSURL?
                try FileManager.default.trashItem(at: item.url, resultingItemURL: &trashURL)
                return RemovalResult(item: item, succeeded: true, error: nil,
                                     trashedTo: trashURL as URL?)
            } catch {
                return RemovalResult(item: item, succeeded: false,
                                     error: error.localizedDescription, trashedTo: nil)
            }
        }
    }

    /// Move trashed items back to their original locations — the in-app Undo.
    /// Works as long as the Trash hasn't been emptied since removal.
    public func restore(_ results: [RemovalResult]) -> [RestoreResult] {
        results.compactMap { result -> RestoreResult? in
            guard result.canRestore, let trashed = result.trashedTo else { return nil }
            let destination = result.item.url
            do {
                // The original parent should still exist, but recreate it to be safe.
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                guard !FileSystem.exists(destination) else {
                    return RestoreResult(originalURL: destination, succeeded: false,
                                         error: "Something already exists at the original path")
                }
                try FileManager.default.moveItem(at: trashed, to: destination)
                return RestoreResult(originalURL: destination, succeeded: true, error: nil)
            } catch {
                return RestoreResult(originalURL: destination, succeeded: false,
                                     error: error.localizedDescription)
            }
        }
    }

    public static func reclaimable(_ items: [CleanupItem]) -> Int64 {
        items.reduce(0) { $0 + $1.size }
    }
}
