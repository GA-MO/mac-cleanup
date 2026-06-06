import Foundation

/// Finds browsing data (history, cookies, caches) for installed browsers so it
/// can be cleared for privacy. Clearing cookies signs you out, so items are
/// never auto-selected, and everything goes to the Trash (recoverable).
public struct BrowserPrivacyScanner: Scanner {
    public let category: CleanupCategory = .privacy

    /// A browser and the locations of its profile data.
    public struct Browser: Sendable {
        let name: String
        /// Application Support base (Chromium-family) — profiles live inside.
        let supportBase: URL?
        /// Cache base in ~/Library/Caches.
        let cacheBase: URL?
        /// Fixed files (used by Safari, which isn't profile-structured here).
        let fixedHistory: [URL]
        let fixedCookies: [URL]
        let isChromium: Bool

        public init(name: String, supportBase: URL?, cacheBase: URL?,
                    fixedHistory: [URL], fixedCookies: [URL], isChromium: Bool) {
            self.name = name; self.supportBase = supportBase; self.cacheBase = cacheBase
            self.fixedHistory = fixedHistory; self.fixedCookies = fixedCookies
            self.isChromium = isChromium
        }
    }

    let browsers: [Browser]

    public init(browsers: [Browser]? = nil) {
        self.browsers = browsers ?? Self.knownBrowsers
    }

    static var knownBrowsers: [Browser] {
        func chromium(_ name: String, _ support: String, _ cache: String) -> Browser {
            Browser(name: name,
                    supportBase: FileSystem.home("Library/Application Support/\(support)"),
                    cacheBase: FileSystem.home("Library/Caches/\(cache)"),
                    fixedHistory: [], fixedCookies: [], isChromium: true)
        }
        return [
            chromium("Google Chrome", "Google/Chrome", "Google/Chrome"),
            chromium("Brave", "BraveSoftware/Brave-Browser", "BraveSoftware/Brave-Browser"),
            chromium("Microsoft Edge", "Microsoft Edge", "Microsoft Edge"),
            chromium("Arc", "Arc", "Arc"),
            chromium("Vivaldi", "Vivaldi", "Vivaldi"),
            Browser(name: "Firefox",
                    supportBase: FileSystem.home("Library/Application Support/Firefox/Profiles"),
                    cacheBase: FileSystem.home("Library/Caches/Firefox"),
                    fixedHistory: [], fixedCookies: [], isChromium: false),
            Browser(name: "Safari",
                    supportBase: nil,
                    cacheBase: FileSystem.home("Library/Caches/com.apple.Safari"),
                    fixedHistory: [FileSystem.home("Library/Safari/History.db")],
                    fixedCookies: [FileSystem.home("Library/Cookies/Cookies.binarycookies")],
                    isChromium: false),
        ]
    }

    public func scan(report: @Sendable (CleanupItem) -> Void) async {
        for browser in browsers {
            emit(for: browser, report: report)
        }
    }

    private func emit(for browser: Browser, report: @Sendable (CleanupItem) -> Void) {
        let key = "priv-\(browser.name)"

        func item(_ url: URL, kind: String, safety: SafetyLevel, note: String) {
            guard FileSystem.exists(url) else { return }
            let size = FileSystem.size(of: url)
            report(CleanupItem(
                url: url, size: size, category: category, safety: safety,
                label: "\(browser.name) — \(kind)",
                detail: "\(note) · quit \(browser.name) first",
                lastModified: FileSystem.modificationDate(of: url),
                groupKey: key))
        }

        // Chromium family: one set of files per profile directory.
        if browser.isChromium, let base = browser.supportBase, FileSystem.exists(base) {
            for profile in chromiumProfiles(in: base) {
                let label = profile.lastPathComponent
                item(profile.appending(path: "History"),
                     kind: "History (\(label))", safety: .review, note: "Clears browsing history")
                // Newer Chrome stores cookies under Network/.
                let cookies = profile.appending(path: "Network/Cookies")
                item(FileSystem.exists(cookies) ? cookies : profile.appending(path: "Cookies"),
                     kind: "Cookies (\(label))", safety: .caution, note: "Signs you out of sites")
            }
        }

        // Firefox: each Profiles/* dir holds places.sqlite (history) + cookies.sqlite.
        if browser.name == "Firefox", let base = browser.supportBase, FileSystem.exists(base) {
            for profile in FileSystem.children(of: base) where FileSystem.isDirectory(profile) {
                item(profile.appending(path: "places.sqlite"),
                     kind: "History", safety: .review, note: "Clears browsing history")
                item(profile.appending(path: "cookies.sqlite"),
                     kind: "Cookies", safety: .caution, note: "Signs you out of sites")
            }
        }

        // Fixed-path browsers (Safari).
        for url in browser.fixedHistory {
            item(url, kind: "History", safety: .review, note: "Clears browsing history")
        }
        for url in browser.fixedCookies {
            item(url, kind: "Cookies", safety: .caution, note: "Signs you out of sites")
        }

        // Cache is always safe to clear.
        if let cache = browser.cacheBase {
            item(cache, kind: "Cache", safety: .safe, note: "Frees space, rebuilds on demand")
        }
    }

    /// Chromium profile dirs: "Default" plus any "Profile N".
    private func chromiumProfiles(in base: URL) -> [URL] {
        FileSystem.children(of: base).filter {
            let n = $0.lastPathComponent
            return FileSystem.isDirectory($0) && (n == "Default" || n.hasPrefix("Profile "))
        }
    }
}
