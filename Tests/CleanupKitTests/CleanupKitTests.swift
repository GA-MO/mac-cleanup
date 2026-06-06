import Testing
import Foundation
@testable import CleanupKit

/// Builds a throwaway directory tree under a temp dir, cleaned up after use.
private func withTempTree(_ body: (URL) async throws -> Void) async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "cleanup-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try await body(root)
}

private func write(_ url: URL, bytes: Int) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 0x41, count: bytes).write(to: url)
}

@Test func sizeOfDirectoryIsRecursive() async throws {
    try await withTempTree { root in
        try write(root.appending(path: "a.bin"), bytes: 1000)
        try write(root.appending(path: "sub/b.bin"), bytes: 2000)
        let size = FileSystem.size(of: root)
        #expect(size >= 3000)   // allocated size rounds up, so >=
    }
}

@Test func formattedSizeIsHumanReadable() {
    #expect(Int64(1_500_000).formattedSize.contains("MB"))
}

@Test func developerJunkFindsNodeModules() async throws {
    try await withTempTree { root in
        // A project: package.json + node_modules with content.
        try write(root.appending(path: "myapp/package.json"), bytes: 100)
        try write(root.appending(path: "myapp/node_modules/dep/index.js"), bytes: 5000)

        let scanner = DeveloperJunkScanner(projectRoots: [root], staleAfterDays: 30)
        let items = await scanner.scanAll()

        let nodeModules = items.first { $0.label.contains("node_modules") }
        #expect(nodeModules != nil)
        #expect(nodeModules?.url.lastPathComponent == "node_modules")
    }
}

@Test func developerJunkIgnoresNodeModulesWithoutPackageJson() async throws {
    try await withTempTree { root in
        // node_modules but NO package.json marker — must be skipped.
        try write(root.appending(path: "stray/node_modules/x.js"), bytes: 5000)
        let scanner = DeveloperJunkScanner(projectRoots: [root])
        let items = await scanner.scanAll()
        #expect(items.allSatisfy { !$0.label.contains("node_modules") })
    }
}

@Test func largeFileScannerRespectsMinSize() async throws {
    try await withTempTree { root in
        try write(root.appending(path: "big.bin"), bytes: 2_000_000)
        try write(root.appending(path: "small.bin"), bytes: 1000)

        let scanner = LargeFileScanner(searchRoots: [root], minSizeMB: 1)
        let items = await scanner.scanAll()

        #expect(items.contains { $0.label == "big.bin" })
        #expect(!items.contains { $0.label == "small.bin" })
        // Personal files must never be auto-selected.
        #expect(items.allSatisfy { $0.safety == .caution })
    }
}

@Test func duplicateScannerGroupsIdenticalContent() async throws {
    try await withTempTree { root in
        for sub in ["one", "two", "three"] {
            try FileManager.default.createDirectory(
                at: root.appending(path: sub), withIntermediateDirectories: true)
        }
        let payload = Data(repeating: 0x7A, count: 6_000_000)
        try payload.write(to: root.appending(path: "one/file.bin"))
        try payload.write(to: root.appending(path: "two/file.bin"))
        try Data(repeating: 0x00, count: 6_000_000).write(to: root.appending(path: "three/other.bin"))

        let scanner = DuplicateScanner(searchRoots: [root], minSizeMB: 1)
        let items = await scanner.scanAll()

        // Two identical files form one group; the unique file is not reported.
        #expect(items.count == 2)
        let groups = Set(items.compactMap(\.groupKey))
        #expect(groups.count == 1)
        // Exactly one keeper, one removable.
        #expect(items.filter { $0.safety == .review }.count == 1)
        #expect(items.filter { $0.safety == .safe }.count == 1)
    }
}

@Test func downloadsScannerFlagsInstallersAndStaleFiles() async throws {
    try await withTempTree { root in
        try write(root.appending(path: "App.dmg"), bytes: 2_000_000)
        try write(root.appending(path: "recent.txt"), bytes: 2_000_000)

        // Backdate an old file beyond the stale window.
        let old = root.appending(path: "old.bin")
        try write(old, bytes: 2_000_000)
        let past = Date(timeIntervalSinceNow: -90 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: old.path)

        let scanner = DownloadsScanner(downloads: root, staleAfterDays: 60)
        let items = await scanner.scanAll()

        let dmg = items.first { $0.url.lastPathComponent == "App.dmg" }
        #expect(dmg?.safety == .safe)                       // installer → safe
        #expect(items.contains { $0.url.lastPathComponent == "old.bin" })   // stale → flagged
        #expect(!items.contains { $0.url.lastPathComponent == "recent.txt" }) // recent → ignored
    }
}

