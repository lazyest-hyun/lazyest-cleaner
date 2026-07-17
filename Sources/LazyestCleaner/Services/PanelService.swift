import AppKit
import Foundation

@MainActor
enum PanelService {
    static func chooseScanRoots() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "스캔 위치"
        panel.prompt = "추가"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.resolvesAliases = true
        return panel.runModal() == .OK ? panel.urls : []
    }

    static func chooseProtectedLocations() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "보호 위치"
        panel.prompt = "보호"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.resolvesAliases = true
        return panel.runModal() == .OK ? panel.urls : []
    }
}
