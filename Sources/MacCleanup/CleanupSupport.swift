import SwiftUI
import AppKit
import Foundation
import CleanupKit

/// Trash helpers. Moving items to the Trash doesn't free disk space until the
/// Trash is emptied, so the UI offers explicit review + empty actions.
enum TrashSupport {
    private static var trashURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".Trash")
    }

    static func size() -> Int64 { FileSystem.size(of: trashURL) }

    /// Open the Trash in Finder so the user can review or "Put Back" items.
    static func open() { NSWorkspace.shared.open(trashURL) }

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

/// Shown after a cleanup. Surfaces items that couldn't be removed, offers an
/// Undo (restore from Trash), and explains/handles reclaiming space by emptying
/// the Trash — the two are opposites, so both paths are made explicit.
struct PostCleanFooter: View {
    let failures: [RemovalResult]
    /// How many items were just moved to the Trash. Drives the empty-Trash
    /// prompt even when ~/.Trash can't be measured (it needs Full Disk Access).
    var trashedItems: Int = 0
    /// Restore-from-Trash action; nil when nothing can be undone. Returns a
    /// summary to display.
    var onUndo: (() async -> String)? = nil

    @State private var trashBytes: Int64 = 0
    @State private var emptying = false
    @State private var emptied = false
    @State private var confirmEmpty = false
    @State private var undoing = false
    @State private var undoSummary: String?

    var body: some View {
        VStack(spacing: 12) {
            if !failures.isEmpty { failureBox }
            if onUndo != nil { undoSection }
            trashSection
        }
        .frame(maxWidth: 480)
        .task { trashBytes = TrashSupport.size() }
        .confirmationDialog("Empty the Trash?", isPresented: $confirmEmpty, titleVisibility: .visible) {
            Button("Empty Trash — Permanent", role: .destructive) {
                Task {
                    emptying = true
                    emptied = await TrashSupport.empty()
                    emptying = false
                    if emptied { trashBytes = 0 }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes everything in your Trash — including items from other apps. It cannot be undone and Undo / Put Back will no longer work.")
        }
    }

    private var failureBox: some View {
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

    @ViewBuilder
    private var undoSection: some View {
        if let undoSummary {
            Label(undoSummary, systemImage: "arrow.uturn.backward.circle.fill")
                .font(.callout).foregroundStyle(.green)
        } else if let onUndo {
            Button {
                Task {
                    undoing = true
                    undoSummary = await onUndo()
                    undoing = false
                    trashBytes = TrashSupport.size()   // restored items leave the Trash
                }
            } label: {
                if undoing { ProgressView().controlSize(.small) }
                else { Label("Undo — Restore Files", systemImage: "arrow.uturn.backward") }
            }
            .disabled(undoing)
        }
    }

    /// Show the empty-Trash prompt whenever we actually trashed something, or
    /// can see the Trash is non-empty.
    private var showTrashSection: Bool { trashedItems > 0 || trashBytes > 0 }

    @ViewBuilder
    private var trashSection: some View {
        if emptied {
            Label("Trash emptied — space reclaimed", systemImage: "checkmark.circle.fill")
                .font(.callout).foregroundStyle(.green)
        } else if showTrashSection {
            VStack(spacing: 8) {
                Text(trashBytes > 0
                     ? "Moved items sit in the Trash and still use \(trashBytes.formattedSize). Review them first, or empty the Trash to reclaim the space."
                     : "Moved items sit in the Trash and still use space until it's emptied. Review them first, or empty the Trash to reclaim the space.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    Button { TrashSupport.open() } label: {
                        Label("Open Trash", systemImage: "trash")
                    }
                    Button(role: .destructive) { confirmEmpty = true } label: {
                        if emptying { ProgressView().controlSize(.small) }
                        else if trashBytes > 0 { Label("Empty Trash (\(trashBytes.formattedSize))", systemImage: "trash.fill") }
                        else { Label("Empty Trash", systemImage: "trash.fill") }
                    }
                    .disabled(emptying)
                }
            }
        }
    }
}
