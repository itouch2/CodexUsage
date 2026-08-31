import CoreGraphics
import XCTest
@testable import CodexUsageCore

final class CodexUsageWidgetPresentationTests: XCTestCase {
    func testSquareResizeFrameTracksDiagonalAndAlignsToBackingPixels() {
        let initialFrame = CGRect(x: 100, y: 300, width: 200, height: 200)

        let expanded = CodexUsageWidgetPresentation.squareResizeFrame(
            initialFrame: initialFrame,
            horizontalMovement: 40,
            downwardMovement: 40,
            minimumSideLength: 160,
            backingScaleFactor: 2
        )
        XCTAssertEqual(expanded, CGRect(x: 100, y: 260, width: 240, height: 240))

        let horizontalOnly = CodexUsageWidgetPresentation.squareResizeFrame(
            initialFrame: initialFrame,
            horizontalMovement: 41,
            downwardMovement: 0,
            minimumSideLength: 160,
            backingScaleFactor: 2
        )
        XCTAssertEqual(
            horizontalOnly,
            CGRect(x: 100, y: 279.5, width: 220.5, height: 220.5)
        )
        XCTAssertEqual(horizontalOnly.maxY, initialFrame.maxY)
    }

    func testSquareResizeFrameClampsAtMinimumSize() {
        let initialFrame = CGRect(x: 100, y: 300, width: 200, height: 200)

        let frame = CodexUsageWidgetPresentation.squareResizeFrame(
            initialFrame: initialFrame,
            horizontalMovement: -80,
            downwardMovement: -80,
            minimumSideLength: 160,
            backingScaleFactor: 2
        )

        XCTAssertEqual(frame, CGRect(x: 100, y: 340, width: 160, height: 160))
        XCTAssertEqual(frame.maxY, initialFrame.maxY)
    }

    func testSquareResizeFrameKeepsDesktopTopLeftAnchorAcrossUpdates() {
        let initialFrame = CGRect(x: 120, y: 340, width: 200, height: 200)
        let topLeftAnchor = CGPoint(
            x: initialFrame.minX,
            y: initialFrame.maxY
        )

        for movement in stride(from: -80.0, through: 160.0, by: 0.5) {
            let frame = CodexUsageWidgetPresentation.squareResizeFrame(
                topLeftAnchor: topLeftAnchor,
                initialSideLength: initialFrame.width,
                horizontalMovement: movement,
                downwardMovement: movement,
                minimumSideLength: 160,
                backingScaleFactor: 2
            )

            XCTAssertEqual(frame.minX, topLeftAnchor.x)
            XCTAssertEqual(frame.maxY, topLeftAnchor.y)
        }
    }

    func testFormatsDynamicCodexWindowPeriods() {
        XCTAssertEqual(CodexUsageWidgetPresentation.periodLabel(minutes: 300), "5-hour quota")
        XCTAssertEqual(CodexUsageWidgetPresentation.periodLabel(minutes: 10080), "7-day quota")
        XCTAssertEqual(CodexUsageWidgetPresentation.periodLabel(minutes: 45), "45-minute quota")
        XCTAssertEqual(CodexUsageWidgetPresentation.periodLabel(minutes: 0), "Usage quota")
    }

    func testBuildsSevenDayTimeAxisTicksAtDailyPositions() {
        let ticks = CodexUsageWidgetPresentation.timeAxisTicks(
            windowMinutes: 10_080
        )

        XCTAssertEqual(ticks.map(\.label), ["1", "2", "3", "4", "5", "6", "7"])
        XCTAssertEqual(ticks.first?.progress ?? -1, 1.0 / 7.0, accuracy: 0.0001)
        XCTAssertEqual(ticks.last?.progress ?? -1, 1, accuracy: 0.0001)
        XCTAssertTrue(
            CodexUsageWidgetPresentation.timeAxisTicks(
                windowMinutes: 300
            ).isEmpty
        )
    }

    func testBuildsAccessibleRemainingSummary() {
        XCTAssertEqual(
            CodexUsageWidgetPresentation.accessibilitySummary(
                windowMinutes: 10080,
                remainingPercent: 49
            ),
            "7-day Codex quota, 49 percent remaining"
        )
    }

