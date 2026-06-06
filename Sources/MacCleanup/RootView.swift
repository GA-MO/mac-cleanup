import SwiftUI
import CleanupKit

enum Tool: String, CaseIterable, Identifiable {
    case smartScan   = "Smart Scan"
    case cleanup     = "Cleanup"
    case developer   = "Developer"
    case uninstaller = "Uninstaller"
    case diskMap     = "Disk Map"
    case maintenance = "Maintenance"

    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .smartScan:   "wand.and.stars"
        case .cleanup:     "sparkles"
        case .developer:   "chevron.left.forwardslash.chevron.right"
        case .uninstaller: "trash.square"
        case .diskMap:     "chart.pie"
        case .maintenance: "wrench.and.screwdriver"
        }
    }
}

/// Top-level shell: a sidebar of tools, each driving its own detail view.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var tool: Tool = .smartScan
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    var body: some View {
        content
            .sheet(isPresented: Binding(get: { !hasOnboarded }, set: { hasOnboarded = !$0 })) {
                OnboardingView { hasOnboarded = true }
            }
    }

    private var content: some View {
        NavigationSplitView {
            List(Tool.allCases, selection: $tool) { t in
                NavigationLink(value: t) {
                    Label(t.rawValue, systemImage: t.systemImage)
                }
            }
            .navigationTitle("Mac Cleanup")
            .frame(minWidth: 180)
            .safeAreaInset(edge: .bottom) { DiskGauge() }
        } detail: {
            switch tool {
            case .smartScan:   SmartScanView()
            case .cleanup:     ContentView()
            case .developer:   DevReclaimView()
            case .uninstaller: UninstallerView()
            case .diskMap:     DiskMapView()
            case .maintenance: MaintenanceView()
            }
        }
    }
}

/// Compact free-space gauge shown at the bottom of the sidebar.
struct DiskGauge: View {
    @State private var info: VolumeInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let info {
                Text("\(info.free.formattedSize) free")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(info.isLow ? .orange : .primary)
                ProgressView(value: info.usedFraction)
                    .tint(info.isLow ? .orange : .accentColor)
                Text("\(info.used.formattedSize) of \(info.total.formattedSize) used")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .task { info = VolumeInfo.current() }
    }
}
