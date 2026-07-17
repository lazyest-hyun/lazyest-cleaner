import SwiftUI

struct CleanupTableView: View {
    @Environment(CleanupStore.self) private var store

    var body: some View {
        Table(store.visibleItems, selection: selection) {
            TableColumn("") { item in
                SelectionToggle(item: item)
            }
            .width(34)

            TableColumn("항목") { item in
                HStack(spacing: DesignTokens.spacing8) {
                    ItemIconView(item: item, size: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name)
                            .lineLimit(1)
                        Text(item.source)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if item.recommendation == .recommended && !item.isProtected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .help("추천")
                            .accessibilityLabel("추천")
                    }
                }
                .help(item.url?.path ?? item.source)
            }
            .width(min: 240, ideal: 420)

            TableColumn("크기") { item in
                Text(DisplayFormatting.bytes(item.size))
                    .font(.callout.monospacedDigit())
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 76, ideal: 90, max: 110)

            TableColumn("수정") { item in
                Text(DisplayFormatting.date(item.modifiedAt))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 82, ideal: 96, max: 116)

            TableColumn("상태") { item in
                RiskMarkView(risk: item.risk, compact: true)
            }
            .width(min: 76, ideal: 86, max: 96)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .contextMenu(forSelectionType: String.self) { ids in
            TableContextMenu(ids: ids)
        } primaryAction: { ids in
            store.setSelection(ids)
            store.requestAction(.reveal)
        }
    }

    private var selection: Binding<Set<String>> {
        Binding(
            get: { store.selectedItemIDs },
            set: { store.setSelection($0) }
        )
    }
}

private struct SelectionToggle: View {
    @Environment(CleanupStore.self) private var store
    let item: CleanupItem

    var body: some View {
        Button {
            store.toggleSelection(item)
        } label: {
            Image(systemName: symbol)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!item.isSelectable)
        .help(helpText)
        .accessibilityLabel(accessibilityText)
    }

    private var symbol: String {
        if item.isProtected { return "lock.square" }
        return store.selectedItemIDs.contains(item.id) ? "checkmark.square.fill" : "square"
    }

    private var helpText: String {
        if let protectedReason = item.protectedReason { return protectedReason }
        return store.selectedItemIDs.contains(item.id) ? "선택 해제" : "선택"
    }

    private var accessibilityText: String {
        item.isProtected ? "보호됨" : helpText
    }
}

private struct TableContextMenu: View {
    @Environment(CleanupStore.self) private var store
    let ids: Set<String>

    var body: some View {
        ContextAction(action: .reveal, ids: ids)
        Divider()
        ContextAction(action: .protect, ids: ids)
        ContextAction(action: .unprotect, ids: ids)
        Divider()
        if store.selectedCategory == .applications {
            ContextAction(action: .removeApplicationOnly, ids: ids)
            ContextAction(action: .removeAppData, ids: ids)
            ContextAction(action: .uninstallApplication, ids: ids)
        } else if store.selectedCategory == .systemApplications {
            EmptyView()
        } else if store.selectedCategory == .trash {
            ContextAction(action: .deletePermanently, ids: ids)
        } else if store.selectedCategory == .docker {
            ContextAction(action: .runDockerCleanup, ids: ids)
        } else {
            ContextAction(action: .moveToTrash, ids: ids)
            ContextAction(action: .removeImmediately, ids: ids)
        }
    }
}

private struct ContextAction: View {
    @Environment(CleanupStore.self) private var store
    let action: CleanupActionID
    let ids: Set<String>

    var body: some View {
        let resolution = store.resolution(for: action, itemIDs: ids)
        Button(role: resolution.descriptor.role == .destructive ? .destructive : nil) {
            store.requestAction(action, itemIDs: ids)
        } label: {
            Label(
                resolution.descriptor.title,
                systemImage: resolution.descriptor.systemImage
            )
        }
        .disabled(!resolution.isEnabled)
        .help(resolution.disabledReason ?? resolution.descriptor.tooltip)
    }
}