    func testBuildsGlanceableStatusLabels() {
        XCTAssertEqual(CodexUsageWidgetPresentation.statusLabel(remainingPercent: 80), "Plenty remaining")
        XCTAssertEqual(CodexUsageWidgetPresentation.statusLabel(remainingPercent: 45), "Half remaining")
        XCTAssertEqual(CodexUsageWidgetPresentation.statusLabel(remainingPercent: 18), "Running low")
        XCTAssertEqual(CodexUsageWidgetPresentation.statusLabel(remainingPercent: 5), "Almost exhausted")
    }

    func testFormatsRelativeResetCountdown() {
        let now = Date(timeIntervalSince1970: 1_000_000)

        XCTAssertEqual(
            CodexUsageWidgetPresentation.resetCountdown(
                resetsAt: now.addingTimeInterval(11 * 3_600 + 27 * 60),
                now: now
            ),
            "Resets in 11h 27m"
        )
        XCTAssertEqual(
            CodexUsageWidgetPresentation.resetCountdown(
                resetsAt: now.addingTimeInterval(2 * 86_400 + 4 * 3_600),
                now: now
            ),
            "Resets in 2d 4h"
        )
    }

    func testCalculatesElapsedWindowProgress() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resetsAt = now.addingTimeInterval(3_000)

        let progress = CodexUsageWidgetPresentation.elapsedTimeProgress(
            windowMinutes: 100,
            resetsAt: resetsAt,
            now: now
        )

