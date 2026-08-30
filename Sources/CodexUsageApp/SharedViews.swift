import AppKit
import SwiftUI
import UsageCore

extension Color {
    static let codexUsageCardFill = Color(nsColor: .textBackgroundColor)
    static let codexUsageCardStroke = Color.black.opacity(0.08)
}

struct StatusPill: View {
    var title: String
    var systemImage: String
    var color: Color

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(color.opacity(0.16), in: Capsule())
        .overlay {
            Capsule()
                .stroke(color.opacity(0.18), lineWidth: 1)
        }
    }
}

struct InfoCard<Content: View>: View {
    var title: String
    var titleFont: Font = .headline
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(titleFont)

            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.codexUsageCardFill,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.codexUsageCardStroke, lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MetricRow: View {
    var title: String
    var value: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Text(value)
                .font(.body.monospacedDigit().weight(.semibold))
        }
    }
}

func formatTokens(_ value: Int) -> String {
    value.formatted(.number.notation(.compactName))
}

func tokenSummary(_ usage: TokenUsage?) -> String {
    guard let usage else { return "No data" }
    return formatTokens(usage.totalTokens)
}
