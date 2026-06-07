import Foundation

/// A reclaim action for a developer tool (Docker, Xcode, Go, …). Each maps to
/// the tool's own cleanup command and only shows up when that tool is present.
public struct DevReclaimTask: Identifiable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let detail: String
    public let systemImage: String
    /// Executable that must exist on PATH for this task to be offered.
    public let requiresTool: String
    /// Cleanup command (run via the login shell).
    let command: String
    /// Optional read-only command that prints the reclaimable size, in bytes,
    /// as a plain integer. Used to preview the win before running.
    let estimateCommand: String?

    public init(id: String, title: String, detail: String, systemImage: String,
                requiresTool: String, command: String, estimateCommand: String? = nil) {
        self.id = id; self.title = title; self.detail = detail
        self.systemImage = systemImage; self.requiresTool = requiresTool
        self.command = command; self.estimateCommand = estimateCommand
    }
}

public struct DevReclaimResult: Sendable {
    public let task: DevReclaimTask
    public let succeeded: Bool
    public let output: String
}

/// Frees space used by developer tooling. Every command here removes only
/// regenerable artifacts (build caches, unused images, package caches) — code
/// and projects are never touched.
public enum DevReclaim {

    /// Sum the size (in bytes) of one or more shell-evaluated paths via `du`.
    private static func duBytes(_ pathExpr: String) -> String {
        #"du -sk \#(pathExpr) 2>/dev/null | awk '{s+=$1} END{print s*1024}'"#
    }
    /// awk that turns size tokens like "20.8GB" into bytes and sums them.
    private static let humanToBytesAwk =
        #"{v=$1; n=v; gsub(/[^0-9.].*/,"",n); u=v; gsub(/[0-9.]+/,"",u); m=1; if(u=="GB")m=1000000000; else if(u=="MB")m=1000000; else if(u=="kB"||u=="KB")m=1000; s+=n*m} END{printf "%.0f", s}"#

    public static let allTasks: [DevReclaimTask] = [
        .init(id: "docker", title: "Docker — Prune Build Cache & Images",
              detail: "Removes build cache and unused images (the usual #1 space hog)",
              systemImage: "shippingbox", requiresTool: "docker",
              command: "docker builder prune -af && docker image prune -f && docker system df",
              estimateCommand: #"docker system df --format '{{.Reclaimable}}' 2>/dev/null | awk '\#(humanToBytesAwk)'"#),
        .init(id: "simctl", title: "Xcode — Delete Unavailable Simulators",
              detail: "Removes simulators for runtimes you no longer have",
              systemImage: "iphone", requiresTool: "xcrun",
              command: "xcrun simctl delete unavailable && echo 'Done.'"),
        .init(id: "brew", title: "Homebrew — Clean Up",
              detail: "Removes outdated formula versions and download cache",
              systemImage: "mug", requiresTool: "brew",
              command: "brew cleanup --prune=all",
              estimateCommand: #"brew cleanup --prune=all -n 2>&1 | awk '/approximately/{v=$0; sub(/.*approximately /,"",v); sub(/ of.*/,"",v); n=v; gsub(/[^0-9.].*/,"",n); u=v; gsub(/[0-9.]+/,"",u); m=1; if(u=="GB")m=1000000000; else if(u=="MB")m=1000000; else if(u=="KB"||u=="kB")m=1000; printf "%.0f", n*m}'"#),
        .init(id: "go", title: "Go — Clear Build & Module Cache",
              detail: "Clears the compile cache and downloaded modules",
              systemImage: "g.circle", requiresTool: "go",
              command: "go clean -cache -modcache && echo 'Done.'",
              estimateCommand: duBytes(#""$(go env GOCACHE)" "$(go env GOMODCACHE)""#)),
        .init(id: "npm", title: "npm — Clean Cache",
              detail: "Clears the npm download cache",
              systemImage: "n.circle", requiresTool: "npm",
              command: "npm cache clean --force 2>&1 && echo 'Done.'",
              estimateCommand: duBytes(#""$(npm config get cache)""#)),
        .init(id: "pnpm", title: "pnpm — Prune Store",
              detail: "Removes packages not referenced by any project",
              systemImage: "p.circle", requiresTool: "pnpm",
              command: "pnpm store prune",
              estimateCommand: duBytes(#""$(pnpm store path 2>/dev/null)""#)),
        .init(id: "yarn", title: "Yarn — Clean Cache",
              detail: "Clears the Yarn package cache",
              systemImage: "y.circle", requiresTool: "yarn",
              command: "yarn cache clean && echo 'Done.'",
              estimateCommand: duBytes(#""$(yarn cache dir 2>/dev/null)""#)),
        .init(id: "bun", title: "Bun — Clear Cache",
              detail: "Clears Bun's global install cache (~/.bun/install/cache)",
              systemImage: "b.circle", requiresTool: "bun",
              // `bun pm cache rm` requires a project (package.json); remove the
              // global cache dir directly — Bun recreates it on demand.
              command: #"rm -rf "${BUN_INSTALL_CACHE_DIR:-${BUN_INSTALL:-$HOME/.bun}/install/cache}" && echo 'Done.'"#,
              estimateCommand: duBytes(#""${BUN_INSTALL_CACHE_DIR:-${BUN_INSTALL:-$HOME/.bun}/install/cache}""#)),
        .init(id: "pip", title: "pip — Purge Cache",
              detail: "Clears the pip download/wheel cache",
              systemImage: "ladybug", requiresTool: "pip3",
              command: "pip3 cache purge",
              estimateCommand: duBytes(#""$(pip3 cache dir 2>/dev/null)""#)),
        .init(id: "pod", title: "CocoaPods — Clean Cache",
              detail: "Clears the CocoaPods spec/pod cache",
              systemImage: "p.square", requiresTool: "pod",
              command: "pod cache clean --all && echo 'Done.'",
              estimateCommand: duBytes(#""$HOME/Library/Caches/CocoaPods""#)),
    ]

    /// Tasks whose required tool is installed. Detection runs each lookup
    /// concurrently through the login shell.
    public static func availableTasks() async -> [DevReclaimTask] {
        await withTaskGroup(of: (DevReclaimTask, Bool).self) { group in
            for task in allTasks {
                group.addTask { (task, Shell.hasTool(task.requiresTool)) }
            }
            var available: [DevReclaimTask] = []
            for await (task, ok) in group where ok { available.append(task) }
            let rank = Dictionary(uniqueKeysWithValues: allTasks.enumerated().map { ($1.id, $0) })
            return available.sorted { (rank[$0.id] ?? 0) < (rank[$1.id] ?? 0) }
        }
    }

    /// Reclaimable bytes for a task, or nil if it can't be estimated / is zero.
    public static func estimate(_ task: DevReclaimTask) async -> Int64? {
        guard let cmd = task.estimateCommand else { return nil }
        let out = await withCheckedContinuation { (c: CheckedContinuation<Shell.Output, Never>) in
            DispatchQueue.global(qos: .utility).async { c.resume(returning: Shell.run(cmd)) }
        }
        // Take the last all-digit token to dodge any shell-startup noise.
        let token = out.text.split(whereSeparator: \.isWhitespace)
            .last { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
        guard let token, let bytes = Int64(token), bytes > 0 else { return nil }
        return bytes
    }

    public static func run(_ task: DevReclaimTask) async -> DevReclaimResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let out = Shell.run(task.command)
                continuation.resume(returning: DevReclaimResult(
                    task: task, succeeded: out.succeeded, output: out.text))
            }
        }
    }
}
