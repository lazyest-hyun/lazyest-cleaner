import SwiftUI

@main
@MainActor
struct LazyestCleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = CleanupStore()

    var body: some Scene {
        Window("Lazyest Cleaner", id: "main") {
            ContentView()
                .environment(store)
        }
        .defaultSize(width: 1_180, height: 760)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            LazyestCleanerCommands(store: store)
        }
    }
}
