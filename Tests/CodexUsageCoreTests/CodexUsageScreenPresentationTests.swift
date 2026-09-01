import Foundation
import XCTest

final class CodexUsageScreenPresentationTests: XCTestCase {
    func testDashboardUsesWidgetStudioInsteadOfLegacyCardStack() throws {
        let source = try appSource("AgentUsageView.swift")

        XCTAssertTrue(source.contains("WidgetStudioPreview("))
        XCTAssertTrue(source.contains("WidgetInspectorView("))
        XCTAssertTrue(source.contains("HStack(spacing: 0)"))
        XCTAssertFalse(source.contains("InfoCard(title: \"Daily Usage\")"))
        XCTAssertFalse(source.contains("InfoCard(title: \"Recent Sessions\")"))
        XCTAssertFalse(source.contains("ProviderCard("))
    }

    func testPreviewUsesTheRealDesktopWidget() throws {
        let source = try appSource("WidgetStudioPreview.swift")

        XCTAssertTrue(source.contains("CodexUsageDesktopWidgetView("))
        XCTAssertTrue(source.contains(".allowsHitTesting(false)"))
        XCTAssertTrue(source.contains(
            "Drag and resize directly on your desktop"
        ))
    }

    func testPreviewInstructionIsTwoPointsLargerAndMoreTransparent() throws {
        let source = try appSource("WidgetStudioPreview.swift")
        let instruction = try sourceSection(
            in: source,
            from: "Text(\"Drag and resize directly on your desktop\")",
            to: "Spacer(minLength: 32)"
        )

        XCTAssertTrue(instruction.contains(".font(.system(size: 12))"))
        XCTAssertTrue(instruction.contains(".opacity(0.68)"))
        XCTAssertFalse(instruction.contains(".font(.caption)"))
    }

    func testPreviewKeepsTheFixedGradientFromTheWidgetFirstDesign() throws {
        let source = try appSource("WidgetStudioPreview.swift")

        XCTAssertTrue(source.contains("designGradientTopColor"))
        XCTAssertTrue(source.contains("designGradientMiddleColor"))
        XCTAssertTrue(source.contains("designGradientBottomColor"))
        XCTAssertTrue(source.contains("red: 205.0 / 255.0"))
        XCTAssertTrue(source.contains("green: 237.0 / 255.0"))
        XCTAssertTrue(source.contains("blue: 208.0 / 255.0"))
        XCTAssertTrue(source.contains("LinearGradient("))
        XCTAssertTrue(source.contains("startPoint: .top"))
        XCTAssertTrue(source.contains("endPoint: .bottom"))
        XCTAssertFalse(source.contains("controller.palette"))
    }

    func testInspectorExposesWidgetFirstControls() throws {
        let source = try appSource("WidgetInspectorView.swift")

        for copy in [
            "Desktop Widget",
            "Show on Desktop",
            "Appearance",
            "Bring to Front",
            "Reset alerts",
            "Work Trail",
            "Location stays on this Mac."
        ] {
            XCTAssertTrue(source.contains(copy), "Missing \(copy)")
        }

        XCTAssertTrue(source.contains("controller.show(viewModel: viewModel)"))
        XCTAssertTrue(source.contains("controller.hide()"))
        XCTAssertTrue(source.contains("controller.selectPalette(palette)"))
        XCTAssertTrue(source.contains("controller.beginEditing()"))
        XCTAssertTrue(source.contains("controller.finishEditing()"))
        XCTAssertFalse(source.contains("controller.refresh()"))
        XCTAssertFalse(source.contains("Label(\"Refresh\""))
        XCTAssertFalse(source.contains("Button(\"Hide Widget\""))
        XCTAssertFalse(source.contains("Edit on Desktop"))
        XCTAssertFalse(source.contains("Done Editing"))
        XCTAssertFalse(source.contains("editButtonTitle"))
        XCTAssertFalse(source.contains("editWidgetOnDesktop"))
    }

    func testInspectorOmitsOnlyTheTwoScreenshotIndicatedDividers() throws {
        let source = try appSource("WidgetInspectorView.swift")
        let desktopToAppearance = try sourceSection(
            in: source,
            from: "Toggle(\"Bring to Front\"",
            to: "Text(\"Appearance\")"
        )
        let appearanceToResetAlerts = try sourceSection(
            in: source,
            from: "ForEach(CodexUsageWidgetPalette.allCases)",
            to: "ResetAlertsSettingsRow(viewModel: viewModel)"
        )
        let latestResetToLatestPost = try sourceSection(
            in: source,
            from: "if let post = viewModel.resetRadar?.latestPost",
            to: "latestPostContent(post)"
        )

        XCTAssertFalse(desktopToAppearance.contains("Divider()"))
        XCTAssertTrue(appearanceToResetAlerts.contains("Divider()"))
        XCTAssertFalse(latestResetToLatestPost.contains("Divider()"))
    }

