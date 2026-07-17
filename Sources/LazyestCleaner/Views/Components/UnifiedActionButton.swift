import SwiftUI

enum ActionButtonPresentation {
    case iconOnly
    case bordered
    case prominent
}

struct UnifiedActionButton: View {
    @Environment(CleanupStore.self) private var store

    let action: CleanupActionID
    var presentation: ActionButtonPresentation = .bordered

    var body: some View {
        let resolution = store.resolution(for: action)
        let descriptor = resolution.descriptor

        Group {
            switch presentation {
            case .iconOnly:
                Button(role: buttonRole) {
                    store.requestAction(action)
                } label: {
                    Image(systemName: descriptor.systemImage)
                        .frame(
                            width: DesignTokens.iconButtonSize,
                            height: DesignTokens.iconButtonSize
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            case .bordered:
                Button(role: buttonRole) {
                    store.requestAction(action)
                } label: {
                    Label(descriptor.title, systemImage: descriptor.systemImage)
                }
                .buttonStyle(.bordered)
            case .prominent:
                Button(role: buttonRole) {
                    store.requestAction(action)
                } label: {
                    Label(descriptor.title, systemImage: descriptor.systemImage)
                }
                .buttonStyle(.borderedProminent)
                .tint(descriptor.role == .destructive ? .red : .accentColor)
            }
        }
        .disabled(!resolution.isEnabled)
        .help(helpText(for: resolution))
        .accessibilityLabel(descriptor.title)
    }

    private var buttonRole: ButtonRole? {
        ActionCatalog.descriptor(for: action).role == .destructive ? .destructive : nil
    }

    private func helpText(for resolution: ActionResolution) -> String {
        guard let disabledReason = resolution.disabledReason else {
            return resolution.descriptor.tooltip
        }
        return "\(resolution.descriptor.tooltip) \(disabledReason)"
    }
}

struct UnifiedActionMenuItem: View {
    @Environment(CleanupStore.self) private var store
    let action: CleanupActionID

    var body: some View {
        let resolution = store.resolution(for: action)
        Button(role: resolution.descriptor.role == .destructive ? .destructive : nil) {
            store.requestAction(action)
        } label: {
            Label(resolution.descriptor.title, systemImage: resolution.descriptor.systemImage)
        }
        .disabled(!resolution.isEnabled)
        .help(resolution.disabledReason ?? resolution.descriptor.tooltip)
    }
}
