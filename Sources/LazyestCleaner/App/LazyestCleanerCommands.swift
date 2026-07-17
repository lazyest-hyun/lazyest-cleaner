import SwiftUI

struct LazyestCleanerCommands: Commands {
    let store: CleanupStore

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            ActionCommandButton(store: store, action: .openSettings)
        }

        CommandGroup(replacing: .newItem) {
            ActionCommandButton(store: store, action: .addLocation)
        }

        CommandMenu("스캔") {
            ActionCommandButton(store: store, action: .scanAll)
            ActionCommandButton(store: store, action: .scan)
            ActionCommandButton(store: store, action: .cancelScan)
        }

        CommandMenu("선택") {
            ActionCommandButton(store: store, action: .selectRecommended)
            ActionCommandButton(store: store, action: .selectAll)
            ActionCommandButton(store: store, action: .clearSelection)
        }

        CommandMenu("정리") {
            ActionCommandButton(store: store, action: .moveToTrash)
            ActionCommandButton(store: store, action: .removeImmediately)
            Divider()
            ActionCommandButton(store: store, action: .removeApplicationOnly)
            ActionCommandButton(store: store, action: .removeAppData)
            ActionCommandButton(store: store, action: .uninstallApplication)
            Divider()
            ActionCommandButton(store: store, action: .runDockerCleanup)
            Divider()
            ActionCommandButton(store: store, action: .openTrash)
        }
    }
}

private struct ActionCommandButton: View {
    let store: CleanupStore
    let action: CleanupActionID

    @ViewBuilder
    var body: some View {
        let resolution = store.resolution(for: action)
        let button = Button(
            resolution.descriptor.title,
            systemImage: resolution.descriptor.systemImage,
            role: resolution.descriptor.role == .destructive ? .destructive : nil
        ) {
            store.requestAction(action)
        }
        .disabled(!resolution.isEnabled)

        if let shortcut = resolution.descriptor.shortcut {
            button.keyboardShortcut(
                KeyEquivalent(shortcut.key),
                modifiers: shortcut.modifiers.eventModifiers
            )
        } else {
            button
        }
    }
}

private extension ShortcutModifiers {
    var eventModifiers: EventModifiers {
        var result: EventModifiers = []
        if contains(.command) { result.insert(.command) }
        if contains(.option) { result.insert(.option) }
        if contains(.shift) { result.insert(.shift) }
        return result
    }
}
