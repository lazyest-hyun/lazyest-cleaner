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
                        .help(entry.date.formatted(date: .complete, time: .shortened))
                }
                .width(144)

                TableColumn("작업") { entry in
                    let descriptor = ActionCatalog.descriptor(for: entry.action)
                    AlignedSymbolLabel(title: descriptor.title, systemImage: descriptor.systemImage)
                        .lineLimit(1)
                        .help(descriptor.title)
                }
                .width(min: 110, ideal: 142, max: 240)

                TableColumn("항목") { entry in
                    Text(DisplayFormatting.count(entry.itemCount))
                        .font(.callout.monospacedDigit())
                }
                .width(44)

                TableColumn("크기") { entry in
                    Text(DisplayFormatting.bytes(entry.bytes))
                        .font(.callout.monospacedDigit())
                }
                .width(88)

                TableColumn("결과") { entry in
                    AlignedSymbolLabel(
                        title: entry.failed == 0 ? "완료" : "일부 실패",
                        systemImage: entry.failed == 0 ? "checkmark.circle" : "exclamationmark.triangle"
                    )
                    .foregroundStyle(entry.failed == 0 ? .green : .orange)
                }
                .width(100)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }
}
