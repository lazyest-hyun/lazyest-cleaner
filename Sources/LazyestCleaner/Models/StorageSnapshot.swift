import Foundation

struct StorageSnapshot: Sendable {
    let total: Int64
    let available: Int64

    var used: Int64 {
        max(0, total - available)
    }

    var usedFraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(used) / Double(total)))
    }
}
