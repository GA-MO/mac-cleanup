import Foundation

/// A one-shot system maintenance command.
public struct MaintenanceTask: Identifiable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let detail: String
    public let systemImage: String
    /// Requires administrator privileges (prompts for password when run).
    public let needsAdmin: Bool
    /// Shell command to execute. Kept quote-free so it survives AppleScript
    /// wrapping for the admin path.
    let command: String
}

public struct MaintenanceResult: Sendable {
    public let task: MaintenanceTask
    public let succeeded: Bool
    public let output: String
}

/// Runs safe, well-known macOS maintenance commands. Nothing here deletes user
/// data — these flush caches and rebuild system indexes.
public enum Maintenance {

    public static let tasks: [MaintenanceTask] = [
        .init(id: "dns", title: "Flush DNS Cache",
              detail: "Clears resolver cache — fixes stale domain lookups",
              systemImage: "network", needsAdmin: true,
              command: "dscacheutil -flushcache; killall -HUP mDNSResponder"),
        .init(id: "purge", title: "Free Up Memory",
              detail: "Purges inactive memory (runs `purge`)",
              systemImage: "memorychip", needsAdmin: true,
              command: "purge"),
        .init(id: "spotlight", title: "Rebuild Spotlight Index",
              detail: "Re-indexes the boot volume — fixes broken search",
              systemImage: "magnifyingglass.circle", needsAdmin: true,
              command: "mdutil -E /"),
        .init(id: "fontcache", title: "Clear Font Caches",
              detail: "Removes font caches — fixes garbled text rendering",
              systemImage: "textformat", needsAdmin: true,
              command: "atsutil databases -remove"),
        .init(id: "lsregister", title: "Rebuild Launch Services",
              detail: "Fixes duplicate / wrong 'Open With' entries",
              systemImage: "arrow.triangle.2.circlepath", needsAdmin: false,
              command: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user"),
    ]

    public static func run(_ task: MaintenanceTask) async -> MaintenanceResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = execute(task)
                continuation.resume(returning: result)
            }
        }
    }

    private static func execute(_ task: MaintenanceTask) -> MaintenanceResult {
        let process = Process()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        if task.needsAdmin {
            // AppleScript shows the native admin prompt; no helper tool needed.
            let escaped = task.command.replacingOccurrences(of: "\"", with: "\\\"")
            process.executableURL = URL(filePath: "/usr/bin/osascript")
            process.arguments = ["-e", "do shell script \"\(escaped)\" with administrator privileges"]
        } else {
            process.executableURL = URL(filePath: "/bin/zsh")
            process.arguments = ["-c", task.command]
        }

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(data: data, encoding: .utf8) ?? ""
            return MaintenanceResult(task: task, succeeded: process.terminationStatus == 0,
                                     output: output.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return MaintenanceResult(task: task, succeeded: false,
                                     output: error.localizedDescription)
        }
    }
}
