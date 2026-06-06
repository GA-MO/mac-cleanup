import Foundation

/// Finds user caches and logs. Caches are always safe (apps rebuild them);
/// logs are flagged for review since you may want recent ones for debugging.
public struct CacheScanner: Scanner {
    public let category: CleanupCategory = .cachesAndLogs

    /// Cache/log roots whose immediate children each become an item, so the
    /// user can clear per-app rather than all-or-nothing.
    private var roots: [(url: URL, safety: SafetyLevel, kind: String)] {
        [
            (FileSystem.home("Library/Caches"),         .safe,   "cache"),
            (FileSystem.home("Library/Logs"),           .review, "logs"),
            (FileSystem.home("Library/Application Support/CrashReporter"), .safe, "crash reports"),
        ]
    }

    /// Caches we never touch — clearing these logs you out or breaks running apps.
    private static let protected: Set<String> = [
        "com.apple.containermanagerd",
        "CloudKit",
        "com.apple.HomeKit",
    ]

    public func scan(report: @Sendable (CleanupItem) -> Void) async {
        for root in roots where FileSystem.exists(root.url) {
            for child in FileSystem.children(of: root.url) {
                let name = child.lastPathComponent
                guard !Self.protected.contains(name) else { continue }

                let size = FileSystem.size(of: child)
                guard size > 1_000_000 else { continue }   // ignore sub-1MB noise

                let modified = FileSystem.modificationDate(of: child)
                report(CleanupItem(
                    url: child,
                    size: size,
                    category: category,
                    safety: root.safety,
                    label: "\(name) · \(root.kind)",
                    detail: modified.map { "Last used \(Self.relativeDate($0))" },
                    lastModified: modified
                ))
            }
        }
    }

    static func relativeDate(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}
