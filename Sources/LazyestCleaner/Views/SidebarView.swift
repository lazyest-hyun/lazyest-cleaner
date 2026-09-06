import SwiftUI

struct SidebarView: View {
    @Environment(CleanupStore.self) private var store

    var body: some View {
        List(selection: selection) {
            Section {
                SidebarWorkspaceRow(workspace: .overview)
                    .tag(CleanupWorkspace.overview)
                SidebarWorkspaceRow(workspace: .quick)
                    .tag(CleanupWorkspace.quick)
            }

            Section("정리") {
                ForEach([
                    CleanupWorkspace.applications,
                    .files,
                    .appData,
                    .developer,
                ]) { workspace in
                    SidebarWorkspaceRow(workspace: workspace)
                        .tag(workspace)
                }
            }

            Section("관리") {
                SidebarWorkspaceRow(workspace: .history)
                    .tag(CleanupWorkspace.history)
                SidebarWorkspaceRow(workspace: .settings)
                    .tag(CleanupWorkspace.settings)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 184, ideal: 210, max: 242)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarFooter()
        }
    }

    private var selection: Binding<CleanupWorkspace?> {
        Binding(
            get: { store.selectedWorkspace },
            set: { workspace in
                if let workspace { store.selectWorkspace(workspace) }
            }
        )
    }
}

private struct SidebarWorkspaceRow: View {
    @Environment(CleanupStore.self) private var store
    let workspace: CleanupWorkspace

    var body: some View {
        let summary = store.summary(for: workspace)
        HStack(spacing: DesignTokens.spacing8) {
            AlignedSymbolLabel(title: workspace.title, systemImage: workspace.symbol)
                .lineLimit(1)
            Spacer(minLength: DesignTokens.spacing8)
            ZStack(alignment: .trailing) {
                if isScanningWorkspace {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Text(summary.count > 0 ? DisplayFormatting.count(summary.count) : "")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 34, height: 16, alignment: .trailing)
        }
        .help(workspace.title)
    }

    private var isScanningWorkspace: Bool {
        guard store.isScanning, let category = store.scanningCategory else { return false }
        return workspace.categories.contains(category)
    }
}

private struct SidebarFooter: View {
    @Environment(CleanupStore.self) private var store

    var body: some View {
        HStack(spacing: DesignTokens.spacing8) {
            if let snapshot = store.storageSnapshot {
                Image(systemName: "internaldrive")
                    .frame(width: DesignTokens.labelIconWidth)
                    .foregroundStyle(.secondary)
                Text("\(DisplayFormatting.bytes(snapshot.available)) 여유")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            UnifiedActionButton(action: .openTrash, presentation: .iconOnly)
        }
        .padding(.horizontal, DesignTokens.spacing12)
        .padding(.vertical, DesignTokens.spacing8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
