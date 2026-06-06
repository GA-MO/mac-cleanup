import Foundation

/// Runs commands through the user's login shell so developer tools resolve
/// correctly. A GUI app launched from Finder gets a minimal PATH; sourcing the
/// login + interactive shell picks up Homebrew, nvm, cargo, etc.
public enum Shell {

    public struct Output: Sendable {
        public let status: Int32
        public let text: String
        public var succeeded: Bool { status == 0 }
    }

    /// Execute `command` via `zsh -ilc` and return its combined output.
    public static func run(_ command: String) -> Output {
        let process = Process()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.executableURL = URL(filePath: "/bin/zsh")
        // -i -l so both ~/.zshrc (nvm, etc.) and ~/.zprofile (brew) are sourced.
        process.arguments = ["-i", "-l", "-c", command]

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(data: data, encoding: .utf8) ?? ""
            return Output(status: process.terminationStatus,
                          text: text.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return Output(status: -1, text: error.localizedDescription)
        }
    }

    /// True if `tool` is found on the login shell's PATH.
    public static func hasTool(_ tool: String) -> Bool {
        run("command -v \(tool) >/dev/null 2>&1").succeeded
    }
}
