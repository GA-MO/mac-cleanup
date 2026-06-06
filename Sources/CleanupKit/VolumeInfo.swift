import Foundation

/// Free / total capacity of the boot volume, for the menu-bar readout and
/// low-space warnings.
public struct VolumeInfo: Sendable {
    public let free: Int64
    public let total: Int64

    public var used: Int64 { total - free }
    public var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    /// True when free space is low enough to nudge the user to clean up.
    public var isLow: Bool { total > 0 && Double(free) / Double(total) < 0.10 }

    public static func current() -> VolumeInfo? {
        let url = URL(filePath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey,
        ]) else { return nil }

        let free = values.volumeAvailableCapacityForImportantUsage ?? 0
        let total = Int64(values.volumeTotalCapacity ?? 0)
        guard total > 0 else { return nil }
        return VolumeInfo(free: Int64(free), total: total)
    }
}
