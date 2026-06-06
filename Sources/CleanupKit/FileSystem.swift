import Foundation

/// Filesystem helpers shared by all scanners. Kept dependency-free so the
/// whole thing stays unit-testable.
public enum FileSystem {
    // FileManager.default is safe for the read-only operations used here.
    nonisolated(unsafe) static let manager = FileManager.default

    /// Recursive size of a file or directory, in bytes. Uses allocated size
    /// when available so it matches what Finder reports.
    public static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [
            .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
            .fileSizeKey, .isDirectoryKey, .isRegularFileKey,
        ]

        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }

        if values.isRegularFile == true {
            return Int64(values.totalFileAllocatedSize
                ?? values.fileAllocatedSize
                ?? values.fileSize
                ?? 0)
        }

        guard values.isDirectory == true,
              let enumerator = manager.enumerator(
                at: url,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
              )
        else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let v = try? fileURL.resourceValues(forKeys: keys),
                  v.isRegularFile == true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? v.fileSize ?? 0)
        }
        return total
    }

    public static func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    public static func exists(_ url: URL) -> Bool {
        manager.fileExists(atPath: url.path)
    }

    public static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    /// Immediate children of a directory (non-recursive). Empty if unreadable.
    public static func children(of url: URL, includingHidden: Bool = false) -> [URL] {
        let opts: FileManager.DirectoryEnumerationOptions =
            includingHidden ? [] : [.skipsHiddenFiles]
        return (try? manager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: opts
        )) ?? []
    }

    /// Expands a `~`-relative path to an absolute URL under the user's home.
    public static func home(_ relative: String) -> URL {
        manager.homeDirectoryForCurrentUser.appending(path: relative, directoryHint: .inferFromPath)
    }
}
