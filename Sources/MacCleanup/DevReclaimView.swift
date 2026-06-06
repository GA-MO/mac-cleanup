import SwiftUI
import CleanupKit

@MainActor
@Observable
final class DevReclaimModel {
    var tasks: [DevReclaimTask] = []
    var loading = true
    var running: Set<String> = []
    var results: [String: DevReclaimResult] = [:]
    /// Estimated reclaimable bytes per task id (computed before running).
    var estimates: [String: Int64] = [:]
    /// Task ids whose estimate is still being measured.
    var estimating: Set<String> = []

    var totalEstimated: Int64 { estimates.values.reduce(0, +) }

    func load() async {
        loading = true
        tasks = await DevReclaim.availableTasks()
        loading = false
        await refreshEstimates()
    }

    /// Measure every task's reclaimable size concurrently, filling them in as
    /// each finishes.
    func refreshEstimates() async {
        estimating = Set(tasks.map(\.id))
        await withTaskGroup(of: (String, Int64?).self) { group in
            for task in tasks {
                group.addTask { (task.id, await DevReclaim.estimate(task)) }
            }
            for await (id, bytes) in group {
                if let bytes { estimates[id] = bytes } else { estimates[id] = nil }
                estimating.remove(id)
            }
        }
    }

    func run(_ task: DevReclaimTask) async {
        running.insert(task.id)
        results[task.id] = await DevReclaim.run(task)
        running.remove(task.id)
        // Re-measure: should drop toward zero once cleaned.
        estimating.insert(task.id)
        estimates[task.id] = await DevReclaim.estimate(task)
        estimating.remove(task.id)
    }

    func runAll() async {
        for task in tasks where !running.contains(task.id) {
            await run(task)
        }
    }
}

struct DevReclaimView: View {
    @State private var m = DevReclaimModel()

    var body: some View {
        Group {
            if m.loading {
                ProgressView("Detecting developer tools…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if m.tasks.isEmpty {
                ContentUnavailableView("No developer tools found",
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    description: Text("Install Docker, Homebrew, Go, npm, etc. to reclaim their caches here."))
            } else {
                list
            }
        }
        .navigationTitle("Developer Reclaim")
        .toolbar {
            if !m.tasks.isEmpty {
                if m.totalEstimated > 0 {
                    Text("~\(m.totalEstimated.formattedSize) reclaimable")
                        .foregroundStyle(.secondary).monospacedDigit()
                }
                Button("Run All") { Task { await m.runAll() } }
                    .disabled(!m.running.isEmpty)
            }
        }
        .task { await m.load() }
    }

    private var list: some View {
        List {
            Section {
                ForEach(m.tasks) { task in
                    row(task)
                }
            } footer: {
                Text("Each task runs that tool's own cleanup command. Only regenerable caches and unused artifacts are removed — your code and projects are untouched. Output is shown after each run.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ task: DevReclaimTask) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: task.systemImage)
                    .font(.title3).foregroundStyle(.tint).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title).font(.headline)
                    Text(task.detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                estimateLabel(for: task)
                if m.running.contains(task.id) {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Run") { Task { await m.run(task) } }
                }
            }
            if let result = m.results[task.id] {
                ResultBlock(result: result)
            }
        }
        .padding(.vertical, 4)
    }

    /// "~1.2 GB" reclaimable preview, a spinner while measuring, or nothing.
    @ViewBuilder
    private func estimateLabel(for task: DevReclaimTask) -> some View {
        if m.estimating.contains(task.id) {
            ProgressView().controlSize(.small)
        } else if let bytes = m.estimates[task.id], bytes > 0 {
            Text("~\(bytes.formattedSize)")
                .font(.callout.weight(.medium)).monospacedDigit()
                .foregroundStyle(.tint)
                .help("Estimated reclaimable space")
        }
    }
}

/// Collapsible-looking output block shown under a task after it runs.
struct ResultBlock: View {
    let result: DevReclaimResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(result.succeeded ? "Completed" : "Finished with errors",
                  systemImage: result.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(result.succeeded ? .green : .orange)
            if !result.output.isEmpty {
                ScrollView {
                    Text(result.output)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
                .padding(8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.leading, 40)
    }
}
