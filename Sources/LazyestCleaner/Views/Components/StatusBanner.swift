import SwiftUI

struct StatusBanner: View {
    @Environment(CleanupStore.self) private var store
    let notice: CleanupNotice

    var body: some View {
        HStack(spacing: DesignTokens.spacing8) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text(notice.message)
                .font(.callout)
                .lineLimit(1)
            Spacer()
            Button {
                store.clearNotice()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("닫기")
            .accessibilityLabel("닫기")
        }
        .padding(.horizontal, DesignTokens.spacing12)
        .padding(.vertical, DesignTokens.spacing8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
                .stroke(.separator.opacity(0.7), lineWidth: 1)
        }
    }

    private var symbol: String {
        switch notice.kind {
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch notice.kind {
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }
}
