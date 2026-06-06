import Foundation

/// Everything an app has scattered across the system: the bundle plus its
/// support files, caches, preferences, containers, and launch agents.
public struct AppFootprint: Sendable {
    public let app: InstalledApp
    /// The `.app` bundle itself.
    public let appItem: CleanupItem
    /// Associated files found elsewhere (support, caches, prefs, …).
    public let relatedItems: [CleanupItem]

    public var allItems: [CleanupItem] { [appItem] + relatedItems }
    public var totalSize: Int64 { CleanupEngine.reclaimable(allItems) }
}

/// Builds the full footprint of an installed app so it can be removed
/// completely — the bundle and every leftover in one pass.
public enum Uninstaller {

    /// `(directory, suffix)` pairs to search. `suffix` non-nil means entries
    /// are files named `<id><suffix>`; nil means directories named `<id>`.
    private static var searchSpecs: [(url: URL, suffix: String?)] {
        [
            (FileSystem.home("Library/Application Support"), nil),
            (FileSystem.home("Library/Caches"), nil),
            (FileSystem.home("Library/Containers"), nil),
            (FileSystem.home("Library/Group Containers"), nil),
            (FileSystem.home("Library/HTTPStorages"), nil),
            (FileSystem.home("Library/WebKit"), nil),
            (FileSystem.home("Library/Logs"), nil),
            (FileSystem.home("Library/Preferences"), ".plist"),
            (FileSystem.home("Library/Saved Application State"), ".savedState"),
            (FileSystem.home("Library/LaunchAgents"), ".plist"),
            (FileSystem.home("Library/Cookies"), ".binarycookies"),
        ]
    }

    public static func footprint(of app: InstalledApp,
                                 specs: [(url: URL, suffix: String?)]? = nil) -> AppFootprint {
        let appItem = CleanupItem(
            url: app.url,
            size: FileSystem.size(of: app.url),
            category: .appLeftovers,
            safety: .review,
            label: app.name,
            detail: app.bundleID,
            lastModified: FileSystem.modificationDate(of: app.url)
        )

        var related: [CleanupItem] = []
        for spec in (specs ?? searchSpecs) where FileSystem.exists(spec.url) {
            for child in FileSystem.children(of: spec.url) {
                var ident = child.lastPathComponent
                if let suffix = spec.suffix {
                    guard ident.hasSuffix(suffix) else { continue }
                    ident = String(ident.dropLast(suffix.count))
                }
                guard matches(ident, app: app) else { continue }

                let size = FileSystem.size(of: child)
                related.append(CleanupItem(
                    url: child,
                    size: size,
                    category: .appLeftovers,
                    safety: .review,
                    label: child.lastPathComponent,
                    detail: spec.url.lastPathComponent,
                    lastModified: FileSystem.modificationDate(of: child)
                ))
            }
        }
        return AppFootprint(app: app, appItem: appItem, relatedItems: related)
    }

    /// An entry belongs to the app if its name matches the bundle id (exact or
    /// dotted child like `com.x.App.helper`) or the app's name.
    static func matches(_ identifier: String, app: InstalledApp) -> Bool {
        let id = identifier.lowercased()
        if let bundle = app.bundleID?.lowercased() {
            if id == bundle { return true }
            // Child id: "com.acme.App.Updater" — but require a dot boundary so
            // "com.acme.Apple" doesn't match "com.acme.App".
            if id.hasPrefix(bundle + ".") { return true }
        }
        if id == app.name.lowercased() { return true }
        return false
    }
}
