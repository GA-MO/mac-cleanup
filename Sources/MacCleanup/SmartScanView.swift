import SwiftUI
import CleanupKit

/// One-click scan across everything that reclaims space: the cleanup scanners
/// (→ Trash) and developer tool caches (→ each tool's own cleanup). Safe items
/// are pre-selected so a single "Clean" frees the obvious wins.
@MainActor
@Observable
final class SmartScanModel {
    enum Phase: Equatable { case idle, scanning, results, cleaning, done(Int64) }

    private let engine = CleanupEngine()
    var phase: Phase = .idle

    // Cleanup-scanner findings (removed by moving to Trash).
    private(set) var items: [CleanupItem] = []
    var itemSelection: Set<UUID> = []

    // Developer tool caches (reclaimed by running the tool's cleanup command).
    private(set) var devTasks: [DevReclaimTask] = []
    private(set) var devEstimates: [String: Int64] = [:]
    var devSelection: Set<String> = []

    var byCategory: [CategoryGroup] {
        CleanupCategory.allCases.compactMap { cat in
            let group = items.filter { $0.category == cat }.sorted { $0.size > $1.size }
            return group.isEmpty ? nil : CategoryGroup(category: cat, items: group)
        }
    }

    var selectedItems: [CleanupItem] { items.filter { itemSelection.contains($0.id) } }
    var selectedCleanupSize: Int64 { CleanupEngine.reclaimable(selectedItems) }
    var selectedDevSize: Int64 {
        devSelection.reduce(0) { $0 + (devEstimates[$1] ?? 0) }
    }
    var totalSelected: Int64 { selectedCleanupSize + selectedDevSize }
    var totalFound: Int64 {
        CleanupEngine.reclaimable(items) + devTasks.reduce(0) { $0 + (devEstimates[$1.id] ?? 0) }
    }

    func sizeOfCategory(_ cat: CleanupCategory) -> Int64 {
        CleanupEngine.reclaimable(items.filter { $0.category == cat })
    }

    func scan() async {
        items = []; itemSelection = []
        devTasks = []; devEstimates = [:]; devSelection = []
        phase = .scanning

        // Cleanup scan and developer-tool detection run concurrently.
        async let cleanup = engine.scan { _ in }
        let tasks = await DevReclaim.availableTasks()

        var estimates: [String: Int64] = [:]
        await withTaskGroup(of: (String, Int64?).self) { group in
            for t in tasks { group.addTask { (t.id, await DevReclaim.estimate(t)) } }
            for await (id, bytes) in group { if let bytes { estimates[id] = bytes } }
        }

        let found = await cleanup
        items = found
        itemSelection = Set(found.filter { $0.safety == .safe }.map(\.id))

        // Only surface dev caches that actually have something to reclaim.
        devTasks = tasks.filter { (estimates[$0.id] ?? 0) > 0 }
        devEstimates = estimates
        devSelection = Set(devTasks.map(\.id))   // all safe → pre-selected

        phase = .results
    }

    func toggleItem(_ item: CleanupItem) {
        if itemSelection.contains(item.id) { itemSelection.remove(item.id) }
        else { itemSelection.insert(item.id) }
    }
    func toggleDev(_ id: String) {
        if devSelection.contains(id) { devSelection.remove(id) } else { devSelection.insert(id) }
    }
    func selectAll(in cat: CleanupCategory) {
        for i in items where i.category == cat { itemSelection.insert(i.id) }
    }
    func deselectAll(in cat: CleanupCategory) {
        for i in items where i.category == cat { itemSelection.remove(i.id) }
    }

    func clean() async {
        phase = .cleaning
        // Cleanup items → Trash.
        let removed = await engine.remove(selectedItems, dryRun: false)
        var freed = removed.filter(\.succeeded).reduce(Int64(0)) { $0 + $1.item.size }
        // Developer caches → each tool's cleanup; count the estimate as freed.
        for task in devTasks where devSelection.contains(task.id) {
            _ = await DevReclaim.run(task)
            freed += devEstimates[task.id] ?? 0
        }
        phase = .done(freed)
    }

