import SwiftUI
import Darwin

@main
@MainActor
struct LazyestCleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: CleanupStore

    init() {
        if PreviewExporter.exportIfRequested() { exit(0) }
        _store = State(initialValue: CleanupStore())
    }

    var body: some Scene {
        Window("Lazyest Cleaner", id: "main") {
            ContentView()
                .environment(store)
                .tint(DesignTokens.accent)
                .accentColor(DesignTokens.accent)
        }
        .defaultSize(width: 1_180, height: 760)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            LazyestCleanerCommands(store: store)
        }
    }
}
