import Foundation
import Observation
import CleanupKit

/// A category and its items, identified by category for SwiftUI lists.
struct CategoryGroup: Identifiable {
    let category: CleanupCategory
    let items: [CleanupItem]
    var id: CleanupCategory { category }
}

/// Phase of the scan/clean lifecycle, drives which UI is shown.
enum ScanPhase: Equatable {
    case idle
    case scanning
    case results
    case cleaning
    case done(reclaimed: Int64, failures: Int)
}

/// Single source of truth for the UI. Owns the engine, the found items, and
/// the user's selection.
@MainActor
@Observable
final class AppModel {
    private let engine = CleanupEngine()

    var phase: ScanPhase = .idle
    /// All items found, keyed by id for stable selection.
    private(set) var items: [CleanupItem] = []
    /// IDs the user has chosen to clean.
    var selection: Set<UUID> = []
    /// Log of the most recent removal, kept so the user can undo it.
    var lastResults: [RemovalResult] = []

    /// True while the last cleanup can still be reversed from the Trash.
    var canUndo: Bool { lastResults.contains { $0.canRestore } }

    /// Items grouped by category for the sidebar, with stable category order.
    /// A struct (not a tuple) so SwiftUI `ForEach(id:)` key paths work.
    var byCategory: [CategoryGroup] {
        CleanupCategory.allCases.compactMap { cat in
            let group = items.filter { $0.category == cat }
                .sorted { $0.size > $1.size }
            return group.isEmpty ? nil : CategoryGroup(category: cat, items: group)
        }
    }

    var totalFound: Int64 { CleanupEngine.reclaimable(items) }
    var selectedItems: [CleanupItem] { items.filter { selection.contains($0.id) } }
    var selectedSize: Int64 { CleanupEngine.reclaimable(selectedItems) }

    func sizeOfCategory(_ cat: CleanupCategory) -> Int64 {
        CleanupEngine.reclaimable(items.filter { $0.category == cat })
    }

    // MARK: - Actions

    func startScan() async {
        guard phase != .scanning, phase != .cleaning else { return }
        items = []
        selection = []
        phase = .scanning

        let found = await engine.scan { [weak self] item in
            Task { @MainActor in self?.appendLive(item) }
        }
        // Reconcile with the streamed list (covers any races) and auto-select safe items.
        items = found
        selection = Set(found.filter { $0.safety == .safe }.map(\.id))
        phase = .results
    }

    private func appendLive(_ item: CleanupItem) {
        guard phase == .scanning else { return }
        items.append(item)
        if item.safety == .safe { selection.insert(item.id) }
    }

    func toggle(_ item: CleanupItem) {
        if selection.contains(item.id) { selection.remove(item.id) }
        else { selection.insert(item.id) }
    }

    func selectAll(in cat: CleanupCategory) {
        for item in items where item.category == cat { selection.insert(item.id) }
    }

    func deselectAll(in cat: CleanupCategory) {
        for item in items where item.category == cat { selection.remove(item.id) }
    }

    /// Preview what would be removed without touching disk.
    func previewClean() async -> [RemovalResult] {
        await engine.remove(selectedItems, dryRun: true)
    }

    func performClean() async {
        guard !selection.isEmpty else { return }
        let target = selectedItems
        phase = .cleaning
        let results = await engine.remove(target, dryRun: false)
        lastResults = results

        let reclaimed = results.filter(\.succeeded).reduce(Int64(0)) { $0 + $1.item.size }
        let failures = results.filter { !$0.succeeded }.count

        // Drop successfully-removed items from the list.
        let removedIDs = Set(results.filter(\.succeeded).map { $0.item.id })
        items.removeAll { removedIDs.contains($0.id) }
        selection.subtract(removedIDs)

        phase = .done(reclaimed: reclaimed, failures: failures)
    }

    /// Move the last cleanup's items back out of the Trash. Returns a summary.
    func undo() async -> String {
        let restored = await engine.restore(lastResults)
        let ok = restored.filter(\.succeeded).count
        let failed = restored.count - ok
        lastResults = []   // can't undo twice
        return "Restored \(ok) item(s) to their original locations"
            + (failed > 0 ? " · \(failed) couldn't be restored" : "")
    }

    func reset() {
        phase = .idle
        items = []
        selection = []
        lastResults = []
    }
}
