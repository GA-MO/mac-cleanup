import Foundation

/// Surfaces clutter in ~/Downloads: installer packages that have served their
/// purpose, and files that have sat untouched for a long time.
public struct DownloadsScanner: Scanner {
    public let category: CleanupCategory = .downloads

    let downloads: URL
    /// Files older than this (and not installers) are flagged as stale.
    let staleAfter: TimeInterval

    /// Extensions that are almost always disposable once installed/extracted.
    private static let installerExtensions: Set<String> =
        ["dmg", "pkg", "iso"]
    private static let archiveExtensions: Set<String> =
        ["zip", "gz", "tar", "tgz", "bz2", "xz"]

    public init(downloads: URL? = nil, staleAfterDays: Int = 60) {
        self.downloads = downloads ?? FileSystem.home("Downloads")
        self.staleAfter = TimeInterval(staleAfterDays) * 86_400
    }

    public func scan(report: @Sendable (CleanupItem) -> Void) async {
        guard FileSystem.exists(downloads) else { return }
        let now = Date()

        for url in FileSystem.children(of: downloads) {
            let ext = url.pathExtension.lowercased()
            let size = FileSystem.size(of: url)
            guard size > 0 else { continue }

            let modified = FileSystem.modificationDate(of: url)
            let age = modified.map { now.timeIntervalSince($0) } ?? 0

            let kind: (label: String, safety: SafetyLevel, detail: String)?
            if Self.installerExtensions.contains(ext) {
                kind = ("Installer · \(url.lastPathComponent)", .safe,
                        "Disk image/installer — safe to remove after installing")
            } else if Self.archiveExtensions.contains(ext) {
                kind = ("Archive · \(url.lastPathComponent)", .review,
                        "Downloaded archive — usually safe once extracted")
            } else if age >= staleAfter {
                kind = (url.lastPathComponent, .review,
                        "Untouched for \(Int(age / 86_400)) days")
            } else {
                kind = nil   // recent, non-installer file — leave it alone
            }

            guard let k = kind else { continue }
            report(CleanupItem(
                url: url,
                size: size,
                category: category,
                safety: k.safety,
                label: k.label,
                detail: k.detail,
                lastModified: modified
            ))
        }
    }
}
