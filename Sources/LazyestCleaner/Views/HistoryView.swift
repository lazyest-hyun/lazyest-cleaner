import SwiftUI

struct HistoryView: View {
    @Environment(CleanupStore.self) private var store

    var body: some View {
        if store.history.isEmpty {
            ContentUnavailableView {
                Label("기록 없음", systemImage: "clock")
            }
        } else {
            Table(store.history) {
                TableColumn("날짜") { entry in
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                        .lineLimit(1)
                }
                .width(min: 130, ideal: 160)

                TableColumn("작업") { entry in
                    let descriptor = ActionCatalog.descriptor(for: entry.action)
                    Label(descriptor.title, systemImage: descriptor.systemImage)
                }
                .width(min: 130, ideal: 170)

                TableColumn("항목") { entry in
                    Text(DisplayFormatting.count(entry.itemCount))
                        .font(.callout.monospacedDigit())
                }
                .width(64)

                TableColumn("크기") { entry in
                    Text(DisplayFormatting.bytes(entry.bytes))
                        .font(.callout.monospacedDigit())
                }
                .width(min: 86, ideal: 104)

                TableColumn("결과") { entry in
                    Label(
                        entry.failed == 0 ? "완료" : "일부 실패",
                        systemImage: entry.failed == 0 ? "checkmark.circle" : "exclamationmark.triangle"
                    )
                    .foregroundStyle(entry.failed == 0 ? .green : .orange)
                }
                .width(min: 96, ideal: 112)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }
}