    func testBringToFrontSwitchControlsEditingAndRequiresVisibleWidget() throws {
        let source = try appSource("WidgetInspectorView.swift")
        let desktopWidgetSection = try sourceSection(
            in: source,
            from: "Text(\"Desktop Widget\")",
            to: "Divider()"
        )
        let appearanceSection = try sourceSection(
            in: source,
            from: "Text(\"Appearance\")",
            to: "Divider()"
        )

        XCTAssertTrue(desktopWidgetSection.contains(
            "Toggle(\"Bring to Front\", isOn: widgetEditing)"
        ))
        XCTAssertFalse(desktopWidgetSection.contains(
            "Button(\"Bring to Front\")"
        ))
        XCTAssertTrue(desktopWidgetSection.contains(
            ".toggleStyle(CompactChubbyToggleStyle())"
        ))
        XCTAssertTrue(desktopWidgetSection.contains(
            ".disabled(!controller.isVisible)"
        ))
        XCTAssertTrue(source.contains(
            "get: { controller.isEditing }"
        ))
        XCTAssertTrue(source.contains(
            "controller.beginEditing()"
        ))
        XCTAssertTrue(source.contains(
            "controller.finishEditing()"
        ))
        XCTAssertFalse(desktopWidgetSection.contains(
            "controller.show(viewModel: viewModel)"
        ))
        XCTAssertFalse(appearanceSection.contains("Bring to Front"))
    }

    func testDesktopWidgetOmitsDoneEditingOverlay() throws {
        let source = try appSource("CodexUsageDesktopWidgetView.swift")

        XCTAssertFalse(source.contains("Button(\"Done\")"))
        XCTAssertFalse(source.contains("controller.finishEditing()"))
    }

    func testDesktopWidgetHasTinyMoreButtonThatOpensDashboard() throws {
        let widget = try appSource("CodexUsageDesktopWidgetView.swift")
        let controller = try appSource(
            "CodexUsageDesktopWidgetController.swift"
        )
        let dashboard = try appSource("AgentUsageView.swift")
        let header = try sourceSection(
            in: widget,
            from: "private var widgetHeader: some View",
            to: "private var moreButton"
        )
        let moreButton = try sourceSection(
            in: widget,
            from: "private var moreButton",
            to: "@ViewBuilder"
        )

        XCTAssertTrue(header.contains("moreButton"))
        XCTAssertTrue(moreButton.contains("controller.openDashboard()"))
        XCTAssertTrue(moreButton.contains("Image(systemName: \"ellipsis\")"))
        XCTAssertTrue(moreButton.contains(".frame(width: 20, height: 20)"))
        XCTAssertTrue(moreButton.contains(
            ".accessibilityLabel(\"Open Codex Usage\")"
        ))
        XCTAssertTrue(controller.contains("func openDashboard()"))
        XCTAssertTrue(controller.contains("isInMoreButtonHotZone"))
        XCTAssertTrue(controller.contains("dashboardOpenHandler?()"))
        XCTAssertTrue(dashboard.contains("@Environment(\\.openWindow)"))
        XCTAssertTrue(dashboard.contains(
            "widgetController.setDashboardOpenHandler"
        ))
    }

    func testInspectorSwitchesShareTheCompactChubbyVioletStyle() throws {
        let source = try appSource("WidgetInspectorView.swift")
        let desktopVisibilityToggle = try sourceSection(
            in: source,
            from: "Toggle(\"Show on Desktop\"",
            to: "Divider()"
        )
        let bringToFrontToggle = try sourceSection(
            in: source,
            from: "Toggle(\"Bring to Front\"",
            to: "Divider()"
        )
        let workTrailToggle = try sourceSection(
            in: source,
            from: "Toggle(\"Work Trail\"",
            to: "if !recorder.samples.isEmpty"
        )
        let toggleStyle = try sourceSection(
            in: source,
            from: "private struct CompactChubbyToggleStyle",
            to: "private struct PaletteSwatchButton"
        )

        XCTAssertTrue(desktopVisibilityToggle.contains(
            ".toggleStyle(CompactChubbyToggleStyle())"
        ))
        XCTAssertTrue(bringToFrontToggle.contains(
            ".toggleStyle(CompactChubbyToggleStyle())"
        ))
        XCTAssertTrue(workTrailToggle.contains(
            ".toggleStyle(CompactChubbyToggleStyle())"
        ))
        XCTAssertFalse(desktopVisibilityToggle.contains(".controlSize(.large)"))
        XCTAssertFalse(desktopVisibilityToggle.contains(".tint(.black)"))
        XCTAssertTrue(toggleStyle.contains("red: 88.0 / 255.0"))
        XCTAssertTrue(toggleStyle.contains("green: 104.0 / 255.0"))
        XCTAssertTrue(toggleStyle.contains("blue: 244.0 / 255.0"))
        XCTAssertTrue(toggleStyle.contains("width: 29.92, height: 17.68"))
        XCTAssertTrue(toggleStyle.contains("width: 13.6, height: 13.6"))
        XCTAssertTrue(toggleStyle.contains(".padding(2.04)"))
        XCTAssertFalse(toggleStyle.contains("width: 35.2, height: 20.8"))
        XCTAssertFalse(toggleStyle.contains("width: 16, height: 16"))
    }

