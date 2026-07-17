import SwiftUI

struct RiskMarkView: View {
    let risk: CleanupRisk
    var compact = false

    var body: some View {
        HStack(spacing: compact ? DesignTokens.spacing4 : DesignTokens.spacing8) {
            Image(systemName: risk.symbol)
                .frame(width: 16)
            Text(risk.title)
        }
        .foregroundStyle(tint)
        .font(.callout)
        .lineLimit(1)
        .help(tooltip)
        .accessibilityLabel(risk.title)
    }

    private var tint: Color {
        switch risk {
        case .safe: .green
        case .review: .orange
        case .sensitive: .red
        case .protected: .secondary
        }
    }

    private var tooltip: String {
        switch risk {
        case .safe: "재생성 가능한 데이터입니다."
        case .review: "삭제 전에 내용을 확인해야 합니다."
        case .sensitive: "프로젝트나 앱 상태에 영향을 줄 수 있습니다."
        case .protected: "보호 규칙 때문에 실행할 수 없습니다."
        }
    }
}
