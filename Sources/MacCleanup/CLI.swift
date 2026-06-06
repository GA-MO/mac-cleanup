import Foundation
import CleanupKit

/// Headless entry point: `MacCleanup --scan` runs every scanner and prints a
/// report without launching the GUI. Read-only — it never deletes. Handy for
/// scripting and for verifying the engine from a terminal.
enum CLI {
    static func run() {
        let sem = DispatchSemaphore(value: 0)
        Task {
            await scanAndReport()
            sem.signal()
        }
        sem.wait()
    }

    private static func scanAndReport() async {
        FileHandle.standardError.write(Data("Scanning…\n".utf8))
        let engine = CleanupEngine()
        let items = await engine.scan { _ in }

        let byCat = Dictionary(grouping: items, by: \.category)
        var grand: Int64 = 0

        for category in CleanupCategory.allCases {
            guard let group = byCat[category], !group.isEmpty else { continue }
            let total = CleanupEngine.reclaimable(group)
            grand += total
            print("\n▸ \(category.rawValue) — \(total.formattedSize) (\(group.count) items)")
            for item in group.sorted(by: { $0.size > $1.size }).prefix(10) {
                let badge = item.safety == .safe ? "[safe]   "
                          : item.safety == .review ? "[review] " : "[caution]"
                print("  \(badge) \(item.size.formattedSize.padding(toLength: 10, withPad: " ", startingAt: 0)) \(item.label)")
            }
            if group.count > 10 { print("  … and \(group.count - 10) more") }
        }

        print("\n═══ Total reclaimable: \(grand.formattedSize) across \(items.count) items ═══")
    }
}
