import Foundation

/// One installed application.
public struct InstalledApp: Identifiable, Sendable, Hashable {
    public let url: URL
    public let name: String
    public let bundleID: String?
    /// True for apps under /System — shown for reference but not uninstallable.
    public let isSystem: Bool

    public var id: String { bundleID ?? url.path }

    public init(url: URL, name: String, bundleID: String?, isSystem: Bool = false) {
        self.url = url
        self.name = name
        self.bundleID = bundleID
        self.isSystem = isSystem
    }
}

/// Index of apps currently installed on the machine, used to decide whether a
/// support/cache folder belongs to something still present or is a leftover.
public struct InstalledApps: Sendable {
    /// Lowercased bundle identifiers of every installed app.
    public let bundleIDs: Set<String>
    /// Lowercased app names (without ".app").
    public let names: Set<String>

    static let appRoots: [URL] = [
        URL(filePath: "/Applications"),
        URL(filePath: "/Applications/Utilities"),
        URL(filePath: "/System/Applications"),
        URL(filePath: "/System/Applications/Utilities"),
        FileSystem.home("Applications"),
    ]

    public static func scan() -> InstalledApps {
        var ids: Set<String> = []
        var names: Set<String> = []
        for app in list() {
            names.insert(app.name.lowercased())
            if let id = app.bundleID { ids.insert(id.lowercased()) }
        }
        return InstalledApps(bundleIDs: ids, names: names)
    }

    /// Full records of every installed app, excluding macOS system apps the
    /// user can't uninstall.
    public static func list() -> [InstalledApp] {
        var apps: [InstalledApp] = []
        var seen: Set<String> = []

        for root in appRoots where FileSystem.exists(root) {
            // System apps live under /System — surface them as info only.
            let isSystem = root.path.hasPrefix("/System")
            guard let enumerator = FileSystem.manager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            while let url = enumerator.nextObject() as? URL {
                guard url.pathExtension == "app" else { continue }
                enumerator.skipDescendants()
                let path = url.standardizedFileURL.path
                guard seen.insert(path).inserted else { continue }
                apps.append(InstalledApp(
                    url: url,
                    name: url.deletingPathExtension().lastPathComponent,
                    bundleID: bundleID(of: url),
                    isSystem: isSystem
                ))
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func bundleID(of appURL: URL) -> String? {
        let plist = appURL.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let obj = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = obj as? [String: Any]
        else { return nil }
        return dict["CFBundleIdentifier"] as? String
    }

    /// True if `identifier` (a folder/file name) plausibly belongs to an
    /// installed app — matched leniently so we never flag something that's
    /// actually present.
    public func isInstalled(_ identifier: String) -> Bool {
        let id = identifier.lowercased()
        if names.contains(id) { return true }
        if bundleIDs.contains(id) { return true }
        // A leftover's id may be a parent/child of an installed id
        // (e.g. "com.google.Chrome.helper" vs "com.google.Chrome").
        for installed in bundleIDs where id.hasPrefix(installed) || installed.hasPrefix(id) {
            return true
        }
        return false
    }
}
