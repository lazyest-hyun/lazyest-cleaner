import SwiftUI

struct OverviewView: View {
    var body: some View {
        VStack(spacing: 0) {
            StorageHeader()
            Divider()
            if storeNeedsFullDiskAccess {
                FullDiskAccessRow()
                Divider()
            }
            QuickCleanRow()
            Divider()
            WorkspaceResultsList()
        }
    }

    @Environment(CleanupStore.self) private var store

    private var storeNeedsFullDiskAccess: Bool {
        store.needsFullDiskAccess
    }
}

private struct FullDiskAccessRow: View {
    var body: some View {
        HStack(spacing: DesignTokens.spacing12) {
            Label("전체 디스크 접근 권한", systemImage: "lock.shield")
                .font(.callout.weight(.medium))
            Spacer()
            UnifiedActionButton(action: .openFullDiskAccess, presentation: .bordered)
        }
        .padding(.horizontal, DesignTokens.spacing16)
        .frame(height: 48)
    }
}

private struct StorageHeader: View {
    @Environment(CleanupStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing12) {
            HStack(alignment: .center, spacing: DesignTokens.spacing24) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("사용 가능", systemImage: "internaldrive")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(store.storageSnapshot.map { DisplayFormatting.bytes($0.available) } ?? "-")
                        .font(.title2.monospacedDigit().weight(.semibold))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("정리 후보")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(DisplayFormatting.bytes(store.totalCandidateBytes))
                        .font(.title2.monospacedDigit().weight(.semibold))
                }

                Spacer()

                OverviewScanControl()
            }

            if let snapshot = store.storageSnapshot {
                Gauge(value: snapshot.usedFraction) {
                    EmptyView()
                }
                .gaugeStyle(.linearCapacity)
                .tint(snapshot.usedFraction > 0.9 ? .red : .accentColor)
                .help("사용 \(DisplayFormatting.bytes(snapshot.used)) · 전체 \(DisplayFormatting.bytes(snapshot.total))")
            }

            ZStack {
                Color.clear
                if store.isScanning, let progress = store.scanProgress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                }
            }
            .frame(height: 3)
        }
        .padding(DesignTokens.spacing16)
        .frame(height: 132)
    }
}

private struct OverviewScanControl: View {
    @Environment(CleanupStore.self) private var store

    var body: some View {
        ZStack(alignment: .trailing) {
            UnifiedActionButton(action: .scanAll, presentation: .prominent)
                .opacity(store.isScanning ? 0 : 1)
                .allowsHitTesting(!store.isScanning)

            HStack(spacing: DesignTokens.spacing8) {
                Text(store.scanStatusTitle ?? "스캔 중")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                UnifiedActionButton(action: .cancelScan, presentation: .iconOnly)
            }
            .opacity(store.isScanning ? 1 : 0)
            .allowsHitTesting(store.isScanning)
        }
        .frame(width: 190, height: 32, alignment: .trailing)
    }
}

private struct QuickCleanRow: View {
    @Environment(CleanupStore.self) private var store

    var body: some View {
        let summary = store.summary(for: .quick)
        Button {
            store.selectWorkspace(.quick)
        } label: {
            HStack(spacing: DesignTokens.spacing12) {
                Image(systemName: CleanupWorkspace.quick.symbol)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(CleanupWorkspace.quick.title)
                        .font(.headline)
                    Text(quickStatus(summary: summary))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(summary.count > 0 ? "검토" : "열기")
                    .font(.callout.weight(.medium))
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            .contentShape(Rectangle())
            .padding(.horizontal, DesignTokens.spacing16)
            .padding(.vertical, DesignTokens.spacing12)
            .frame(minHeight: 72)
            .background(Color.accentColor.opacity(0.08))
        }
        .buttonStyle(.plain)
        .help("안전한 정리 후보 열기")
    }

    private func quickStatus(summary: (count: Int, bytes: Int64, protected: Int)) -> String {
        if summary.count > 0 {
            return "\(DisplayFormatting.count(summary.count))개 · \(DisplayFormatting.bytes(summary.bytes))"
        }
        return store.hasScanned(.quick) ? "정리할 항목 없음" : "스캔 전"
    }
}

private struct WorkspaceResultsList: View {
    var body: some View {
        List {
            Section("영역") {
                ForEach([
                    CleanupWorkspace.applications,
                    .files,
                    .appData,
                    .developer,
                ]) { workspace in
                    WorkspaceResultRow(workspace: workspace)
                }
            }
        }
        .listStyle(.inset)
    }
}

private struct WorkspaceResultRow: View {
    @Environment(CleanupStore.self) private var store
    let workspace: CleanupWorkspace

    var body: some View {
        let summary = store.summary(for: workspace)
        Button {
            store.selectWorkspace(workspace)
        } label: {
            HStack(spacing: DesignTokens.spacing12) {
                Image(systemName: workspace.symbol)
                    .frame(width: 22)
                    .foregroundStyle(.secondary)

                Text(workspace.title)
                    .font(.body)

                Spacer()

                if summary.protected > 0 {
                    Label(DisplayFormatting.count(summary.protected), systemImage: "lock.fill")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .help("보호 항목")
                }

                Text(resultStatus(summary: summary))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 132, alignment: .trailing)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .frame(minHeight: 38)
        }
        .buttonStyle(.plain)
        .help("\(workspace.title) 열기")
    }

    private func resultStatus(summary: (count: Int, bytes: Int64, protected: Int)) -> String {
        if summary.count > 0 {
            return "\(DisplayFormatting.count(summary.count))개 · \(DisplayFormatting.bytes(summary.bytes))"
        }
        return store.hasScanned(workspace) ? "항목 없음" : "스캔 전"
    }
}