    func reset() { phase = .idle; items = []; itemSelection = []; devTasks = []; devSelection = [] }
}

struct SmartScanView: View {
    @State private var m = SmartScanModel()
    @State private var confirming = false

    var body: some View {
        Group {
            switch m.phase {
            case .idle:                 idle
            case .scanning:             scanning
            case .results, .cleaning:   results
            case let .done(freed):      done(freed)
            }
        }
        .navigationTitle("Smart Scan")
    }

    private var idle: some View {
        VStack(spacing: 18) {
            Image(systemName: "wand.and.stars").font(.system(size: 52)).foregroundStyle(.tint)
            Text("Smart Scan").font(.largeTitle.bold())
            Text("Scan everything at once — caches, developer junk, large files,\nduplicates, and developer tool caches — then clean the safe wins in one click.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button { Task { await m.scan() } } label: {
                Label("Smart Scan", systemImage: "wand.and.stars")
                    .frame(maxWidth: 220).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
    }

    private var scanning: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("Scanning everything…").font(.title2.weight(.medium))
            Text("Cleanup scanners + developer caches").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func done(_ freed: Int64) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(.green)
            Text("Freed \(freed.formattedSize)").font(.largeTitle.bold())
            Text("Cleanup items are in your Trash. Developer caches were cleared in place.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack {
                Button("Scan Again") { Task { await m.scan() } }.buttonStyle(.borderedProminent)
                Button("Done") { m.reset() }
            }
            .controlSize(.large).padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
    }

    private var results: some View {
        List {
            ForEach(m.byCategory) { group in
                Section {
                    ForEach(group.items) { item in
                        ItemRow(item: item, isSelected: m.itemSelection.contains(item.id)) {
                            m.toggleItem(item)
                        }
                    }
                } header: { categoryHeader(group) }
            }

            if !m.devTasks.isEmpty {
                Section {
                    ForEach(m.devTasks) { task in
                        devRow(task)
                    }
                } header: {
                    Label("Developer Caches", systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.headline)
                }
            }
        }
        .safeAreaInset(edge: .bottom) { actionBar }
        .confirmationDialog("Clean \(m.totalSelected.formattedSize)?",
                            isPresented: $confirming, titleVisibility: .visible) {
            Button("Clean \(m.totalSelected.formattedSize)", role: .destructive) {
                Task { await m.clean() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Cleanup items move to the Trash (undoable). Developer caches are cleared by each tool and rebuild on demand.")
        }
    }

    private func categoryHeader(_ group: CategoryGroup) -> some View {
        HStack {
            Label(group.category.rawValue, systemImage: group.category.systemImage).font(.headline)
            Text(m.sizeOfCategory(group.category).formattedSize)
                .foregroundStyle(.secondary).monospacedDigit()
            Spacer()
            Button("Select All") { m.selectAll(in: group.category) }
            Button("None") { m.deselectAll(in: group.category) }
        }
        .buttonStyle(.link).font(.callout)
    }

    private func devRow(_ task: DevReclaimTask) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(get: { m.devSelection.contains(task.id) },
                                     set: { _ in m.toggleDev(task.id) })).labelsHidden()
            Image(systemName: task.systemImage).foregroundStyle(.tint).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).lineLimit(1)
                Text(task.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text("~\((m.devEstimates[task.id] ?? 0).formattedSize)")
                .monospacedDigit().foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { m.toggleDev(task.id) }
    }

    private var actionBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Found \(m.totalFound.formattedSize)").font(.subheadline)
                Text(m.totalSelected.formattedSize)
                    .font(.title3.bold()).foregroundStyle(.tint).monospacedDigit()
            }
            Spacer()
            if m.phase == .cleaning {
                ProgressView().controlSize(.small)
                Text("Cleaning…").foregroundStyle(.secondary)
            }
            Button("Clean") { confirming = true }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(m.totalSelected == 0 || m.phase == .cleaning)
        }
        .padding(.horizontal, 20).padding(.vertical, 12).background(.bar)
    }
}
