import SwiftUI

struct ConfirmationSheet: View {
    @Environment(CleanupStore.self) private var store
    let request: CleanupConfirmationRequest

    @State private var acknowledged = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DesignTokens.spacing12) {
                Image(systemName: request.descriptor.systemImage)
                    .font(.title2)
                    .foregroundStyle(request.highestRisk >= .sensitive ? .red : .primary)
                    .frame(width: 34)
                Text(request.descriptor.title)
                    .font(.title2.weight(.semibold))
                Spacer()
                RiskMarkView(risk: request.highestRisk, compact: true)
            }
            .padding(DesignTokens.spacing16)

            Divider()

            HStack(spacing: DesignTokens.spacing24) {
                ConfirmationMetric(title: "항목", value: DisplayFormatting.count(request.items.count))
                ConfirmationMetric(title: "크기", value: DisplayFormatting.bytes(request.bytes))
                ConfirmationMetric(title: "방식", value: request.descriptor.title)
                Spacer()
            }
            .padding(DesignTokens.spacing16)

            List(Array(request.items.prefix(12))) { item in
                HStack(spacing: DesignTokens.spacing8) {
                    ItemIconView(item: item, size: 22)
                    Text(item.name)
                        .lineLimit(1)
                    Spacer()
                    Text(DisplayFormatting.bytes(item.size))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    RiskMarkView(risk: item.risk, compact: true)
                        .frame(width: 74, alignment: .leading)
                }
            }
            .listStyle(.inset)
            if request.items.count > 12 {
                Text("외 \(DisplayFormatting.count(request.items.count - 12))개")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, DesignTokens.spacing16)
                    .padding(.bottom, DesignTokens.spacing8)
            }

            Divider()

            HStack(spacing: DesignTokens.spacing12) {
                if request.needsAcknowledgement {
                    Toggle("민감 항목 확인", isOn: $acknowledged)
                        .toggleStyle(.checkbox)
                        .help("선택한 민감 항목을 확인했습니다.")
                }
                Spacer()
                Button("취소", role: .cancel) {
                    store.dismissConfirmation()
                }
                .keyboardShortcut(.cancelAction)
                Button(request.descriptor.title, role: .destructive) {
                    store.confirmPendingAction()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(request.needsAcknowledgement && !acknowledged)
            }
            .padding(DesignTokens.spacing16)
        }
        .frame(width: 540, height: 430)
    }
}

private struct ConfirmationMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.body.monospacedDigit().weight(.medium))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
