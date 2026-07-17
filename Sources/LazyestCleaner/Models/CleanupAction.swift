import Foundation

enum CleanupActionID: String, CaseIterable, Codable, Identifiable, Sendable {
    case scan
    case scanAll
    case cancelScan
    case selectRecommended
    case selectAll
    case clearSelection
    case reveal
    case protect
    case unprotect
    case moveToTrash
    case removeImmediately
    case removeApplicationOnly
    case removeAppData
    case uninstallApplication
    case deletePermanently
    case runDockerCleanup
    case openTrash
    case revealTrash
    case openFullDiskAccess
    case addLocation
    case openSettings

    var id: Self { self }
}

enum ActionRole: Sendable {
    case normal
    case primary
    case destructive
}

enum SelectionPolicy: Sendable {
    case none
    case single
    case any
    case fileItems
    case dockerItems
}

enum ConfirmationPolicy: Sendable {
    case none
    case standard
    case reinforced
}

struct ActionShortcut: Sendable {
    let key: Character
    let modifiers: ShortcutModifiers
}

struct ShortcutModifiers: OptionSet, Sendable {
    let rawValue: Int

    static let command = ShortcutModifiers(rawValue: 1 << 0)
    static let option = ShortcutModifiers(rawValue: 1 << 1)
    static let shift = ShortcutModifiers(rawValue: 1 << 2)
}

struct ActionDescriptor: Identifiable, Sendable {
    let id: CleanupActionID
    let title: String
    let systemImage: String
    let tooltip: String
    let role: ActionRole
    let selectionPolicy: SelectionPolicy
    let confirmation: ConfirmationPolicy
    let shortcut: ActionShortcut?
}

