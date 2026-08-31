import CodexUsageCore
import SwiftUI
import UsageCore

enum CodexUsageWidgetPalette: String, CaseIterable, Identifiable {
    case macaronBerry = "rose"
    case macaronMint = "ocean"
    case brightBerry = "sunset"
    case brightSky
    case morandiRose
    case morandiSage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .macaronBerry:
            return "Macaron Berry"
        case .macaronMint:
            return "Macaron Mint"
        case .brightBerry:
            return "Bright Berry"
        case .brightSky:
            return "Bright Sky"
        case .morandiRose:
            return "Morandi Rose"
        case .morandiSage:
            return "Morandi Sage"
        }
    }

    var referenceLineColor: Color {
        switch self {
        case .macaronBerry:
            return Color(
                red: 155.0 / 255.0,
                green: 127.0 / 255.0,
                blue: 232.0 / 255.0
            )
        case .macaronMint:
            return Color(
                red: 111.0 / 255.0,
                green: 141.0 / 255.0,
                blue: 221.0 / 255.0
            )
        case .brightBerry:
            return Color(
                red: 115.0 / 255.0,
                green: 87.0 / 255.0,
                blue: 255.0 / 255.0
            )
        case .brightSky:
            return Color(
                red: 109.0 / 255.0,
                green: 93.0 / 255.0,
                blue: 251.0 / 255.0
            )
        case .morandiRose:
            return Color(
                red: 124.0 / 255.0,
                green: 113.0 / 255.0,
                blue: 143.0 / 255.0
            )
        case .morandiSage:
            return Color(
                red: 122.0 / 255.0,
                green: 119.0 / 255.0,
                blue: 146.0 / 255.0
            )
        }
    }

    var usageLineColor: Color {
        switch self {
        case .macaronBerry:
            return Color(
                red: 255.0 / 255.0,
                green: 107.0 / 255.0,
                blue: 154.0 / 255.0
            )
        case .macaronMint:
            return Color(
                red: 34.0 / 255.0,
                green: 199.0 / 255.0,
                blue: 184.0 / 255.0
            )
        case .brightBerry:
            return Color(
                red: 255.0 / 255.0,
                green: 45.0 / 255.0,
                blue: 114.0 / 255.0
            )
        case .brightSky:
            return Color(
                red: 0.0 / 255.0,
                green: 166.0 / 255.0,
                blue: 255.0 / 255.0
            )
        case .morandiRose:
            return Color(
                red: 185.0 / 255.0,
                green: 103.0 / 255.0,
                blue: 124.0 / 255.0
            )
        case .morandiSage:
            return Color(
                red: 107.0 / 255.0,
                green: 143.0 / 255.0,
                blue: 113.0 / 255.0
            )
        }
    }

}

struct CodexUsagePalettePicker: View {
    @ObservedObject var controller: CodexUsageDesktopWidgetController

    var body: some View {
        HStack(spacing: 8) {
            Text("Color")
                .font(.caption)

            Spacer()

            HStack(spacing: 4) {
                Circle()
                    .fill(controller.palette.referenceLineColor)
                Circle()
                    .fill(controller.palette.usageLineColor)
            }
            .frame(width: 24, height: 10)
            .accessibilityHidden(true)

            Picker(
                "Color",
                selection: Binding(
                    get: { controller.palette },
                    set: { controller.selectPalette($0) }
                )
            ) {
                ForEach(CodexUsageWidgetPalette.allCases) { palette in
                    Text(palette.title).tag(palette)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(width: 138)
        }
    }
}

struct CodexUsageDesktopWidgetView: View {
    @ObservedObject var viewModel: AgentUsageViewModel
    @ObservedObject var controller: CodexUsageDesktopWidgetController

    private var status: ProviderStatus? {
        viewModel.snapshot.status(for: .codex)
    }

    private var primaryLimit: RollingLimit? {
        status?.primaryLimit
    }

    private var elapsedTimeProgress: CGFloat? {
        guard let primaryLimit else { return nil }
        return CodexUsageWidgetPresentation.elapsedTimeProgress(
            windowMinutes: primaryLimit.windowMinutes,
            resetsAt: primaryLimit.resetsAt
        ).map { CGFloat($0) }
    }

    private var consumedUsageProgress: CGFloat {
        guard let primaryLimit else { return 0 }
        return CGFloat(
            CodexUsageWidgetPresentation.consumedUsageProgress(
                usedPercent: primaryLimit.usedPercent
            )
        )
    }

    private var pacePoints: [CodexUsagePacePoint] {
        guard let primaryLimit else { return [] }
        return CodexUsageWidgetPresentation.paceChartPoints(
            samples: controller.paceSamples,
            usedPercent: primaryLimit.usedPercent,
            windowMinutes: primaryLimit.windowMinutes,
            resetsAt: primaryLimit.resetsAt,
            now: viewModel.snapshot.generatedAt
        )
    }

    var body: some View {
        rectangularCard
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
            .overlay(alignment: .bottomTrailing) {
                if controller.isResizeHandleHovered {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.42))
                        .frame(width: 28, height: 28)
                        .padding(12)
                        .accessibilityLabel("Resize Codex usage widget")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilitySummary)
    }

    private var widgetBackgroundColor: Color {
        Color(
            red: 31.0 / 255.0,
            green: 31.0 / 255.0,
            blue: 32.0 / 255.0
        )
    }

    private var chartBackgroundColor: Color {
        Color(
            red: 24.0 / 255.0,
            green: 24.0 / 255.0,
            blue: 25.0 / 255.0
        )
    }

    private var resetSignalColor: Color {
        Color(
            red: 255.0 / 255.0,
            green: 122.0 / 255.0,
            blue: 46.0 / 255.0
        )
    }

    private var summaryAccentColor: Color {
        controller.palette.usageLineColor
    }

    private var rectangularCard: some View {
        VStack(spacing: 14) {
            widgetHeader

            HStack(alignment: .center, spacing: 18) {
                paceChart
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)

                usageSummary
                    .frame(
                        minWidth: 126,
                        idealWidth: 154,
                        maxWidth: 174,
                        maxHeight: .infinity,
                        alignment: .leading
                    )
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(widgetBackgroundColor)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                }
        }
    }

