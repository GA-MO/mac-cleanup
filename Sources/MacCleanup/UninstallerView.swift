import SwiftUI
import AppKit
import CleanupKit

@MainActor
@Observable
final class UninstallerModel {
    private let engine = CleanupEngine()
    var apps: [InstalledApp] = []
    var query = ""
    var selected: InstalledApp?
    var footprint: AppFootprint?
    var loading = false
    var removedMessage: String?

    var filtered: [InstalledApp] {
        let base = apps.filter { !$0.isSystem }
        guard !query.isEmpty else { return base }
        return base.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    func load() async {
        loading = true
        apps = await Task.detached { InstalledApps.list() }.value
        loading = false
    }

    func select(_ app: InstalledApp) async {
        selected = app
        footprint = nil
        removedMessage = nil
        footprint = await Task.detached { Uninstaller.footprint(of: app) }.value
    }

    func uninstall() async {
        guard let fp = footprint else { return }
        let results = await engine.remove(fp.allItems, dryRun: false)
        let freed = results.filter(\.succeeded).reduce(Int64(0)) { $0 + $1.item.size }
        let failed = results.filter { !$0.succeeded }.count
        removedMessage = "Removed \(fp.app.name) — freed \(freed.formattedSize)"
            + (failed > 0 ? " (\(failed) item(s) failed)" : "")
        apps.removeAll { $0.id == fp.app.id }
        footprint = nil
        selected = nil
    }
}

struct UninstallerView: View {
    @State private var m = UninstallerModel()
    @State private var confirming = false

    var body: some View {
        HSplitView {
            appList
            detail
        }
        .navigationTitle("Uninstaller")
        .task { if m.apps.isEmpty { await m.load() } }
    }

    private var appList: some View {
        VStack(spacing: 0) {
            TextField("Search apps", text: $m.query)
                .textFieldStyle(.roundedBorder).padding(8)
            if m.loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Plain selectable rows — no NavigationLink (it would nest inside
                // the outer NavigationSplitView and squeeze the detail pane).
                List(m.filtered, selection: Binding(
                    get: { m.selected },
                    set: { app in if let app { Task { await m.select(app) } } }
                )) { app in
                    HStack {
                        AppIcon(url: app.url)
                        VStack(alignment: .leading) {
                            Text(app.name).lineLimit(1)
                            if let id = app.bundleID {
                                Text(id).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .tag(app)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(minWidth: 240, idealWidth: 300, maxWidth: 380, maxHeight: .infinity)
    }

    @ViewBuilder
    private var detail: some View {
        Group {
            if let msg = m.removedMessage {
                ContentUnavailableView("Done", systemImage: "checkmark.circle.fill",
                                       description: Text(msg))
            } else if let fp = m.footprint {
                footprintView(fp)
            } else if m.selected != nil {
                ProgressView("Gathering files…")
            } else {
                ContentUnavailableView("Select an app", systemImage: "trash.square",
                                       description: Text("Choose an app to see everything it leaves behind."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func footprintView(_ fp: AppFootprint) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                AppIcon(url: fp.app.url, size: 44)
                VStack(alignment: .leading) {
                    Text(fp.app.name).font(.title2.bold())
                    Text("\(fp.allItems.count) items · \(fp.totalSize.formattedSize)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive) { confirming = true } label: {
                    Label("Uninstall", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
            }
            .padding()

            List {
                ForEach(fp.allItems) { item in
                    HStack {
                        Image(systemName: item.url == fp.app.url ? "app.fill" : "doc")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text(item.label).lineLimit(1)
                            Text(item.detail ?? item.url.deletingLastPathComponent().lastPathComponent)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(item.size.formattedSize).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .help(item.url.path)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog("Move \(fp.app.name) and all its files to Trash?",
                            isPresented: $confirming, titleVisibility: .visible) {
            Button("Uninstall \(fp.totalSize.formattedSize)", role: .destructive) {
                Task { await m.uninstall() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// Renders an app's real icon via AppKit.
struct AppIcon: View {
    let url: URL
    var size: CGFloat = 20

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable().frame(width: size, height: size)
    }
}
