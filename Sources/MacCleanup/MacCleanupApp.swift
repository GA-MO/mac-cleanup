import SwiftUI
import AppKit

/// Top-level entry. Routes to the headless scanner when invoked with `--scan`,
/// otherwise launches the SwiftUI app.
@main
enum Entry {
    static func main() {
        if CommandLine.arguments.contains("--scan") {
            CLI.run()
        } else {
            MacCleanupApp.main()
        }
    }
}

struct MacCleanupApp: App {
    @State private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("Mac Cleanup", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 580)
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra("Mac Cleanup", systemImage: "sparkles") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
    }
}

/// Ensures the window comes to the front when launched via Finder / `open`.
/// SwiftUI apps bundled outside Xcode don't always self-activate.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
