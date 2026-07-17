import AppKit
import SwiftUI

@MainActor
private final class ApplicationIconCache {
    static let shared = ApplicationIconCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 256
    }

    func icon(for url: URL) -> NSImage {
        let key = url.standardizedFileURL.path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(icon, forKey: key)
        return icon
    }
}

struct ItemIconView: View {
    let item: CleanupItem
    var size: CGFloat = 20

    var body: some View {
        Group {
            if item.kind == .application, let url = item.url {
                Image(nsImage: ApplicationIconCache.shared.icon(for: url))
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: item.kind.symbol)
                    .foregroundStyle(item.isProtected ? .secondary : .primary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
