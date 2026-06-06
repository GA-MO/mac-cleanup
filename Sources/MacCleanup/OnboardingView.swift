import SwiftUI
import AppKit

/// First-run welcome shown over the main window. Introduces the tools, states
/// the safety guarantee, and offers a shortcut to grant Full Disk Access.
struct OnboardingView: View {
    let onDone: () -> Void

    private struct Feature: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let blurb: String
    }

    private let features: [Feature] = [
        .init(icon: "sparkles", title: "Cleanup",
              blurb: "Caches, logs, dev junk, large files & duplicates"),
        .init(icon: "chevron.left.forwardslash.chevron.right", title: "Developer Reclaim",
              blurb: "One-click cache cleanup for Docker, npm, Go & more"),
        .init(icon: "trash.square", title: "Uninstaller",
              blurb: "Remove an app and every file it left behind"),
        .init(icon: "chart.pie", title: "Disk Map",
              blurb: "See what's eating space with a visual treemap"),
        .init(icon: "wrench.and.screwdriver", title: "Maintenance",
              blurb: "Flush DNS, free memory, rebuild system indexes"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                Text("Welcome to Mac Cleanup")
                    .font(.largeTitle.bold())
                Text("Reclaim disk space safely — five tools in one app.")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 36)
            .padding(.bottom, 24)

            VStack(spacing: 14) {
                ForEach(features) { f in
                    HStack(spacing: 14) {
                        Image(systemName: f.icon)
                            .font(.title2)
                            .foregroundStyle(.tint)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(f.title).font(.headline)
                            Text(f.blurb).font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 44)

            // Safety guarantee — the most important reassurance.
            Label {
                Text("Nothing is deleted permanently. Everything goes to the Trash, and you can undo any cleanup.")
            } icon: {
                Image(systemName: "lock.shield.fill").foregroundStyle(.green)
            }
            .font(.callout)
            .padding(14)
            .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 44)
            .padding(.top, 22)

            Spacer(minLength: 16)

            HStack(spacing: 12) {
                Button("Grant Full Disk Access") { openFullDiskAccess() }
                Button("Get Started", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(.bottom, 28)

            Text("For complete results, grant Full Disk Access — some system caches are otherwise hidden.")
                .font(.caption2).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)
                .padding(.bottom, 24)
        }
        .frame(width: 540, height: 680)
    }

    private func openFullDiskAccess() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }
}