    func testDashboardWindowMatchesTheWidgetStudioCanvas() throws {
        let source = try appSource("CodexUsageApp.swift")

        XCTAssertTrue(source.contains("minWidth: 860"))
        XCTAssertTrue(source.contains("idealWidth: 1020"))
        XCTAssertTrue(source.contains("idealHeight: 660"))
    }

    func testDashboardHidesTheTitleBarOverTheWidgetCanvas() throws {
        let source = try appSource("CodexUsageApp.swift")

        XCTAssertTrue(source.contains(".windowStyle(.hiddenTitleBar)"))
        XCTAssertFalse(source.contains(".windowStyle(.titleBar)"))
    }

    func testMenuBarOmitsManualRefreshAndKeepsResetStatus() throws {
        let source = try appSource("CodexUsageApp.swift")
        let start = try XCTUnwrap(
            source.range(of: "private struct CodexUsageMenuBarView")?.lowerBound
        )
        let menuBar = source[start...]

        XCTAssertFalse(menuBar.contains("Button(\"Refresh\")"))
        XCTAssertTrue(menuBar.contains(
            "CodexResetRadarPresentation.widgetBadge"
        ))
        XCTAssertTrue(menuBar.contains("viewModel.resetRadar"))
        XCTAssertTrue(menuBar.contains("viewModel.refresh()"))
    }

    func testMenuBarLabelUsesTheRemainingQuotaNumber() throws {
        let source = try appSource("CodexUsageMenuBarLabel.swift")

        XCTAssertFalse(source.contains("Text(\"Codex\")"))
        XCTAssertTrue(source.contains(
            "Text(\"\\(remainingPercent)%\")"
        ))
        XCTAssertTrue(source.contains("Text(\"--%\")"))
        XCTAssertTrue(source.contains("accessibilityLabel"))
    }

    func testInspectorCanHideAppFromDockAndRestoreItOnLaunch() throws {
        let app = try appSource("CodexUsageApp.swift")
        let inspector = try appSource("WidgetInspectorView.swift")
        let dockVisibility = try sourceSection(
            in: inspector,
            from: "Toggle(\"Show in Dock\"",
            to: "private var dockVisibility"
        )

        XCTAssertTrue(dockVisibility.contains(
            ".toggleStyle(CompactChubbyToggleStyle())"
        ))
        XCTAssertTrue(inspector.contains(
            "@AppStorage(CodexUsageDockPreference.defaultsKey)"
        ))
        XCTAssertTrue(inspector.contains(
            "CodexUsageDockPreference.apply(isVisible: isVisible)"
        ))
        XCTAssertTrue(app.contains("applicationWillFinishLaunching"))
        XCTAssertTrue(app.contains(
            "CodexUsageDockPreference.applyCurrentPreference()"
        ))
        XCTAssertTrue(app.contains("isVisible ? .regular : .accessory"))
        XCTAssertTrue(app.contains("defaults.register(defaults: ["))
    }

    func testWindowUsesOneTitleAndInspectorOmitsLiveStatusCopy() throws {
        let root = try appSource("AgentUsageView.swift")
        let inspector = try appSource("WidgetInspectorView.swift")

        XCTAssertFalse(root.contains("ToolbarItem(placement: .principal)"))
        XCTAssertFalse(inspector.contains("widgetStatusTitle"))
        XCTAssertFalse(inspector.contains("Widget Active"))
        XCTAssertFalse(inspector.contains("Widget Hidden"))
        XCTAssertFalse(inspector.contains("Updated"))
    }

    func testInspectorStaysCompactAtTheMinimumWindowHeight() throws {
        let source = try appSource("WidgetInspectorView.swift")

        XCTAssertFalse(source.contains("LazyVGrid(columns: paletteColumns"))
        XCTAssertFalse(source.contains("Text(editButtonTitle)"))
        XCTAssertTrue(source.contains("CompactChubbyToggleStyle"))
    }