        XCTAssertNotNil(progress)
        XCTAssertEqual(
            progress ?? -1,
            0.5,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CodexUsageWidgetPresentation.elapsedTimeProgress(
                windowMinutes: 100,
                resetsAt: now.addingTimeInterval(-1),
                now: now
            ),
            1
        )
        XCTAssertNil(
            CodexUsageWidgetPresentation.elapsedTimeProgress(
                windowMinutes: 0,
                resetsAt: resetsAt,
                now: now
            )
        )
    }

    func testCalculatesConsumedUsageProgress() {
        XCTAssertEqual(
            CodexUsageWidgetPresentation.consumedUsageProgress(
                usedPercent: 76
            ),
            0.76,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CodexUsageWidgetPresentation.consumedUsageProgress(
                usedPercent: -5
            ),
            0
        )
        XCTAssertEqual(
            CodexUsageWidgetPresentation.consumedUsageProgress(
                usedPercent: 140
            ),
            1
        )
    }

    func testBuildsPaceChartPointsForTheCurrentResetWindow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resetsAt = now.addingTimeInterval(2.5 * 3_600)
        let samples = [
            CodexUsagePaceSample(
                capturedAt: now.addingTimeInterval(-1_800),
                usedPercent: 42,
                windowMinutes: 300,
                resetsAt: resetsAt
            ),
            CodexUsagePaceSample(
                capturedAt: now.addingTimeInterval(-3_600),
                usedPercent: 25,
                windowMinutes: 300,
                resetsAt: resetsAt.addingTimeInterval(1)
            ),
            CodexUsagePaceSample(
                capturedAt: now.addingTimeInterval(-7_200),
                usedPercent: 90,
                windowMinutes: 300,
                resetsAt: resetsAt.addingTimeInterval(-300)
            ),
        ]

        let points = CodexUsageWidgetPresentation.paceChartPoints(
            samples: samples,
            usedPercent: 62,
            windowMinutes: 300,
            resetsAt: resetsAt,
            now: now
        )

        XCTAssertEqual(points.count, 4)
        XCTAssertEqual(points[0], CodexUsagePacePoint(timeProgress: 0, usageProgress: 0))
        XCTAssertEqual(points[1].usageProgress, 0.25, accuracy: 0.0001)
        XCTAssertEqual(points[2].usageProgress, 0.42, accuracy: 0.0001)
        XCTAssertEqual(points[3].usageProgress, 0.62, accuracy: 0.0001)
        XCTAssertLessThan(points[0].timeProgress, points[1].timeProgress)
        XCTAssertLessThan(points[1].timeProgress, points[2].timeProgress)
        XCTAssertLessThan(points[2].timeProgress, points[3].timeProgress)
        XCTAssertEqual(points[3].timeProgress, 0.5, accuracy: 0.0001)
    }

    func testPaceChartPointsStayMonotonicWithinAResetWindow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resetsAt = now.addingTimeInterval(3_600)
        let samples = [
            CodexUsagePaceSample(
                capturedAt: now.addingTimeInterval(-10_800),
                usedPercent: 12,
                windowMinutes: 300,
                resetsAt: resetsAt
            ),
            CodexUsagePaceSample(
                capturedAt: now.addingTimeInterval(-7_200),
                usedPercent: 10,
                windowMinutes: 300,
                resetsAt: resetsAt
            ),
            CodexUsagePaceSample(
                capturedAt: now.addingTimeInterval(-3_600),
                usedPercent: 19,
                windowMinutes: 300,
                resetsAt: resetsAt
            ),
        ]

        let points = CodexUsageWidgetPresentation.paceChartPoints(
            samples: samples,
            usedPercent: 16,
            windowMinutes: 300,
            resetsAt: resetsAt,
            now: now
        )

        XCTAssertEqual(
            points.map(\.usageProgress),
            [0, 0.12, 0.12, 0.19, 0.19]
        )
    }

    func testBuildsStepPointsWithoutInventingLinearUsageBetweenSamples() {
        let points = [
            CodexUsagePacePoint(timeProgress: 0.10, usageProgress: 0.08),
            CodexUsagePacePoint(timeProgress: 0.25, usageProgress: 0.08),
            CodexUsagePacePoint(timeProgress: 0.40, usageProgress: 0.21),
        ]

        let stepped = CodexUsageWidgetPresentation.steppedPaceChartPoints(
            points
        )

        XCTAssertEqual(
            stepped,
            [
                CodexUsagePacePoint(timeProgress: 0.10, usageProgress: 0.08),
                CodexUsagePacePoint(timeProgress: 0.25, usageProgress: 0.08),
                CodexUsagePacePoint(timeProgress: 0.25, usageProgress: 0.08),
                CodexUsagePacePoint(timeProgress: 0.40, usageProgress: 0.08),
                CodexUsagePacePoint(timeProgress: 0.40, usageProgress: 0.21),
            ]
        )
    }

    func testPaceChartPointsClampInvalidUsageValues() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resetsAt = now.addingTimeInterval(3_000)
        let samples = [
            CodexUsagePaceSample(
                capturedAt: now.addingTimeInterval(-10_000),
                usedPercent: -20,
                windowMinutes: 100,
                resetsAt: resetsAt
            ),
        ]

        let points = CodexUsageWidgetPresentation.paceChartPoints(
            samples: samples,
            usedPercent: 130,
            windowMinutes: 100,
            resetsAt: resetsAt,
            now: now
        )

        XCTAssertEqual(points.first?.timeProgress ?? -1, 0)
        XCTAssertEqual(points.first?.usageProgress ?? -1, 0)
        XCTAssertEqual(points.last?.timeProgress ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(points.last?.usageProgress ?? -1, 1)
    }

    func testFormatsCompactResetDuration() {
        let now = Date(timeIntervalSince1970: 1_000_000)

        XCTAssertEqual(
            CodexUsageWidgetPresentation.compactResetDuration(
                resetsAt: now.addingTimeInterval(
                    3 * 86_400 + 4 * 3_600
                ),
                now: now
            ),
            "3d"
        )
        XCTAssertEqual(
            CodexUsageWidgetPresentation.compactResetDuration(
                resetsAt: now.addingTimeInterval(
                    2 * 3_600 + 18 * 60
                ),
                now: now
            ),
            "2h 18m"
        )
        XCTAssertEqual(
            CodexUsageWidgetPresentation.compactResetDuration(
                resetsAt: now.addingTimeInterval(18 * 60),
                now: now
            ),
            "18m"
        )
        XCTAssertEqual(
            CodexUsageWidgetPresentation.compactResetDuration(
                resetsAt: now.addingTimeInterval(-1),
                now: now
            ),
            "0m"
        )
        XCTAssertEqual(
            CodexUsageWidgetPresentation.compactResetDuration(
                resetsAt: nil,
                now: now
            ),
            "--"
        )
    }

    func testClampsWidgetFrameToVisibleScreenBounds() {
        let visibleFrame = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let offscreen = CGRect(x: 1500, y: 960, width: 330, height: 260)

        XCTAssertEqual(
            CodexUsageWidgetPresentation.clampedFrame(
                offscreen,
                visibleFrame: visibleFrame,
                margin: 20
            ),
            CGRect(x: 1090, y: 620, width: 330, height: 260)
        )
    }
}
