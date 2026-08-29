import CoreGraphics
import Foundation

public struct CodexUsagePaceSample: Codable, Equatable, Sendable {
    public var capturedAt: Date
    public var usedPercent: Double
    public var windowMinutes: Int
    public var resetsAt: Date

    public init(
        capturedAt: Date,
        usedPercent: Double,
        windowMinutes: Int,
        resetsAt: Date
    ) {
        self.capturedAt = capturedAt
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
    }
}

public struct CodexUsagePacePoint: Equatable, Sendable {
    public var timeProgress: Double
    public var usageProgress: Double

    public init(timeProgress: Double, usageProgress: Double) {
        self.timeProgress = timeProgress
        self.usageProgress = usageProgress
    }
}

public struct CodexUsageTimeAxisTick: Equatable, Sendable {
    public var label: String
    public var progress: Double

    public init(label: String, progress: Double) {
        self.label = label
        self.progress = progress
    }
}

public enum CodexUsageWidgetPresentation {
    public static let resetTimeTolerance: TimeInterval = 60

    public static func squareResizeFrame(
        initialFrame: CGRect,
        horizontalMovement: CGFloat,
        downwardMovement: CGFloat,
        minimumSideLength: CGFloat,
        backingScaleFactor: CGFloat
    ) -> CGRect {
        squareResizeFrame(
            topLeftAnchor: CGPoint(
                x: initialFrame.minX,
                y: initialFrame.maxY
            ),
            initialSideLength: initialFrame.width,
            horizontalMovement: horizontalMovement,
            downwardMovement: downwardMovement,
            minimumSideLength: minimumSideLength,
            backingScaleFactor: backingScaleFactor
        )
    }

    public static func squareResizeFrame(
        topLeftAnchor: CGPoint,
        initialSideLength: CGFloat,
        horizontalMovement: CGFloat,
        downwardMovement: CGFloat,
        minimumSideLength: CGFloat,
        backingScaleFactor: CGFloat
    ) -> CGRect {
        let projectedMovement =
            (horizontalMovement + downwardMovement) / 2
        let proposedSideLength = max(
            minimumSideLength,
            initialSideLength + projectedMovement
        )
        let scale = max(backingScaleFactor, 1)
        let sideLength = (proposedSideLength * scale).rounded() / scale
        return CGRect(
            x: topLeftAnchor.x,
            y: topLeftAnchor.y - sideLength,
            width: sideLength,
            height: sideLength
        )
    }

    public static func periodLabel(minutes: Int) -> String {
        guard minutes > 0 else { return "Usage quota" }
        if minutes.isMultiple(of: 1_440) {
            return "\(minutes / 1_440)-day quota"
        }
        if minutes.isMultiple(of: 60) {
            return "\(minutes / 60)-hour quota"
        }
        return "\(minutes)-minute quota"
    }

    public static func timeAxisTicks(
        windowMinutes: Int
    ) -> [CodexUsageTimeAxisTick] {
        guard windowMinutes == 7 * 1_440 else { return [] }
        return (1...7).map { day in
            CodexUsageTimeAxisTick(
                label: String(day),
                progress: Double(day) / 7
            )
        }
    }

    public static func accessibilitySummary(
        windowMinutes: Int,
        remainingPercent: Int
    ) -> String {
        let period = periodLabel(minutes: windowMinutes)
            .replacingOccurrences(of: " quota", with: "")
        return "\(period) Codex quota, \(remainingPercent) percent remaining"
    }

    public static func statusLabel(remainingPercent: Double) -> String {
        switch remainingPercent {
        case 60...:
            return "Plenty remaining"
        case 30..<60:
            return "Half remaining"
        case 10..<30:
            return "Running low"
        default:
            return "Almost exhausted"
        }
    }