    func testPaletteButtonsUseWhiteFillAndQuietGrayBorder() throws {
        let source = try appSource("WidgetInspectorView.swift")

        XCTAssertTrue(source.contains("Color(nsColor: .textBackgroundColor)"))
        XCTAssertTrue(source.contains("Color(nsColor: .separatorColor).opacity(0.55)"))
        XCTAssertFalse(source.contains("Color(nsColor: .underPageBackgroundColor)"))
        XCTAssertTrue(source.contains("isSelected ? Color.accentColor"))
    }

    func testInspectorUsesAWhiteSemanticBackground() throws {
        let source = try appSource("WidgetInspectorView.swift")

        XCTAssertTrue(source.contains(
            ".background(Color(nsColor: .textBackgroundColor))"
        ))
        XCTAssertFalse(source.contains(".background(.regularMaterial)"))
    }

    func testResetAlertsAndWorkTrailUsePrimarySectionTitleStyle() throws {
        let source = try appSource("WidgetInspectorView.swift")
        let resetAlerts = try sourceSection(
            in: source,
            from: "private struct ResetAlertsSettingsRow",
            to: "private struct WorkTrailSettingsRow"
        )
        let workTrail = try sourceSection(
            in: source,
            from: "private struct WorkTrailSettingsRow",
            to: "private var recordingEnabled"
        )

        XCTAssertTrue(resetAlerts.contains(".font(.title3.weight(.semibold))"))
        XCTAssertTrue(workTrail.contains(".font(.title3.weight(.semibold))"))
        XCTAssertFalse(resetAlerts.contains(".subheadline.weight(.medium)"))
        XCTAssertFalse(workTrail.contains(".subheadline.weight(.medium)"))
    }

    func testResetAlertsShowsLatestResetAndLatestTiboSeparately() throws {
        let source = try appSource("WidgetInspectorView.swift")
        let resetAlerts = try sourceSection(
            in: source,
            from: "private struct ResetAlertsSettingsRow",
            to: "private struct WorkTrailSettingsRow"
        )

        XCTAssertTrue(resetAlerts.contains("viewModel.resetRadar?.latestReset"))
        XCTAssertTrue(resetAlerts.contains("viewModel.resetRadar?.latestPost"))
        XCTAssertTrue(resetAlerts.contains("Text(\"Latest reset\")"))
        XCTAssertTrue(resetAlerts.contains("Text(\"Latest from Tibo\")"))
        XCTAssertTrue(resetAlerts.contains(
            "CodexResetRadarPresentation.displayText"
        ))
        XCTAssertTrue(resetAlerts.contains(
            "CodexResetRadarPresentation.relativeAge"
        ))
    }

    func testPaletteColorsThePaceChartAndUsageValue() throws {
        let root = try appSource("AgentUsageView.swift")
        let menu = try appSource("CodexUsageApp.swift")
        let preview = try appSource("WidgetStudioPreview.swift")
        let widget = try appSource("CodexUsageDesktopWidgetView.swift")
        let summaryAccent = try sourceSection(
            in: widget,
            from: "private var summaryAccentColor: Color",
            to: "private var rectangularCard"
        )
        let summary = try sourceSection(
            in: widget,
            from: "private var usageSummary: some View",
            to: "private func stackedSummaryMetric"
        )
        let radar = try sourceSection(
            in: widget,
            from: "private var resetRadarBadge: some View",
            to: "private func resetWatchBadgeLabel"
        )
        let chart = try sourceSection(
            in: widget,
            from: "private var paceChart: some View",
            to: "private func roundedStepPath"
        )

        XCTAssertFalse(root.contains(".tint(widgetController.palette"))
        XCTAssertFalse(menu.contains(".tint(widgetController.palette"))
        XCTAssertFalse(preview.contains("controller.palette"))
        XCTAssertFalse(widget.contains("var tintColor"))
        XCTAssertFalse(widget.contains(".tint(controller.palette"))
        XCTAssertFalse(summary.contains("controller.palette"))
        XCTAssertTrue(summary.contains("summaryAccentColor"))
        XCTAssertTrue(summaryAccent.contains("controller.palette.usageLineColor"))
        XCTAssertFalse(radar.contains("controller.palette"))
        XCTAssertTrue(chart.contains("controller.palette.referenceLineColor"))
        XCTAssertTrue(chart.contains("controller.palette.usageLineColor"))
    }

    private func appSource(_ filename: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/CodexUsageApp/\(filename)"
            ),
            encoding: .utf8
        )
    }

    private func sourceSection(
        in source: String,
        from startMarker: String,
        to endMarker: String
    ) throws -> Substring {
        let start = try XCTUnwrap(source.range(of: startMarker)?.lowerBound)
        let end = try XCTUnwrap(
            source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound
        )
        return source[start..<end]
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
