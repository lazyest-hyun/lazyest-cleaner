import AppKit
import SwiftUI

struct BottomActionBar: View {
    @Environment(CleanupStore.self) private var store

    var body: some View {
        HStack(spacing: DesignTokens.spacing12) {
            selectionSummary

            Spacer(minLength: DesignTokens.spacing16)

            ZStack {
                ProgressView()
                    .controlSize(.small)
                    .opacity(store.isExecuting || store.isPreparingAction ? 1 : 0)
            }
            .frame(width: 16, height: 16)
            .help(store.isPreparingAction ? "앱 데이터 확인 중" : "정리 중")

            Menu {
                actionMenu
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(
                        width: DesignTokens.iconButtonSize,
                        height: DesignTokens.iconButtonSize
                    )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("추가 동작")
            .accessibilityLabel("추가 동작")

            HStack(spacing: DesignTokens.spacing8) {
                primaryActions
            }
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(2)
        }
        .padding(.horizontal, DesignTokens.spacing16)
        .padding(.vertical, DesignTokens.spacing8)
        .frame(height: 52)
        .background(.bar)
    }

    @ViewBuilder
    private var actionMenu: some View {
        UnifiedActionMenuItem(action: .reveal)
        Divider()
        switch store.selectedCategory {
        case .applications:
            UnifiedActionMenuItem(action: .removeApplicationOnly)
            UnifiedActionMenuItem(action: .removeAppData)
            UnifiedActionMenuItem(action: .uninstallApplication)
            Divider()
            UnifiedActionMenuItem(action: .protect)
            UnifiedActionMenuItem(action: .unprotect)
        case .systemApplications:
            EmptyView()
        case .trash:
            UnifiedActionMenuItem(action: .deletePermanently)
        case .docker:
            UnifiedActionMenuItem(action: .runDockerCleanup)
        default:
            UnifiedActionMenuItem(action: .protect)
            UnifiedActionMenuItem(action: .unprotect)
            Divider()
            UnifiedActionMenuItem(action: .removeImmediately)
        }
        Divider()
        UnifiedActionMenuItem(action: .clearSelection)
    }

    @ViewBuilder
    private var primaryActions: some View {
        switch store.selectedCategory {
        case .applications:
            UnifiedActionButton(action: .removeAppData, presentation: .bordered)
            UnifiedActionButton(action: .uninstallApplication, presentation: .prominent)
        case .systemApplications:
            Label("삭제 불가", systemImage: "lock.fill")
                .font(.callout)
                .foregroundStyle(.secondary)
                .help("시스템 앱은 읽기 전용으로 표시됩니다.")
            UnifiedActionButton(action: .reveal, presentation: .bordered)
        case .trash:
            UnifiedActionButton(action: .deletePermanently, presentation: .prominent)
        case .docker:
            UnifiedActionButton(action: .runDockerCleanup, presentation: .prominent)
        default:
            UnifiedActionButton(action: .moveToTrash, presentation: .prominent)
        }
    }

    @ViewBuilder
    private var selectionSummary: some View {
        if store.selectedItems.count == 1,
            let item = store.selectedItems.first
        {
            ItemIconView(item: item, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(item.url?.path ?? item.source)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(-1)
            .help("\(item.url?.path ?? item.source)\n\(DisplayFormatting.bytes(item.size))")
            .contextMenu {
                if let path = item.url?.path {
                    Button("경로 복사") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(path, forType: .string)
                    }
                }
            }
        } else {
            Label(
                "\(DisplayFormatting.count(store.selectedItems.count))개",
                systemImage: "checkmark.square"
            )
            .font(.callout)
            Text(DisplayFormatting.bytes(store.selectedBytes))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
