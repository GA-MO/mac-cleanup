import SwiftUI
import CleanupKit

@MainActor
@Observable
final class MaintenanceModel {
    var running: Set<String> = []
    var results: [String: MaintenanceResult] = [:]

    func run(_ task: MaintenanceTask) async {
        running.insert(task.id)
        let result = await Maintenance.run(task)
        results[task.id] = result
        running.remove(task.id)
    }
}

struct MaintenanceView: View {
    @State private var m = MaintenanceModel()

    var body: some View {
        List {
            Section {
                ForEach(Maintenance.tasks) { task in
                    row(task)
                }
            } footer: {
                Text("These run standard macOS commands and don't delete your files. Tasks marked with a lock ask for your password.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Maintenance")
    }

    private func row(_ task: MaintenanceTask) -> some View {
        HStack(spacing: 12) {
            Image(systemName: task.systemImage)
                .font(.title3).foregroundStyle(.tint).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(task.title).font(.headline)
                    if task.needsAdmin {
                        Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(task.detail).font(.caption).foregroundStyle(.secondary)
                if let result = m.results[task.id] {
                    Label(result.succeeded ? "Done" : "Failed: \(result.output)",
                          systemImage: result.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(result.succeeded ? .green : .red)
                        .lineLimit(2)
                }
            }
            Spacer()
            if m.running.contains(task.id) {
                ProgressView().controlSize(.small)
            } else {
                Button("Run") { Task { await m.run(task) } }
            }
        }
        .padding(.vertical, 4)
    }
}
