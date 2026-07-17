import Foundation

struct CleanupActionContext: Sendable {
    let selectedItems: [CleanupItem]
    let visibleItems: [CleanupItem]
    let customProtectedPaths: Set<String>
    let supportsCurrentScan: Bool
    let allowImmediateRemoval: Bool
    let isScanning: Bool
    let isExecuting: Bool
    let isPreparingAction: Bool
}

enum CleanupActionResolver {
    static func resolve(
        _ action: CleanupActionID,
        context: CleanupActionContext
    ) -> ActionResolution {
        let descriptor = ActionCatalog.descriptor(for: action)
        let selected = context.selectedItems
        let selectable = selected.filter(\.isSelectable)
        let fileItems = selectable.filter { item in
            guard item.url != nil else { return false }
            if case .docker = item.operation { return false }
            return true
        }
        let dockerItems = selectable.filter {
            if case .docker = $0.operation { return true }
            return false
        }
        let applicationItems = selectable.filter {
            $0.category == .applications && $0.kind == .application
        }
        let allSelectedAreApplications =
            !selected.isEmpty
            && applicationItems.count == selected.count
        let isBusy = context.isExecuting || context.isPreparingAction

        let result: (Bool, String?, [CleanupItem])
        switch action {
        case .scan:
            result = (
                !context.isScanning && !isBusy && context.supportsCurrentScan,
                context.supportsCurrentScan ? "작업 진행 중" : "현재 화면은 스캔하지 않음",
                []
            )
        case .scanAll:
            result = (!context.isScanning && !isBusy, "작업 진행 중", [])
        case .cancelScan:
            result = (context.isScanning, "진행 중인 스캔 없음", [])
        case .selectRecommended:
            result = (
                context.visibleItems.contains { $0.isSelectable && $0.recommendation == .recommended },
                "추천 항목 없음",
                []
            )
        case .selectAll:
            result = (context.visibleItems.contains(where: \.isSelectable), "선택 가능 항목 없음", [])
        case .clearSelection:
            result = (!selected.isEmpty, "선택 없음", selected)
        case .reveal:
            result = (
                selected.count == 1 && selected.first?.url != nil,
                "파일 항목 하나 필요",
                Array(selected.prefix(1))
            )
        case .protect:
            let protectable = selected.filter {
                guard !$0.isProtected,
                    let path = $0.url?.standardizedFileURL.path
                else { return false }
                return !context.customProtectedPaths.contains(path)
            }
            result = (
                selected.count == 1 && protectable.count == 1,
                "보호할 항목 하나 필요",
                protectable
            )
        case .unprotect:
            let removable = selected.filter {
                guard let path = $0.url?.standardizedFileURL.path else { return false }
                return context.customProtectedPaths.contains(path)
            }
            result = (
                selected.count == 1 && removable.count == 1,
                "사용자 보호 항목 하나 필요",
                removable
            )
        case .moveToTrash:
            let recyclable = fileItems.filter {
                $0.kind != .trash && $0.kind != .application
            }
            result = (
                !recyclable.isEmpty && recyclable.count == selected.count,
                "파일 선택 필요",
                recyclable
            )
        case .removeImmediately:
            let allowedKinds: Set<CleanupItemKind> = [.cache, .browserCache, .developerCache, .log]
            let immediate = fileItems.filter { allowedKinds.contains($0.kind) }
            let enabled =
                context.allowImmediateRemoval
                && !immediate.isEmpty
                && immediate.count == selected.count
            let reason =
                context.allowImmediateRemoval
                ? "캐시·로그만 가능"
                : "설정에서 즉시 삭제를 켜야 함"
            result = (enabled, reason, immediate)
        case .removeApplicationOnly, .removeAppData, .uninstallApplication:
            result = (
                allSelectedAreApplications && !isBusy,
                "설치 앱 선택 필요",
                applicationItems
            )
        case .deletePermanently:
            let trashItems = fileItems.filter { $0.kind == .trash }
            result = (
                !trashItems.isEmpty && trashItems.count == selected.count,
                "휴지통 항목 선택 필요",
                trashItems
            )
        case .runDockerCleanup:
            result = (
                !dockerItems.isEmpty && dockerItems.count == selected.count,
                "Docker 항목 선택 필요",
                dockerItems
            )
        case .openTrash, .revealTrash, .openFullDiskAccess, .openSettings:
            result = (true, nil, [])
        case .addLocation:
            result = (!context.isScanning && !isBusy, "작업 진행 중", [])
        }

        return ActionResolution(
            descriptor: descriptor,
            isEnabled: result.0,
            disabledReason: result.0 ? nil : result.1,
            items: result.2
        )
    }
}
