import SwiftUI

struct CleanupDetailView: View {
    @Environment(CleanupStore.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            DetailHeader()
            Divider()
            ScanProgressTrack()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            BottomActionBar()
        }
        .searchable(text: $store.searchText, placement: .toolbar, prompt: "항목 검색")
    }

    @ViewBuilder
    private var content: some View {
        if !store.currentItems.isEmpty {
            CleanupTableView()
        } else if let issue = store.scanIssue(for: store.selectedCategory) {
            ScanIssueView(issue: issue)
        } else if store.isScanning && store.scanningCategory == store.selectedCategory {
            ContentUnavailableView {
                Label("스캔 중", systemImage: "externaldrive.badge.timemachine")
            }
        } else if store.selectedCategory == .custom && store.settings.customScanRoots.isEmpty {
            ContentUnavailableView {
                Label("위치 없음", systemImage: "folder.badge.plus")
            } actions: {
                UnifiedActionButton(action: .addLocation, presentation: .bordered)
            }
        } else if store.scannedCategories.contains(store.selectedCategory) {
            ContentUnavailableView {
                Label(
                    store.selectedCategory == .trash ? "휴지통 비어 있음" : "결과 없음",
                    systemImage: "checkmark.circle"
                )
            } actions: {
                UnifiedActionButton(action: .scan, presentation: .bordered)
            }
        } else {
            ContentUnavailableView {
                Label("스캔 필요", systemImage: "magnifyingglass")
            } actions: {
                UnifiedActionButton(action: .scan, presentation: .prominent)
            }
        }
    }
}

private struct ScanProgressTrack: View {
    @Environment(CleanupStore.self) private var store

    var body: some View {
        ZStack {
            Color.clear
            if store.isScanning {
                if store.scanTotalCount > 1, let progress = store.scanProgress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                }
            }
        }
        .frame(height: 3)
        .help(store.scanStatusTitle ?? "스캔 대기")
        .accessibilityLabel(store.scanStatusTitle ?? "스캔 대기")
    }
}

private struct ScanIssueView: View {
    @Environment(CleanupStore.self) private var store
    let issue: CleanupScanIssue

    var body: some View {
        ContentUnavailableView {
            Label(issue.title, systemImage: issue.kind.symbol)
                .help(issue.detail)
        } actions: {
            if issue.kind == .permissionDenied {
                UnifiedActionButton(action: .openFullDiskAccess, presentation: .prominent)
            } else {
                UnifiedActionButton(action: .scan, presentation: .bordered)
            }
        }
    }
}

private struct DetailHeader: View {
    @Environment(CleanupStore.self) private var store

    var body: some View {
        let categories = store.selectedWorkspace.categories.filter(\.supportsScan)
        VStack(spacing: DesignTokens.spacing8) {
            if categories.count > 1 {
                Picker("분류", selection: categorySelection) {
                    ForEach(categories) { category in
                        Text(category.title).tag(category)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .help("세부 분류를 전환합니다.")
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 28)
            } else {
                HStack {
                    Label(store.selectedCategory.title, systemImage: store.selectedCategory.symbol)
                        .font(.headline)
                    Spacer()
                }
                .frame(height: 28)
            }

            HStack(spacing: DesignTokens.spacing12) {
                Text("\(DisplayFormatting.count(store.visibleItems.count))개")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 58, alignment: .leading)
                Text(DisplayFormatting.bytes(store.visibleItems.reduce(0) { $0 + $1.size }))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 84, alignment: .leading)
                Divider()
                    .frame(height: 18)
                Text("선택 \(DisplayFormatting.bytes(store.selectedBytes))")
                    .font(.callout.monospacedDigit().weight(.medium))
                    .foregroundStyle(store.selectedItems.isEmpty ? .secondary : Color.accentColor)
                    .frame(minWidth: 112, alignment: .leading)

                Spacer()
                ZStack {
                    ProgressView()
                        .controlSize(.small)
                        .opacity(store.isPreparingAction ? 1 : 0)
                }
                .frame(width: 16, height: 16)
                .help(store.isPreparingAction ? "앱 데이터 확인 중" : "대기")
                FilterMenu()
                DetailSortMenu()
            }
            .frame(height: 28)
        }
        .padding(.horizontal, DesignTokens.spacing16)
        .frame(height: 84)
    }

    private var categorySelection: Binding<CleanupCategory> {
        Binding(
            get: { store.selectedCategory },
            set: { store.selectCategory($0) }
        )
    }
}

private struct FilterMenu: View {
    @Environment(CleanupStore.self) private var store

    var body: some View {
        Menu {
            ForEach(ItemScopeFilter.allCases) { filter in
                Button {
                    store.scopeFilter = filter
                } label: {
                    if store.scopeFilter == filter {
                        Label(filter.title, systemImage: "checkmark")
                    } else {
                        Text(filter.title)
                    }
                }
            }
        } label: {
            Label(store.scopeFilter.title, systemImage: "line.3.horizontal.decrease")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("표시 범위")
    }
}

private struct DetailSortMenu: View {
    @Environment(CleanupStore.self) private var store

    var body: some View {
        Menu {
            ForEach(CleanupSortOrder.allCases) { order in
                Button {
                    store.sortOrder = order
                } label: {
                    if store.sortOrder == order {
                        Label(order.title, systemImage: "checkmark")
                    } else {
                        Text(order.title)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .frame(width: DesignTokens.iconButtonSize, height: DesignTokens.iconButtonSize)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("정렬")
        .accessibilityLabel("정렬")
    }
}
