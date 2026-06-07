import SwiftUI
import Foundation
import CleanupKit

/// Trash helpers. Moving items to the Trash doesn't free disk space until the
/// Trash is emptied, so the UI offers an explicit empty action.
enum TrashSupport {
    static func size() -> Int64 {
        FileSystem.size(of: FileManager.default.homeDirectoryForCurrentUser.appending(path: ".Trash"))
    }

    /// Empty the Trash via Finder. Permanent — gate behind a confirmation.
    static func empty() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(filePath: "/usr/bin/osascript")
                process.arguments = ["-e", "tell application \"Finder\" to empty trash"]
                try? process.run()
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus == 0)
            }
        }
    }
}

/// Shown after a cleanup: explains why moved items don't free space yet, offers
/// to empty the Trash, and surfaces any items that couldn't be removed.
struct PostCleanFooter: View {
    let failures: [RemovalResult]

    @State private var trashBytes: Int64 = 0
    @State private var emptying = false
    @State private var emptied = false
    @State private var confirmEmpty = false

    var body: some View {
        VStack(spacing: 12) {
            if !failures.isEmpty {
                VStack(spacing: 3) {
                    Label("\(failures.count) item(s) couldn't be removed",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.callout.weight(.medium)).foregroundStyle(.orange)
                    if let first = failures.first?.error {
                        Text(first).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Text("In-use files (e.g. a running browser) or system caches that need Full Disk Access.")
                        .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(10)
                .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }

            if emptied {
                Label("Trash emptied — space reclaimed", systemImage: "checkmark.circle.fill")
                    .font(.callout).foregroundStyle(.green)
            } else if trashBytes > 0 {
                VStack(spacing: 6) {
                    Text("Moved items sit in the Trash and still use \(trashBytes.formattedSize). Empty the Trash to actually reclaim the space.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button {
                        confirmEmpty = true
                    } label: {
                        if emptying { ProgressView().controlSize(.small) }
                        else { Label("Empty Trash (\(trashBytes.formattedSize))", systemImage: "trash") }
                    }
                    .disabled(emptying)
                }
            }
        }
        .frame(maxWidth: 460)
        .task { trashBytes = TrashSupport.size() }
        .confirmationDialog("Empty the Trash?", isPresented: $confirmEmpty, titleVisibility: .visible) {
            Button("Empty Trash", role: .destructive) {
                Task {
                    emptying = true
                    emptied = await TrashSupport.empty()
                    emptying = false
                    if emptied { trashBytes = 0 }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes everything in your Trash — including items from other apps.")
        }
    }
}
