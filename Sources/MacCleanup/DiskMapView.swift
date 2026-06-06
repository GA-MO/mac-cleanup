import SwiftUI
import AppKit
import CleanupKit

@MainActor
@Observable
final class DiskMapModel {
    var root: DiskNode?
    /// Drill-down path; last element is what's currently shown.
    var stack: [DiskNode] = []
    var building = false
    /// The folder the current map was built from (for refresh after deletes).
    private(set) var scannedRoot: URL?

    var current: DiskNode? { stack.last ?? root }

    func build(at url: URL) async {
        building = true
        root = nil
        stack = []
        scannedRoot = url
        let node = await Task.detached { DiskMap.build(at: url, maxDepth: 4) }.value
        root = node
        building = false
    }

    /// Move a node's file/folder to the Trash, then refresh the whole map so
    /// sizes reflect the change.
    func trashAndRefresh(_ node: DiskNode) async {
        guard let url = node.url else { return }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            NSSound.beep()
            return
        }
        if let root = scannedRoot { await build(at: root) }
    }

    func reveal(_ node: DiskNode) {
        guard let url = node.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func drill(into node: DiskNode) {
        guard node.isDirectory, !node.children.isEmpty else { return }
        stack.append(node)
    }

    func pop(to index: Int) {
        if index < 0 { stack = [] }
        else if index < stack.count { stack.removeSubrange((index + 1)...) }
    }
}

struct DiskMapView: View {
    @State private var m = DiskMapModel()
    @State private var pendingTrash: DiskNode?

    private let palette: [Color] = [
        .blue, .green, .orange, .purple, .pink, .teal, .indigo, .mint, .red, .cyan,
    ]

    var body: some View {
        VStack(spacing: 0) {
            if m.building {
                ProgressView("Measuring disk usage…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let node = m.current {
                breadcrumb
                treemap(of: node)
            } else {
                start
            }
        }
        .navigationTitle("Disk Map")
        .toolbar {
            Button("Choose Folder…") { chooseFolder() }
            Button("Scan Home") { Task { await m.build(at: home) } }
        }
        .confirmationDialog(
            "Move “\(pendingTrash?.name ?? "")” to Trash?",
            isPresented: Binding(get: { pendingTrash != nil }, set: { if !$0 { pendingTrash = nil } }),
            titleVisibility: .visible
        ) {
            if let node = pendingTrash {
                Button("Move \(node.size.formattedSize) to Trash", role: .destructive) {
                    Task { await m.trashAndRefresh(node) }
                    pendingTrash = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingTrash = nil }
        } message: {
            Text("It goes to the Trash and can be restored until you empty it.")
        }
    }

    private var home: URL { URL(filePath: NSHomeDirectory()) }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        if panel.runModal() == .OK, let url = panel.url {
            Task { await m.build(at: url) }
        }
    }

    private var start: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.pie").font(.system(size: 48)).foregroundStyle(.tint)
            Text("Visualize what's using space").font(.title2.weight(.medium))
            Text("Tip: right-click any tile to reveal it in Finder or move it to the Trash.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Scan Home Folder") { Task { await m.build(at: home) } }
                    .buttonStyle(.borderedProminent)
                Button("Choose Folder…") { chooseFolder() }
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var breadcrumb: some View {
        HStack(spacing: 4) {
            Button(m.root?.name ?? "Home") { m.pop(to: -1) }.buttonStyle(.link)
            ForEach(Array(m.stack.enumerated()), id: \.element.id) { idx, node in
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                Button(node.name) { m.pop(to: idx) }.buttonStyle(.link)
            }
            Spacer()
            if let c = m.current { Text(c.size.formattedSize).foregroundStyle(.secondary).monospacedDigit() }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func treemap(of node: DiskNode) -> some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            let tiles = Treemap.layout(
                node.children.map { (id: $0.id, weight: Double($0.size)) }, in: rect)
            ForEach(Array(tiles.enumerated()), id: \.element.id) { i, tile in
                if let child = node.children.first(where: { $0.id == tile.id }) {
                    TreemapTile(node: child, color: palette[i % palette.count])
                        .frame(width: tile.rect.width, height: tile.rect.height)
                        .position(x: tile.rect.midX, y: tile.rect.midY)
                        .onTapGesture { m.drill(into: child) }
                        .help("\(child.name) — \(child.size.formattedSize)")
                        .contextMenu {
                            if child.url != nil {   // not the "Other" aggregate
                                Button("Reveal in Finder") { m.reveal(child) }
                                if child.isDirectory && !child.children.isEmpty {
                                    Button("Drill In") { m.drill(into: child) }
                                }
                                Divider()
                                Button("Move to Trash…", role: .destructive) {
                                    pendingTrash = child
                                }
                            }
                        }
                }
            }
        }
        .padding(8)
    }
}

struct TreemapTile: View {
    let node: DiskNode
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(color.gradient)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.background, lineWidth: 1))
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(node.name).font(.caption.weight(.semibold)).lineLimit(1)
                    Text(node.size.formattedSize).font(.caption2)
                }
                .foregroundStyle(.white)
                .shadow(radius: 1)
                .padding(4)
            }
    }
}
