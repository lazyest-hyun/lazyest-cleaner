import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(CleanupStore.self) private var store
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var store = store
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
        } detail: {
            detailContent
                .navigationTitle(store.selectedWorkspace.title)
                .overlay(alignment: .bottomTrailing) {
                    if let notice = store.notice {
                        StatusBanner(notice: notice)
                            .frame(maxWidth: 420)
                            .padding(.trailing, DesignTokens.spacing12)
                            .padding(.bottom, 64)
                    }
                }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if store.selectedCategory.supportsScan {
                    UnifiedActionButton(
                        action: store.isScanning ? .cancelScan : .scan,
                        presentation: .iconOnly
                    )
                    UnifiedActionButton(action: .selectRecommended, presentation: .iconOnly)
                }
            }
        }
        .toolbarRole(.editor)
        .sheet(item: $store.pendingConfirmation) { request in
            ConfirmationSheet(request: request)
        }
        .task {
            await store.start()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            Task {
                await store.refreshFullDiskAccessAfterReturning()
            }
        }
        .frame(minWidth: DesignTokens.minimumWindowWidth, minHeight: DesignTokens.minimumWindowHeight)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch store.selectedCategory {
        case .overview:
            OverviewView()
        case .history:
            HistoryView()
        case .settings:
            SettingsView()
        default:
            CleanupDetailView()
        }
    }
}
