import Foundation

struct CleanupHistoryEntry: Identifiable, Codable, Sendable {
    let id: UUID
    let date: Date
    let action: CleanupActionID
    let itemCount: Int
    let bytes: Int64
    let succeeded: Int
    let failed: Int
}

struct CleanupExecutionFailure: Identifiable, Sendable {
    let id = UUID()
    let itemID: String
    let name: String
    let reason: String
}

struct CleanupExecutionReport: Sendable {
    let action: CleanupActionID
    let itemCount: Int
    let bytes: Int64
    let succeeded: Int
    let failures: [CleanupExecutionFailure]

    var historyEntry: CleanupHistoryEntry {
        CleanupHistoryEntry(
            id: UUID(),
            date: Date(),
            action: action,
            itemCount: itemCount,
            bytes: bytes,
            succeeded: succeeded,
            failed: failures.count
        )
    }
}
