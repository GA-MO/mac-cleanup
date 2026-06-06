import Foundation

/// How risky it is to delete an item. Drives UI color + whether it's
/// auto-selected for cleanup.
public enum SafetyLevel: Int, Sendable, Comparable, Codable {
    /// Regenerated automatically, always safe to remove (caches, derived data).
    case safe = 0
    /// Usually safe but may cost rebuild time or could be wanted (old logs, big downloads).
    case review = 1
    /// User must look before deleting (large personal files, duplicates).
    case caution = 2

    public static func < (lhs: SafetyLevel, rhs: SafetyLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Top-level grouping shown in the sidebar.
public enum CleanupCategory: String, Sendable, CaseIterable, Codable {
    case developerJunk = "Developer Junk"
    case cachesAndLogs = "Caches & Logs"
    case appLeftovers  = "App Leftovers"
    case largeFiles    = "Large & Old Files"
    case duplicates    = "Duplicates"
    case downloads     = "Downloads & Installers"

    public var systemImage: String {
        switch self {
        case .developerJunk: "hammer.fill"
        case .cachesAndLogs: "doc.text.fill"
        case .appLeftovers:  "app.dashed"
        case .largeFiles:    "externaldrive.fill"
        case .duplicates:    "doc.on.doc.fill"
        case .downloads:     "arrow.down.circle.fill"
        }
    }
}

/// One thing that can be cleaned. A file or a directory tree.
public struct CleanupItem: Identifiable, Sendable, Hashable, Codable {
    public let id: UUID
    public let url: URL
    /// Total size in bytes (recursive for directories).
    public let size: Int64
    public let category: CleanupCategory
    public let safety: SafetyLevel
    /// Short human label, e.g. "node_modules · my-app".
    public let label: String
    /// Optional extra context, e.g. "Last modified 8 months ago".
    public let detail: String?
    public let lastModified: Date?
    /// Items sharing a groupKey are duplicates/related (used by duplicate finder).
    public let groupKey: String?

    public init(
        id: UUID = UUID(),
        url: URL,
        size: Int64,
        category: CleanupCategory,
        safety: SafetyLevel,
        label: String,
        detail: String? = nil,
        lastModified: Date? = nil,
        groupKey: String? = nil
    ) {
        self.id = id
        self.url = url
        self.size = size
        self.category = category
        self.safety = safety
        self.label = label
        self.detail = detail
        self.lastModified = lastModified
        self.groupKey = groupKey
    }
}

public extension Int64 {
    /// "1.2 GB" style formatting.
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
