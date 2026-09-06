import Foundation

enum DisplayFormatting {
    static func bytes(_ value: Int64) -> String {
        value == 0 ? "0 B" : ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func date(_ value: Date?) -> String {
        guard let value else { return "-" }
        return value.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
    }

    static func count(_ value: Int) -> String {
        value.formatted(.number)
    }
}
