import SwiftUI
import CleanupKit

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.phase {
        case .idle:
            WelcomeView()
        case .scanning:
            ScanningView()
        case .results, .cleaning:
            ResultsView()
        case let .done(reclaimed, failures):
            DoneView(reclaimed: reclaimed, failures: failures)
        }
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Mac Cleanup")
                .font(.largeTitle.bold())
            Text("Scan for caches, developer junk, large files, and duplicates.\nEverything you remove goes to the Trash — nothing is destroyed.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button {
                Task { await model.startScan() }
            } label: {
                Label("Scan My Mac", systemImage: "magnifyingglass")
                    .frame(maxWidth: 220)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Label(
                "For full results, grant Full Disk Access in System Settings → Privacy & Security.",
                systemImage: "lock.shield"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Scanning

struct ScanningView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Scanning…")
                .font(.title2.weight(.medium))
            Text("\(model.items.count) items · \(model.totalFound.formattedSize) found so far")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Done

struct DoneView: View {
    @Environment(AppModel.self) private var model
    let reclaimed: Int64
    let failures: Int

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: failures == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(failures == 0 ? Color.green : Color.orange)
            Text("Freed \(reclaimed.formattedSize)")
                .font(.largeTitle.bold())
            if failures > 0 {
                Text("\(failures) item(s) couldn't be removed.")
                    .foregroundStyle(.secondary)
            }
            if let summary = model.restoreSummary {
                Label(summary, systemImage: "arrow.uturn.backward.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            } else {
                Text("Removed items are in your Trash if you need them back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                PostCleanFooter(failures: model.lastResults.filter { !$0.succeeded })
            }

            HStack {
                Button("Scan Again") { Task { await model.startScan() } }
                    .buttonStyle(.borderedProminent)
                if model.canUndo {
                    Button {
                        Task { await model.undoLastClean() }
                    } label: {
                        Label("Undo — Restore Files", systemImage: "arrow.uturn.backward")
                    }
                }
                Button("Done") { model.reset() }
            }
            .controlSize(.large)
            .padding(.top, 8)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
