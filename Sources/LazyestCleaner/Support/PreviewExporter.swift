import AppKit
import SwiftUI

/// Renders the production views with synthetic data without opening a window or scanning disk.
@MainActor
enum PreviewExporter {
    static func exportIfRequested() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        let audit = arguments.contains("--export-ui-audit")
        guard let index = arguments.firstIndex(of: audit ? "--export-ui-audit" : "--export-preview") else {
            return false
        }
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
            for scenario in audit ? auditScenarios : documentationScenarios {
                defaults.removePersistentDomain(forName: suiteName)
                let category = scenario.category
                let width = scenario.width
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
                configure(store, scenario: scenario)
                let view = NSHostingView(
                    rootView: PreviewShell(scenario: scenario).environment(store).tint(DesignTokens.accent).accentColor(
                        DesignTokens.accent
                    )
                    .environment(\.colorScheme, .light).background(Color(nsColor: .windowBackgroundColor)))
                let window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: width, height: scenario.height),
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                windows.append(window)
                window.contentView = view
                window.appearance = NSAppearance(named: .aqua)
                view.frame = NSRect(x: 0, y: 0, width: width, height: scenario.height)
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
                try data.write(to: directory.appending(path: "\(scenario.name).png"), options: .atomic)
                window.orderOut(nil)
                windows.removeAll()
            }
        } catch {
            fputs("Preview export failed: \(error)\n", stderr)
            exit(1)
        }
        return true
    }

    private static let documentationScenarios = [
        PreviewScenario(name: "cleaner-overview", category: .overview),
        PreviewScenario(name: "cleaner-files", category: .largeFiles),
        PreviewScenario(name: "cleaner-compact", category: .applications, width: 860),
    ]

    private static var auditScenarios: [PreviewScenario] {
        var scenarios = CleanupCategory.allCases.filter { $0 != .settings }.flatMap { category in
            [
                PreviewScenario(name: "route-\(category.rawValue)", category: category),
                PreviewScenario(name: "compact-\(category.rawValue)", category: category, width: 860, height: 620),
            ]
        }
        for section in SettingsSection.allCases {
            scenarios.append(PreviewScenario(name: "settings-\(section)", category: .settings, section: section))
            scenarios.append(
                PreviewScenario(
                    name: "settings-\(section)-compact", category: .settings, width: 860, height: 620, section: section)
            )
        }
        for state in ["initial", "denied", "scanning"] {
            scenarios.append(PreviewScenario(name: "overview-\(state)", category: .overview, state: state))
        }
        for state in ["initial", "empty", "scanning", "filtered", "denied", "timedOut", "unavailable", "failed"] {
            scenarios.append(
                PreviewScenario(name: "detail-\(state)", category: .largeFiles, width: 860, height: 620, state: state))
        }
        scenarios.append(
            PreviewScenario(name: "history-populated", category: .history, width: 860, height: 620, state: "history"))
        scenarios.append(
            PreviewScenario(name: "settings-locations-empty", category: .settings, section: .locations, state: "empty"))
        for state in ["standard", "reinforced"] {
            scenarios.append(
                PreviewScenario(
                    name: "confirmation-\(state)", category: .applications, width: 540, height: 430, state: state))
        }
        return scenarios
    }

    private static func configure(_ store: CleanupStore, scenario: PreviewScenario) {
        if scenario.category == .settings, scenario.state != "empty" {
            store.settings.addScanRoot(
                URL(fileURLWithPath: "/Users/demo/Documents/Projects/Example project with a longer folder name"))
            store.settings.addProtectedPath(URL(fileURLWithPath: "/Users/demo/Documents/Protected project"))
        }
        if ["initial", "empty", "scanning", "denied", "timedOut", "unavailable", "failed"].contains(scenario.state) {
            store.itemsByCategory = [:]
            store.selectedItemIDs = []
            store.scannedCategories = scenario.state == "empty" ? [scenario.category] : []
        }
        switch scenario.state {
        case "initial":
            store.storageSnapshot = nil
            store.hasCheckedFullDiskAccess = false
        case "denied", "timedOut", "unavailable", "failed":
            let kind: CleanupScanIssueKind =
                switch scenario.state {
                case "denied": .permissionDenied
                case "timedOut": .timedOut
                case "unavailable": .unavailable
                default: .failed
                }
            store.hasFullDiskAccess = scenario.state != "denied"
            store.scanIssues[scenario.category] = CleanupScanIssue(kind: kind, title: "스캔을 완료하지 못했습니다", detail: "예시 오류")
        case "scanning":
            store.isScanning = true
            store.scanningCategory = scenario.category == .overview ? .largeFiles : scenario.category
            store.scanCompletedCount = 3
            store.scanTotalCount = 10
        case "filtered": store.searchText = "no-matching-example"
        case "history":
            store.history = [
                CleanupHistoryEntry(
                    id: UUID(), date: Date(timeIntervalSince1970: 1_780_000_000), action: .moveToTrash,
                    itemCount: 3, bytes: 1_240_000_000, succeeded: 3, failed: 0),
                CleanupHistoryEntry(
                    id: UUID(), date: Date(timeIntervalSince1970: 1_780_000_000), action: .uninstallApplication,
                    itemCount: 2, bytes: 3_240_000_000, succeeded: 1, failed: 1),
            ]
        default: break
        }
    }
}

private struct PreviewScenario {
    let name: String
    let category: CleanupCategory
    var width = 1180
    var height = 760
    var section: SettingsSection = .general
    var state = "populated"
}

/// The document export uses the production detail views with a static sidebar;
/// native sidebar vibrancy is composited by WindowServer and cannot be cached offscreen.
private struct PreviewShell: View {
    @Environment(CleanupStore.self) private var store
    let scenario: PreviewScenario

    var body: some View {
        if ["standard", "reinforced"].contains(scenario.state) {
            ConfirmationSheet(
                request: CleanupConfirmationRequest(
                    action: scenario.state == "standard" ? .moveToTrash : .deletePermanently,
                    items: Array((store.itemsByCategory[.applications] ?? []).prefix(2))))
        } else {
            shell
        }
    }

    private var shell: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Lazyest Cleaner").font(.headline).padding(.bottom, 16)
                ForEach(CleanupWorkspace.allCases) { workspace in
                    AlignedSymbolLabel(title: workspace.title, systemImage: workspace.symbol)
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
                .padding(.horizontal, 16)
                .frame(height: 48)
                Divider()
                Group {
                    switch store.selectedCategory {
                    case .overview: OverviewView()
                    case .history: HistoryView()
                    case .settings:
                        SettingsView(section: scenario.section, protectionHome: URL(fileURLWithPath: "/Users/demo"))
                    default: CleanupDetailView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
