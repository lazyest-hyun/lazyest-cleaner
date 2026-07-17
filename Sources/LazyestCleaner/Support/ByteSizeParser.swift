import Foundation

enum ByteSizeParser {
    static func parse(_ value: String) -> Int64? {
        let trimmed =
            value
            .split(separator: "(", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "") ?? ""
        guard !trimmed.isEmpty else { return nil }

        let numberText = String(trimmed.prefix { $0.isNumber || $0 == "." })
        let unitText = trimmed.dropFirst(numberText.count).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let number = Double(numberText) else { return nil }

        let multipliers: [String: Double] = [
            "B": 1,
            "KB": 1_000,
            "MB": 1_000_000,
            "GB": 1_000_000_000,
            "TB": 1_000_000_000_000,
            "KIB": 1_024,
            "MIB": 1_048_576,
            "GIB": 1_073_741_824,
            "TIB": 1_099_511_627_776,
        ]
        guard let multiplier = multipliers[unitText] else { return nil }
        return Int64(number * multiplier)
    }
}
