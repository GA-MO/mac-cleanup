import Foundation

/// A source of cleanable items. Each scanner owns one slice of the cleanup
/// surface (developer junk, caches, …) and reports what it finds.
public protocol Scanner: Sendable {
    var category: CleanupCategory { get }
    /// Scan and return found items. Should never throw on a single unreadable
    /// path — skip and continue. `report` is called as items stream in so the
    /// UI can show progress.
    func scan(report: @Sendable (CleanupItem) -> Void) async
}

public extension Scanner {
    /// Convenience: collect everything into an array.
    func scanAll() async -> [CleanupItem] {
        let box = ItemBox()
        await scan { box.append($0) }
        return box.items
    }
}

/// Thread-safe collector used by `scanAll` and the engine.
final class ItemBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [CleanupItem] = []
    var items: [CleanupItem] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
    func append(_ item: CleanupItem) {
        lock.lock(); defer { lock.unlock() }
        storage.append(item)
    }
}