    private var widgetHeader: some View {
        HStack {
            Text("Codex")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.72))

            Spacer()

            resetRadarBadge
        }
    }

    @ViewBuilder
    private var resetRadarBadge: some View {
        if let watch = viewModel.resetRadar?.activeWatch {
            Button {
                controller.openResetSource(watch.source.url)
            } label: {
                HStack(spacing: 6) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.58))

                        Circle()
                            .fill(resetSignalColor)
                            .frame(width: 4, height: 4)
                            .offset(x: 2, y: -1)
                    }

                    Text(resetWatchBadgeLabel(watch))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text("Tibo")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            controller.isResetSignalBadgeHovered
                                ? Color.white.opacity(0.06)
                                : Color.clear
                        )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "Reset signal from Tibo, \(resetSignalForecast(watch))"
            )
            .accessibilityAddTraits(.isButton)
            .help("Open Tibo's post on X")
        } else if let label = CodexResetRadarPresentation.widgetBadge(
            snapshot: viewModel.resetRadar,
            now: viewModel.snapshot.generatedAt
        ) {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.white.opacity(0.42))
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(Color.white.opacity(0.58))
            }
        }
    }

    private func resetWatchBadgeLabel(_ watch: CodexResetWatch) -> String {
        if let chance = watch.resetChancePercent {
            return "Reset \(chance)% · \(watch.forecastWindow)"
        }
        return "Reset · \(watch.forecastWindow)"
    }

    private func resetSignalForecast(_ watch: CodexResetWatch) -> String {
        if let chance = watch.resetChancePercent {
            return "\(chance)% · \(watch.forecastWindow)"
        }
        return watch.forecastWindow
    }

    private var usageSummary: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(usedPercentNumber)
                    .font(.system(size: 50, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .tracking(-2.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .layoutPriority(1)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                summaryAccentColor.opacity(0.72),
                                summaryAccentColor
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("% USED")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(Color.white.opacity(0.68))
                    .fixedSize()
            }

            Spacer(minLength: 10)

            Text(resetLabel)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.top, 2)
            stackedSummaryMetric(
                title: "CYCLE TOKENS",
                value: "\(tokenCountLabel) tokens"
            )
        }
    }

    private func stackedSummaryMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundColor(Color.white.opacity(0.4))
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(Color.white.opacity(0.56))
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.top, 6)
    }

    private var usedPercentNumber: String {
        "\(Int((consumedUsageProgress * 100).rounded()))"
    }

    private var tokenCountLabel: String {
        guard let tokens = viewModel.snapshot.codexCurrentCycleUsage?.tokens else {
            return "--"
        }
        return formatTokens(tokens)
    }

    private var resetLabel: String {
        guard let resetsAt = primaryLimit?.resetsAt else { return "Reset unavailable" }
        return CodexUsageWidgetPresentation.resetCountdown(
            resetsAt: resetsAt,
            now: viewModel.snapshot.generatedAt
        )
    }

    private var paceChart: some View {
        Canvas { context, size in
            let plotRect = CGRect(origin: .zero, size: size)

            let referencePath = Path { path in
                path.move(
                    to: CGPoint(x: plotRect.minX, y: plotRect.maxY)
                )
                path.addLine(
                    to: CGPoint(x: plotRect.maxX, y: plotRect.minY)
                )
            }
            context.stroke(
                referencePath,
                with: .color(controller.palette.referenceLineColor.opacity(0.48)),
                style: StrokeStyle(
                    lineWidth: 1.5,
                    lineCap: .round,
                    dash: [3, 4]
                )
            )

            let steppedPoints =
                CodexUsageWidgetPresentation.steppedPaceChartPoints(
                    pacePoints
                )
            let chartPoints = steppedPoints.map { point in
                CGPoint(
                    x: plotRect.minX
                        + plotRect.width * CGFloat(point.timeProgress),
                    y: plotRect.maxY
                        - plotRect.height * CGFloat(point.usageProgress)
                )
            }

            if chartPoints.count > 1 {
                let usagePath = roundedStepPath(
                    chartPoints,
                    cornerRadius: 3
                )
                let fillPath = Path { path in
                    path.move(
                        to: CGPoint(
                            x: chartPoints[0].x,
                            y: plotRect.maxY
                        )
                    )
                    path.addLine(to: chartPoints[0])
                    for point in chartPoints.dropFirst() {
                        path.addLine(to: point)
                    }
                    if let latestPoint = chartPoints.last {
                        path.addLine(
                            to: CGPoint(x: latestPoint.x, y: plotRect.maxY)
                        )
                    }
                    path.closeSubpath()
                }
                context.fill(
                    fillPath,
                    with: .color(controller.palette.usageLineColor.opacity(0.12))
                )
                context.stroke(
                    usagePath,
                    with: .color(controller.palette.usageLineColor),
                    style: StrokeStyle(
                        lineWidth: 3,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }

            if let latestPoint = chartPoints.last {
                let marker = CGRect(
                    x: latestPoint.x - 4,
                    y: latestPoint.y - 4,
                    width: 8,
                    height: 8
                )
                context.fill(
                    Path(ellipseIn: marker),
                    with: .color(controller.palette.usageLineColor)
                )
                context.stroke(
                    Path(ellipseIn: marker),
                    with: .color(chartBackgroundColor),
                    lineWidth: 2
                )
            }

        }
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(chartBackgroundColor)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            Color.white.opacity(0.045),
                            lineWidth: 1
                        )
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityHidden(true)
    }

    private func roundedStepPath(
        _ points: [CGPoint],
        cornerRadius: CGFloat
    ) -> Path {
        let points = points.reduce(into: [CGPoint]()) { result, point in
            guard result.last != point else { return }
            result.append(point)
        }
        guard points.count > 2 else {
            return Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
            }
        }

        return Path { path in
            path.move(to: points[0])
            for index in 1..<(points.count - 1) {
                let previous = points[index - 1]
                let corner = points[index]
                let next = points[index + 1]
                let incoming = hypot(
                    corner.x - previous.x,
                    corner.y - previous.y
                )
                let outgoing = hypot(
                    next.x - corner.x,
                    next.y - corner.y
                )
                guard incoming > 0, outgoing > 0 else {
                    path.addLine(to: corner)
                    continue
                }
                let radius = min(
                    cornerRadius,
                    incoming / 2,
                    outgoing / 2
                )
                let before = CGPoint(
                    x: corner.x
                        - (corner.x - previous.x) / incoming * radius,
                    y: corner.y
                        - (corner.y - previous.y) / incoming * radius
                )
                let after = CGPoint(
                    x: corner.x
                        + (next.x - corner.x) / outgoing * radius,
                    y: corner.y
                        + (next.y - corner.y) / outgoing * radius
                )
                path.addLine(to: before)
                path.addQuadCurve(to: after, control: corner)
            }
            path.addLine(to: points[points.count - 1])
        }
    }

    private var accessibilitySummary: String {
        guard primaryLimit != nil else {
            return "Codex usage unavailable"
        }
        let elapsedPercent = Int(
            ((elapsedTimeProgress ?? 0) * 100).rounded()
        )
        let usedPercent = Int((consumedUsageProgress * 100).rounded())
        let usageSummary = "Codex usage, \(usedPercent) percent consumed, "
            + "\(elapsedPercent) percent of time elapsed"
        guard let watch = viewModel.resetRadar?.activeWatch else {
            return usageSummary
        }
        let signalLevel = watch.level == .strong
            ? "Strong signal"
            : "Elevated signal"
        return "\(signalLevel), possible reset \(resetSignalForecast(watch)), "
            + "community prediction. \(usageSummary)"
    }
}