    public static func resetCountdown(resetsAt: Date, now: Date = Date()) -> String {
        let totalMinutes = max(0, Int(resetsAt.timeIntervalSince(now) / 60))
        if totalMinutes == 0 {
            return "Resetting now"
        }

        let days = totalMinutes / 1_440
        let hours = (totalMinutes % 1_440) / 60
        let minutes = totalMinutes % 60
        if days > 0 {
            return "Resets in \(days)d \(hours)h"
        }
        if hours > 0 {
            return "Resets in \(hours)h \(minutes)m"
        }
        return "Resets in \(minutes)m"
    }

    public static func elapsedTimeProgress(
        windowMinutes: Int,
        resetsAt: Date?,
        now: Date = Date()
    ) -> Double? {
        guard windowMinutes > 0, let resetsAt else { return nil }
        let windowSeconds = Double(windowMinutes * 60)
        let remainingSeconds = resetsAt.timeIntervalSince(now)
        return min(max(1 - remainingSeconds / windowSeconds, 0), 1)
    }

    public static func consumedUsageProgress(usedPercent: Double) -> Double {
        min(max(usedPercent / 100, 0), 1)
    }

    public static func paceChartPoints(
        samples: [CodexUsagePaceSample],
        usedPercent: Double,
        windowMinutes: Int,
        resetsAt: Date?,
        now: Date = Date()
    ) -> [CodexUsagePacePoint] {
        guard windowMinutes > 0, let resetsAt else { return [] }
        let windowDuration = TimeInterval(windowMinutes * 60)
        let windowStart = resetsAt.addingTimeInterval(-windowDuration)
        let matchingSamples = samples.filter {
            $0.windowMinutes == windowMinutes
                && abs($0.resetsAt.timeIntervalSince(resetsAt))
                    < resetTimeTolerance
        }
        let currentSample = CodexUsagePaceSample(
            capturedAt: now,
            usedPercent: usedPercent,
            windowMinutes: windowMinutes,
            resetsAt: resetsAt
        )

        let sampledPoints = (matchingSamples + [currentSample])
            .sorted { $0.capturedAt < $1.capturedAt }
            .map { sample in
                CodexUsagePacePoint(
                    timeProgress: min(
                        max(
                            sample.capturedAt.timeIntervalSince(windowStart)
                                / windowDuration,
                            0
                        ),
                        1
                    ),
                    usageProgress: consumedUsageProgress(
                        usedPercent: sample.usedPercent
                    )
                )
            }

        let origin = CodexUsagePacePoint(
            timeProgress: 0,
            usageProgress: 0
        )
        guard sampledPoints.first != origin else { return sampledPoints }
        return [origin] + sampledPoints
    }

    public static func steppedPaceChartPoints(
        _ points: [CodexUsagePacePoint]
    ) -> [CodexUsagePacePoint] {
        guard let first = points.first else { return [] }
        var stepped = [first]
        for point in points.dropFirst() {
            let previous = stepped[stepped.count - 1]
            stepped.append(
                CodexUsagePacePoint(
                    timeProgress: point.timeProgress,
                    usageProgress: previous.usageProgress
                )
            )
            stepped.append(point)
        }
        return stepped
    }

    public static func compactResetDuration(
        resetsAt: Date?,
        now: Date = Date()
    ) -> String {
        guard let resetsAt else { return "--" }
        let totalMinutes = max(0, Int(resetsAt.timeIntervalSince(now) / 60))
        let days = totalMinutes / 1_440
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if days > 0 {
            return "\(days)d"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(totalMinutes)m"
    }

    public static func clampedFrame(
        _ frame: CGRect,
        visibleFrame: CGRect,
        margin: CGFloat
    ) -> CGRect {
        let minimumX = visibleFrame.minX + margin
        let maximumX = visibleFrame.maxX - margin - frame.width
        let minimumY = visibleFrame.minY + margin
        let maximumY = visibleFrame.maxY - margin - frame.height
        return CGRect(
            x: min(max(frame.minX, minimumX), maximumX),
            y: min(max(frame.minY, minimumY), maximumY),
            width: frame.width,
            height: frame.height
        )
    }
}
