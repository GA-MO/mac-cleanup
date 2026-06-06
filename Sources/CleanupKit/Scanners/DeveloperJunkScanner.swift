import Foundation

/// Finds reclaimable space from developer tooling: build artifacts that
/// regenerate, package-manager caches, and stale `node_modules`.
public struct DeveloperJunkScanner: Scanner {
    public let category: CleanupCategory = .developerJunk

    /// Roots to search for project build folders (`node_modules`, `target`, …).
    let projectRoots: [URL]
    /// Only flag `node_modules`/build dirs whose project wasn't touched within
    /// this window. Keeps active projects out of the results.
    let staleAfter: TimeInterval

    public init(
        projectRoots: [URL]? = nil,
        staleAfterDays: Int = 30
    ) {
        self.projectRoots = projectRoots ?? [
            FileSystem.home("Development"),
            FileSystem.home("Developer"),
            FileSystem.home("Projects"),
            FileSystem.home("Code"),
            FileSystem.home("src"),
        ].filter(FileSystem.exists)
        self.staleAfter = TimeInterval(staleAfterDays) * 86_400
    }

    /// Fixed caches that are always safe to clear — they re-download on demand.
    private var fixedCaches: [(path: URL, label: String)] {
        [
            (FileSystem.home("Library/Developer/Xcode/DerivedData"), "Xcode DerivedData"),
            (FileSystem.home("Library/Developer/Xcode/iOS DeviceSupport"), "iOS DeviceSupport"),
            (FileSystem.home("Library/Developer/CoreSimulator/Caches"), "CoreSimulator Caches"),
            (FileSystem.home(".npm/_cacache"), "npm cache"),
            (FileSystem.home(".yarn/cache"), "Yarn cache"),
            (FileSystem.home("Library/Caches/pnpm"), "pnpm store"),
            (FileSystem.home("Library/Caches/pip"), "pip cache"),
            (FileSystem.home("Library/Caches/Homebrew"), "Homebrew cache"),
            (FileSystem.home(".gradle/caches"), "Gradle cache"),
            (FileSystem.home(".cargo/registry/cache"), "Cargo registry cache"),
            (FileSystem.home("go/pkg/mod/cache"), "Go module cache"),
        ]
    }

    /// Build-artifact directory names worth reclaiming, keyed to the marker
    /// file that proves the parent is a real project of that type.
    private static let buildDirs: [(dir: String, marker: String)] = [
        ("node_modules", "package.json"),
        ("target",       "Cargo.toml"),     // Rust
        (".next",        "package.json"),
        ("dist",         "package.json"),
        ("build",        "package.json"),
        (".gradle",      "build.gradle"),
    ]

    public func scan(report: @Sendable (CleanupItem) -> Void) async {
        for cache in fixedCaches where FileSystem.exists(cache.path) {
            let size = FileSystem.size(of: cache.path)
            guard size > 0 else { continue }
            report(CleanupItem(
                url: cache.path,
                size: size,
                category: category,
                safety: .safe,
                label: cache.label,
                detail: "Regenerates automatically"
            ))
        }

        for root in projectRoots {
            scanProjects(under: root, report: report)
        }
    }

    /// Walk a projects root looking for build dirs, but don't descend into a
    /// build dir once found (no point enumerating node_modules internals).
    private func scanProjects(under root: URL, report: @Sendable (CleanupItem) -> Void) {
        guard let enumerator = FileSystem.manager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let now = Date()
        for case let url as URL in enumerator {
            guard FileSystem.isDirectory(url) else { continue }
            let name = url.lastPathComponent

            guard let spec = Self.buildDirs.first(where: { $0.dir == name }) else { continue }
            enumerator.skipDescendants()

            let projectDir = url.deletingLastPathComponent()
            guard FileSystem.exists(projectDir.appending(path: spec.marker)) else { continue }

            // Staleness is judged by the project's source, not the build dir.
            let projModified = FileSystem.modificationDate(of: projectDir.appending(path: spec.marker))
                ?? FileSystem.modificationDate(of: projectDir)
            let age = projModified.map { now.timeIntervalSince($0) } ?? .greatestFiniteMagnitude
            let isStale = age >= staleAfter

            let size = FileSystem.size(of: url)
            guard size > 0 else { continue }

            report(CleanupItem(
                url: url,
                size: size,
                category: category,
                safety: isStale ? .safe : .review,
                label: "\(name) · \(projectDir.lastPathComponent)",
                detail: isStale
                    ? "Project idle \(Self.ageString(age))"
                    : "Active — rebuild needed if removed",
                lastModified: projModified
            ))
        }
    }

    static func ageString(_ interval: TimeInterval) -> String {
        let days = Int(interval / 86_400)
        if days >= 365 { return "\(days / 365)y ago" }
        if days >= 30  { return "\(days / 30)mo ago" }
        return "\(days)d ago"
    }
}
