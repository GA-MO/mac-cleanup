import SwiftUI
import CleanupKit

/// Reusable scan→select→clean flow for tools backed by one or more scanners
/// (Photos, Privacy). Items are grouped by their `groupKey`; everything moves
/// to the Trash, and only Safe items are pre-selected.
@MainActor
@Observable
final class ScannerToolModel {
    enum Phase: Equatable { case idle, scanning, results, cleaning, done(Int64) }

    private let engine: CleanupEngine
    var phase: Phase = .idle
    private(set) var items: [CleanupItem] = []
    var selection: Set<UUID> = []

    init(scanners: [any CleanupKit.Scanner]) {
        engine = CleanupEngine(scanners: scanners)
    }

    /// Items grouped by `groupKey` (loose items become singletons), sorted by
    /// group total size descending.
    var groups: [[CleanupItem]] {
        var byKey: [String: [CleanupItem]] = [:]
        var order: [String] = []
        for item in items {
            let key = item.groupKey ?? item.id.uuidString
            if byKey[key] == nil { order.append(key) }
            byKey[key, default: []].append(item)
        }
        return order.map { byKey[$0]! }
            .sorted { CleanupEngine.reclaimable($0) > CleanupEngine.reclaimable($1) }
    }

    var selectedItems: [CleanupItem] { items.filter { selection.contains($0.id) } }
    var selectedSize: Int64 { CleanupEngine.reclaimable(selectedItems) }
    var totalFound: Int64 { CleanupEngine.reclaimable(items) }

    func scan() async {
        items = []; selection = []
        phase = .scanning
        let found = await engine.scan { _ in }
        items = found
        selection = Set(found.filter { $0.safety == .safe }.map(\.id))
        phase = found.isEmpty ? .done(0) : .results
    }

    func toggle(_ item: CleanupItem) {
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }

    private(set) var failures: [RemovalResult] = []

    func clean() async {
        phase = .cleaning
        let removed = await engine.remove(selectedItems, dryRun: false)
        failures = removed.filter { !$0.succeeded }
        let freed = removed.filter(\.succeeded).reduce(Int64(0)) { $0 + $1.item.size }
        phase = .done(freed)
    }

    func reset() { phase = .idle; items = []; selection = []; failures = [] }
}

struct ScannerToolView: View {
    let title: String
    let prompt: String
    let systemImage: String
    let scanLabel: String
    /// Section header for a group of related items (e.g. a similar-photo set).
    let sectionTitle: ([CleanupItem]) -> String
    /// Optional caution shown above results.
    var warning: String? = nil

    @State private var model: ScannerToolModel
    @State private var confirming = false

    init(title: String, prompt: String, systemImage: String, scanLabel: String,
         scanners: [any CleanupKit.Scanner], warning: String? = nil,
         sectionTitle: @escaping ([CleanupItem]) -> String) {
        self.title = title; self.prompt = prompt; self.systemImage = systemImage
        self.scanLabel = scanLabel; self.warning = warning; self.sectionTitle = sectionTitle
        _model = State(initialValue: ScannerToolModel(scanners: scanners))
    }

    var body: some View {
        Group {
            switch model.phase {
            case .idle:               idle
            case .scanning:           scanning
            case .results, .cleaning: results
            case let .done(freed):    done(freed)
            }
        }
        .navigationTitle(title)
    }

    private var idle: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage).font(.system(size: 48)).foregroundStyle(.tint)
            Text(title).font(.largeTitle.bold())
            Text(prompt).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button { Task { await model.scan() } } label: {
                Label(scanLabel, systemImage: "magnifyingglass").frame(maxWidth: 220).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
    }

    private var scanning: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("Scanning…").font(.title2.weight(.medium))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func done(_ freed: Int64) -> some View {
        VStack(spacing: 18) {
            Image(systemName: freed > 0 ? "checkmark.circle.fill" : "sparkles")
                .font(.system(size: 52)).foregroundStyle(freed > 0 ? .green : .secondary)
            Text(freed > 0 ? "Freed \(freed.formattedSize)" : "Nothing to clean")
                .font(.largeTitle.bold())
            if freed > 0 {
                Text("Removed items are in your Trash if you need them back.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            PostCleanFooter(failures: model.failures)
            HStack {
                Button("Scan Again") { Task { await model.scan() } }.buttonStyle(.borderedProminent)
                Button("Done") { model.reset() }
            }
            .controlSize(.large).padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
    }

    private var results: some View {
        List {
            if let warning {
                Section {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                }
            }
            ForEach(Array(model.groups.enumerated()), id: \.offset) { _, group in
                Section {
                    ForEach(group) { item in
                        ItemRow(item: item, isSelected: model.selection.contains(item.id)) {
                            model.toggle(item)
                        }
                    }
                } header: {
                    HStack {
                        Text(sectionTitle(group)).font(.headline)
                        Spacer()
                        Text(CleanupEngine.reclaimable(group).formattedSize)
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) { actionBar }
        .confirmationDialog("Move \(model.selection.count) item(s) to Trash?",
                            isPresented: $confirming, titleVisibility: .visible) {
            Button("Move \(model.selectedSize.formattedSize) to Trash", role: .destructive) {
                Task { await model.clean() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var actionBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Found \(model.totalFound.formattedSize) · \(model.selection.count) selected")
                    .font(.subheadline)
                Text(model.selectedSize.formattedSize)
                    .font(.title3.bold()).foregroundStyle(.tint).monospacedDigit()
            }
            Spacer()
            if model.phase == .cleaning { ProgressView().controlSize(.small) }
            Button("Clean") { confirming = true }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(model.selection.isEmpty || model.phase == .cleaning)
        }
        .padding(.horizontal, 20).padding(.vertical, 12).background(.bar)
    }
}