@Test func appLeftoverScannerFlagsOrphansOnly() async throws {
    try await withTempTree { root in
        let support = root.appending(path: "Application Support")
        // Orphan: reverse-DNS id with no matching installed app.
        try write(support.appending(path: "com.ghost.OldApp/data.bin"), bytes: 500_000)
        // Installed: matches the apps index.
        try write(support.appending(path: "com.live.Keeper/data.bin"), bytes: 500_000)
        // Apple-owned: always protected.
        try write(support.appending(path: "com.apple.Something/data.bin"), bytes: 500_000)
        // Plain name (not reverse-DNS): never flagged.
        try write(support.appending(path: "Adobe/data.bin"), bytes: 500_000)

        let apps = InstalledApps(bundleIDs: ["com.live.keeper"], names: [])
        let scanner = AppLeftoverScanner(
            apps: apps,
            locations: [.init(url: support)]
        )
        let items = await scanner.scanAll()
        let labels = Set(items.map(\.label))

        #expect(labels.contains("com.ghost.OldApp"))
        #expect(!labels.contains("com.live.Keeper"))
        #expect(!labels.contains("com.apple.Something"))
        #expect(!labels.contains("Adobe"))
        #expect(items.allSatisfy { $0.safety == .caution })   // never auto-selected
    }
}

@Test func installedAppsMatchingIsLenient() {
    let apps = InstalledApps(bundleIDs: ["com.google.chrome"], names: ["my app"])
    #expect(apps.isInstalled("com.google.Chrome"))           // case-insensitive
    #expect(apps.isInstalled("com.google.Chrome.helper"))    // child id
    #expect(apps.isInstalled("My App"))                      // by name
    #expect(!apps.isInstalled("com.ghost.removed"))
}

@Test func dedupedKeepsHigherPriorityCategoryPerPath() {
    let url = URL(filePath: "/tmp/shared/cache")
    let devJunk = CleanupItem(url: url, size: 100, category: .developerJunk,
                              safety: .safe, label: "Homebrew cache")
    let cache = CleanupItem(url: url, size: 100, category: .cachesAndLogs,
                            safety: .safe, label: "Homebrew · cache")
    let other = CleanupItem(url: URL(filePath: "/tmp/other"), size: 50,
                            category: .cachesAndLogs, safety: .safe, label: "other")

    let result = CleanupEngine.deduped([cache, devJunk, other])

    #expect(result.count == 2)                                  // shared path collapsed
    let shared = result.first { $0.url == url }
    #expect(shared?.category == .developerJunk)                 // earlier category wins
    #expect(CleanupEngine.reclaimable(result) == 150)           // not double-counted
}

@Test func uninstallerMatchesBundleIdAndName() {
    let app = InstalledApp(url: URL(filePath: "/Applications/Acme.app"),
                           name: "Acme", bundleID: "com.acme.App")
    #expect(Uninstaller.matches("com.acme.App", app: app))          // exact id
    #expect(Uninstaller.matches("com.acme.App.Updater", app: app))  // child id
    #expect(Uninstaller.matches("Acme", app: app))                  // by name
    #expect(!Uninstaller.matches("com.acme.Apple", app: app))       // dot boundary guard
    #expect(!Uninstaller.matches("com.other.App", app: app))
}

@Test func uninstallerFootprintGathersRelatedFiles() throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "uninstall-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }

    let appURL = root.appending(path: "Acme.app")
    try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
    let support = root.appending(path: "Application Support")
    let prefs = root.appending(path: "Preferences")
    try write(support.appending(path: "com.acme.App/state.bin"), bytes: 4000)
    try write(prefs.appending(path: "com.acme.App.plist"), bytes: 1000)
    try write(prefs.appending(path: "com.other.App.plist"), bytes: 1000)  // unrelated

    let app = InstalledApp(url: appURL, name: "Acme", bundleID: "com.acme.App")
    let fp = Uninstaller.footprint(of: app, specs: [
        (support, nil), (prefs, ".plist"),
    ])

    #expect(fp.relatedItems.count == 2)   // support dir + matching plist, not the other
    #expect(fp.allItems.count == 3)       // including the .app bundle
    #expect(fp.relatedItems.allSatisfy { $0.url.lastPathComponent.contains("acme") || $0.url.lastPathComponent.contains("com.acme") })
}