enum ActionCatalog {
    static func descriptor(for action: CleanupActionID) -> ActionDescriptor {
        switch action {
        case .scan:
            ActionDescriptor(
                id: action, title: "다시 스캔", systemImage: "arrow.clockwise", tooltip: "현재 분류를 다시 스캔합니다.", role: .normal,
                selectionPolicy: .none, confirmation: .none, shortcut: .init(key: "r", modifiers: [.command]))
        case .scanAll:
            ActionDescriptor(
                id: action, title: "전체 스캔", systemImage: "magnifyingglass", tooltip: "설정된 작업군을 차례로 스캔합니다.",
                role: .primary, selectionPolicy: .none, confirmation: .none,
                shortcut: .init(key: "r", modifiers: [.command, .shift]))
        case .cancelScan:
            ActionDescriptor(
                id: action, title: "중단", systemImage: "xmark", tooltip: "진행 중인 스캔을 중단합니다.", role: .normal,
                selectionPolicy: .none, confirmation: .none, shortcut: .init(key: ".", modifiers: [.command]))
        case .selectRecommended:
            ActionDescriptor(
                id: action, title: "추천 선택", systemImage: "checkmark.circle", tooltip: "안전하고 추천된 항목만 선택합니다.",
                role: .normal, selectionPolicy: .none, confirmation: .none,
                shortcut: .init(key: "a", modifiers: [.command, .shift]))
        case .selectAll:
            ActionDescriptor(
                id: action, title: "모두 선택", systemImage: "checkmark.square", tooltip: "현재 목록에서 실행 가능한 항목을 모두 선택합니다.",
                role: .normal, selectionPolicy: .none, confirmation: .none, shortcut: nil)
        case .clearSelection:
            ActionDescriptor(
                id: action, title: "선택 해제", systemImage: "xmark.circle", tooltip: "현재 선택을 모두 해제합니다.", role: .normal,
                selectionPolicy: .any, confirmation: .none, shortcut: .init(key: "d", modifiers: [.command, .shift]))
        case .reveal:
            ActionDescriptor(
                id: action, title: "Finder에서 보기", systemImage: "folder", tooltip: "선택한 항목을 Finder에서 표시합니다.",
                role: .normal, selectionPolicy: .single, confirmation: .none,
                shortcut: .init(key: "f", modifiers: [.command, .option]))
        case .protect:
            ActionDescriptor(
                id: action, title: "보호", systemImage: "lock", tooltip: "선택한 경로를 이후 정리에서 제외합니다.", role: .normal,
                selectionPolicy: .fileItems, confirmation: .none, shortcut: nil)
        case .unprotect:
            ActionDescriptor(
                id: action, title: "보호 해제", systemImage: "lock.open", tooltip: "사용자가 추가한 보호 규칙을 제거합니다.", role: .normal,
                selectionPolicy: .fileItems, confirmation: .standard, shortcut: nil)
        case .moveToTrash:
            ActionDescriptor(
                id: action, title: "휴지통으로", systemImage: "trash", tooltip: "선택한 파일을 복구 가능한 휴지통으로 이동합니다.",
                role: .primary, selectionPolicy: .fileItems, confirmation: .standard,
                shortcut: .init(key: "\u{8}", modifiers: [.command]))
        case .removeImmediately:
            ActionDescriptor(
                id: action, title: "즉시 삭제", systemImage: "eraser", tooltip: "허용된 캐시와 로그를 휴지통을 거치지 않고 삭제합니다.",
                role: .destructive, selectionPolicy: .fileItems, confirmation: .reinforced, shortcut: nil)
        case .removeApplicationOnly:
            ActionDescriptor(
                id: action, title: "앱만 삭제", systemImage: "minus.square", tooltip: "선택한 앱만 휴지통으로 이동하고 사용자 데이터는 유지합니다.",
                role: .destructive, selectionPolicy: .fileItems, confirmation: .standard,
                shortcut: .init(key: "\u{8}", modifiers: [.command]))
        case .removeAppData:
            ActionDescriptor(
                id: action, title: "데이터만 삭제", systemImage: "externaldrive.badge.minus",
                tooltip: "선택한 앱은 유지하고 연결된 사용자 데이터만 휴지통으로 이동합니다.", role: .destructive, selectionPolicy: .fileItems,
                confirmation: .reinforced, shortcut: nil)
        case .uninstallApplication:
            ActionDescriptor(
                id: action, title: "앱 + 데이터 삭제", systemImage: "trash.slash",
                tooltip: "선택한 앱과 확인된 연결 데이터를 함께 휴지통으로 이동합니다.", role: .destructive, selectionPolicy: .fileItems,
                confirmation: .reinforced, shortcut: nil)
        case .deletePermanently:
            ActionDescriptor(
                id: action, title: "영구 삭제", systemImage: "trash.slash", tooltip: "선택한 휴지통 항목을 복구할 수 없게 삭제합니다.",
                role: .destructive, selectionPolicy: .fileItems, confirmation: .reinforced, shortcut: nil)
        case .runDockerCleanup:
            ActionDescriptor(
                id: action, title: "Docker 정리", systemImage: "shippingbox",
                tooltip: "선택한 미사용 Docker 리소스에 prune 명령을 실행합니다.", role: .destructive, selectionPolicy: .dockerItems,
                confirmation: .reinforced, shortcut: nil)
        case .openTrash:
            ActionDescriptor(
                id: action, title: "휴지통 보기", systemImage: "trash", tooltip: "앱에서 휴지통을 열고 내용을 스캔합니다.", role: .normal,
                selectionPolicy: .none, confirmation: .none, shortcut: nil)
        case .revealTrash:
            ActionDescriptor(
                id: action, title: "Finder에서 열기", systemImage: "folder", tooltip: "Finder에서 현재 사용자의 휴지통을 엽니다.",
                role: .normal, selectionPolicy: .none, confirmation: .none, shortcut: nil)
        case .openFullDiskAccess:
            ActionDescriptor(
                id: action, title: "설정에서 허용", systemImage: "gearshape",
                tooltip: "macOS 전체 디스크 접근 설정을 열고 돌아오면 자동으로 다시 스캔합니다.", role: .normal, selectionPolicy: .none,
                confirmation: .none, shortcut: nil)
        case .addLocation:
            ActionDescriptor(
                id: action, title: "위치 추가", systemImage: "folder.badge.plus", tooltip: "스캔할 폴더를 추가합니다.", role: .normal,
                selectionPolicy: .none, confirmation: .none, shortcut: nil)
        case .openSettings:
            ActionDescriptor(
                id: action, title: "설정", systemImage: "gearshape", tooltip: "앱 설정을 엽니다.", role: .normal,
                selectionPolicy: .none, confirmation: .none, shortcut: .init(key: ",", modifiers: [.command]))
        }
    }
}
