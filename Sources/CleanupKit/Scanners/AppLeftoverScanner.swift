import Foundation

/// Finds support files left behind by apps that are no longer installed.
/// Deliberately conservative: it only flags reverse-DNS bundle-id folders that
/// match no installed app, never Apple/system identifiers, and always marks
/// results as Caution so they're never auto-selected.
public struct AppLeftoverScanner: Scanner {
    public let category: CleanupCategory = .appLeftovers

    let apps: InstalledApps
    /// Directories to scan and the filename suffix (if any) that marks an entry
    /// as bundle-id-named. Injectable for testing.
    let locations: [LeftoverLocation]

    public struct LeftoverLocation: Sendable {
        public let url: URL
        public let suffix: String?
        public init(url: URL, suffix: String? = nil) {
            self.url = url
            self.suffix = suffix
        }
    }

    private static var defaultLocations: [LeftoverLocation] {
        [
            .init(url: FileSystem.home("Library/Application Support")),
            .init(url: FileSystem.home("Library/Containers")),
            .init(url: FileSystem.home("Library/Caches")),
            .init(url: FileSystem.home("Library/Saved Application State"), suffix: ".savedState"),
            .init(url: FileSystem.home("Library/HTTPStorages")),
            .init(url: FileSystem.home("Library/Preferences"), suffix: ".plist"),
        ]
    }

    /// Identifier prefixes we never touch — system and Apple-owned state.
    private static let protectedPrefixes = [
        "com.apple.", "apple", "group.com.apple.",
    ]
    /// Non-bundle-id folders that are framework/shared, not per-app leftovers.
    private static let protectedNames: Set<String> = [
        "crashreporter", "mobilesync", "appstore", "cloudkit",
        "knowledge", "com.apple", "google",   // Google has shared dirs across products
    ]

    public init(apps: InstalledApps? = nil, locations: [LeftoverLocation]? = nil) {
        self.apps = apps ?? InstalledApps.scan()
        self.locations = locations ?? Self.defaultLocations
    }

    public func scan(report: @Sendable (CleanupItem) -> Void) async {
        for loc in locations where FileSystem.exists(loc.url) {
            for child in FileSystem.children(of: loc.url) {
                var identifier = child.lastPathComponent
                if let suffix = loc.suffix {
                    guard identifier.hasSuffix(suffix) else { continue }
                    identifier = String(identifier.dropLast(suffix.count))
                }

                guard isLikelyOrphan(identifier) else { continue }

                let size = FileSystem.size(of: child)
                guard size > 100_000 else { continue }   // ignore tiny stragglers

                report(CleanupItem(
                    url: child,
                    size: size,
                    category: category,
                    safety: .caution,
                    label: identifier,
                    detail: "No installed app matches — verify before removing",
                    lastModified: FileSystem.modificationDate(of: child)
                ))
            }
        }
    }

    /// Only reverse-DNS identifiers (≥2 dots) that aren't protected and don't
    /// match an installed app. The dot requirement keeps us off plain folders
    /// like "Adobe" or "Microsoft" that span many products.
    private func isLikelyOrphan(_ identifier: String) -> Bool {
        let lower = identifier.lowercased()
        guard identifier.filter({ $0 == "." }).count >= 2 else { return false }
        if Self.protectedPrefixes.contains(where: { lower.hasPrefix($0) }) { return false }
        if Self.protectedNames.contains(where: { lower.hasPrefix($0) }) { return false }
        return !apps.isInstalled(identifier)
    }
}