@Test func maintenanceTasksAreWellFormed() {
    #expect(!Maintenance.tasks.isEmpty)
    #expect(Set(Maintenance.tasks.map(\.id)).count == Maintenance.tasks.count)  // unique ids
    #expect(Maintenance.tasks.contains { $0.id == "dns" && $0.needsAdmin })
}

@Test func diskMapAggregatesSmallChildren() async throws {
    try await withTempTree { root in
        try write(root.appending(path: "big/a.bin"), bytes: 80_000_000)
        try write(root.appending(path: "tiny/b.bin"), bytes: 1000)
        try write(root.appending(path: "tiny2/c.bin"), bytes: 1000)

        let node = DiskMap.build(at: root, maxDepth: 2, minSize: 50_000_000)

        #expect(node.isDirectory)
        #expect(node.size >= 80_000_000)
        // "big" stays; the two tiny dirs collapse into one "Other".
        #expect(node.children.contains { $0.name == "big" })
        #expect(node.children.contains { $0.isAggregate && $0.name == "Other" })
    }
}

@Test func treemapTilesCoverAreaProportionally() {
    let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
    let tiles = Treemap.layout([
        ("a", 50.0), ("b", 30.0), ("c", 20.0), ("zero", 0.0),
    ], in: rect)

    #expect(tiles.count == 3)   // zero-weight dropped
    // Total tiled area ≈ container area (10,000), proportions preserved.
    let totalArea = tiles.reduce(0.0) { $0 + Double($1.rect.width * $1.rect.height) }
    #expect(abs(totalArea - 10_000) < 1.0)
    let a = tiles.first { $0.id == "a" }!
    let c = tiles.first { $0.id == "c" }!
    let aArea = Double(a.rect.width * a.rect.height)
    let cArea = Double(c.rect.width * c.rect.height)
    #expect(abs(aArea / cArea - 2.5) < 0.01)   // 50 vs 20 → 2.5×
    // Every tile stays inside the container.
    #expect(tiles.allSatisfy { rect.contains($0.rect) || rect.union($0.rect) == rect })
}

@Test func devReclaimTasksAreWellFormed() {
    #expect(!DevReclaim.allTasks.isEmpty)
    #expect(Set(DevReclaim.allTasks.map(\.id)).count == DevReclaim.allTasks.count)
    #expect(DevReclaim.allTasks.allSatisfy { !$0.requiresTool.isEmpty && !$0.command.isEmpty })
    #expect(DevReclaim.allTasks.contains { $0.id == "docker" && $0.requiresTool == "docker" })
}

@Test func shellResolvesABasicTool() {
    // The login shell should always find a core utility like `ls`.
    #expect(Shell.hasTool("ls"))
    #expect(!Shell.hasTool("definitely-not-a-real-tool-xyz"))
}

@Test func removeThenRestoreRoundTripsViaTrash() async throws {
    try await withTempTree { root in
        let file = root.appending(path: "restore-me.bin")
        try write(file, bytes: 2000)
        let item = CleanupItem(url: file, size: 2000, category: .cachesAndLogs,
                               safety: .safe, label: "restore-me")

        let engine = CleanupEngine()
        let removed = await engine.remove([item], dryRun: false)
        #expect(removed.first?.canRestore == true)
        #expect(!FileManager.default.fileExists(atPath: file.path))   // gone to Trash

        let restored = await engine.restore(removed)
        #expect(restored.first?.succeeded == true)
        #expect(FileManager.default.fileExists(atPath: file.path))    // back at origin
    }
}

@Test func removeDryRunDoesNotDeleteFiles() async throws {
    try await withTempTree { root in
        let file = root.appending(path: "victim.bin")
        try write(file, bytes: 1000)
        let item = CleanupItem(url: file, size: 1000, category: .cachesAndLogs,
                               safety: .safe, label: "victim")

        let engine = CleanupEngine()
        let results = await engine.remove([item], dryRun: true)

        #expect(results.first?.succeeded == true)
        #expect(FileManager.default.fileExists(atPath: file.path))   // still there
    }
}
