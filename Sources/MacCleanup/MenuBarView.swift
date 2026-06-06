import SwiftUI
import AppKit
import CleanupKit

/// The menu-bar dropdown: at-a-glance free space plus quick entry points.
struct MenuBarView: View {
    @State private var info: VolumeInfo?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mac Cleanup").font(.headline)

            if let info {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(info.free.formattedSize) free")
                            .font(.title3.bold())
                            .foregroundStyle(info.isLow ? .orange : .primary)
                        Spacer()
                        if info.isLow {
                            Label("Low", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                    ProgressView(value: info.usedFraction)
                        .tint(info.isLow ? .orange : .accentColor)
                    Text("\(info.used.formattedSize) of \(info.total.formattedSize) used")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Disk info unavailable").font(.caption).foregroundStyle(.secondary)
            }

            Divider()

            Button {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            } label: {
                Label("Open Mac Cleanup", systemImage: "macwindow")
            }
            .buttonStyle(.borderedProminent)

            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.link)
        }
        .padding(14)
        .frame(width: 260)
        .task { info = VolumeInfo.current() }
    }
}
