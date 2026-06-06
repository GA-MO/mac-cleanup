import SwiftUI
import CleanupKit

/// Cleanup results as one grouped list (a section per category) with a clean
/// action bar pinned to the bottom.
struct ResultsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirming = false

    var body: some View {
        List {
            ForEach(model.byCategory) { group in
                Section {
                    ForEach(group.items) { item in
                        ItemRow(item: item, isSelected: model.selection.contains(item.id)) {
                            model.toggle(item)
                        }
                    }
                } header: {
                    HStack {
                        Label(group.category.rawValue, systemImage: group.category.systemImage)
                            .font(.headline)
                        Text(model.sizeOfCategory(group.category).formattedSize)
                            .foregroundStyle(.secondary).monospacedDigit()
                        Spacer()
                        Button("Select All") { model.selectAll(in: group.category) }
                        Button("None") { model.deselectAll(in: group.category) }
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                }
            }
        }
        .safeAreaInset(edge: .bottom) { actionBar }
        .confirmationDialog(
            "Move \(model.selection.count) item(s) to Trash?",
            isPresented: $confirming, titleVisibility: .visible
        ) {
            Button("Move \(model.selectedSize.formattedSize) to Trash", role: .destructive) {
                Task { await model.performClean() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Items go to the Trash and can be restored until you empty it.")
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
            if case .cleaning = model.phase {
                ProgressView().controlSize(.small)
                Text("Cleaning…").foregroundStyle(.secondary)
            }
            Button("Rescan") { Task { await model.startScan() } }
            Button("Clean") { confirming = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.selection.isEmpty || model.phase == .cleaning)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.bar)
    }
}

struct ItemRow: View {
    let item: CleanupItem
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(get: { isSelected }, set: { _ in toggle() }))
                .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label).lineLimit(1)
                HStack(spacing: 6) {
                    SafetyBadge(level: item.safety)
                    if let detail = item.detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            Spacer()
            Text(item.size.formattedSize).monospacedDigit().foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .help(item.url.path)
    }
}

struct SafetyBadge: View {
    let level: SafetyLevel

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private var text: String {
        switch level {
        case .safe: "Safe"
        case .review: "Review"
        case .caution: "Caution"
        }
    }
    private var color: Color {
        switch level {
        case .safe: .green
        case .review: .orange
        case .caution: .red
        }
    }
}
