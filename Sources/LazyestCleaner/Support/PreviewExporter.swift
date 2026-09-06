import AppKit
import SwiftUI

/// Renders the production views with synthetic data without opening a window or scanning disk.
@MainActor
enum PreviewExporter {
    static func exportIfRequested() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--export-preview") else { return false }
        guard arguments.indices.contains(index + 1) else { exit(2) }
        let directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        let suiteName = "com.lazyest.cleaner.preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        NSApplication.shared.setActivationPolicy(.prohibited)
        NSApplication.shared.appearance = NSAppearance(named: .aqua)
        var windows: [NSWindow] = []
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (name, category, width) in [
                ("cleaner-overview", CleanupCategory.overview, 1180),
                ("cleaner-files", CleanupCategory.largeFiles, 1180),
                ("cleaner-compact", CleanupCategory.applications, 860),
            ] {
                let store = CleanupStore(
                    settings: AppSettings(defaults: defaults),
                    historyRepository: HistoryRepository(fileURL: directory.appending(path: "unused-history.json")),
                    demoMode: true
                )
                store.itemsByCategory = DemoData.items()
                store.scannedCategories = Set(store.itemsByCategory.keys)
                store.storageSnapshot = DemoData.storage
                store.hasCheckedFullDiskAccess = true
                store.hasFullDiskAccess = true
                store.selectedCategory = category
                if category == .applications, let item = store.currentItems.first {
                    store.selectedItemIDs = [item.id]
                } else {
                    store.selectedItemIDs = []
                }
                let view = NSHostingView(
                    rootView: PreviewShell().environment(store).tint(DesignTokens.accent).accentColor(
                        DesignTokens.accent
                    )
                    .environment(\.colorScheme, .light).background(Color(nsColor: .windowBackgroundColor)))
                let window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: width, height: 760),
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                windows.append(window)
                window.contentView = view
                window.appearance = NSAppearance(named: .aqua)
                view.frame = NSRect(x: 0, y: 0, width: width, height: 760)
                view.layoutSubtreeIfNeeded()
                // Let SwiftUI settle native tables and split columns without ordering the window front.
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                guard let data = bitmap.representation(using: .png, properties: [:]) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                try data.write(to: directory.appending(path: "\(name).png"), options: .atomic)
                window.orderOut(nil)
            }
        } catch {
            fputs("Preview export failed: \(error)\n", stderr)
            exit(1)
        }
        return true
    }
}

/// The document export uses the production detail views with a static sidebar;
/// native sidebar vibrancy is composited by WindowServer and cannot be cached offscreen.
private struct PreviewShell: View {
    @Environment(CleanupStore.self) private var store

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Lazyest Cleaner").font(.headline).padding(.bottom, 16)
                ForEach(CleanupWorkspace.allCases) { workspace in
                    Label(workspace.title, systemImage: workspace.symbol)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(workspace == store.selectedWorkspace ? DesignTokens.accent.opacity(0.12) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Spacer()
                Label("238 GB 여유", systemImage: "internaldrive")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16).frame(width: 210)
            .background(Color(nsColor: .controlBackgroundColor))
            Divider()
            VStack(spacing: 0) {
                HStack {
                    Text(store.selectedWorkspace.title).font(.headline); Spacer()
                }
                .padding(16)
                Divider()
                if store.selectedCategory == .overview { OverviewView() } else { CleanupDetailView() }
            }
        }
    }
}
