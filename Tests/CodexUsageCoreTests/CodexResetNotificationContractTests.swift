import Foundation
import XCTest

final class CodexResetNotificationContractTests: XCTestCase {
    func testNotifierReportsAuthorizationStateAndErrors() throws {
        let source = try sourceText(
            at: "Sources/CodexUsageApp/CodexResetRadarNotifier.swift"
        )

        XCTAssertTrue(source.contains("notificationSettings()"))
        XCTAssertTrue(source.contains("requestAuthorization() async"))
        XCTAssertTrue(source.contains("case failed(String)"))
        XCTAssertTrue(source.contains("error.localizedDescription"))
        XCTAssertFalse(source.contains(
            "_ = try? await center.requestAuthorization"
        ))
    }

    func testNotifierTracksWatchAndConfirmedResetSignalsSeparately() throws {
        let source = try sourceText(
            at: "Sources/CodexUsageApp/CodexResetRadarNotifier.swift"
        )

        XCTAssertTrue(source.contains(
            "codexUsage.resetRadar.lastNotifiedResetSignalID"
        ))
        XCTAssertTrue(source.contains("lastNotifiedWatchSignalID:"))
        XCTAssertTrue(source.contains("lastNotifiedResetSignalID:"))
        XCTAssertTrue(source.contains(
            "snapshot.latestReset?.source.url.absoluteString"
        ))
    }

    func testResetRadarProvidesExplicitNotificationControls() throws {
        let viewModel = try sourceText(
            at: "Sources/CodexUsageApp/AgentUsageViewModel.swift"
        )
        let view = try sourceText(
            at: "Sources/CodexUsageApp/WidgetInspectorView.swift"
        )

        XCTAssertFalse(viewModel.contains("prepareAuthorization()"))
        XCTAssertTrue(viewModel.contains(
            "requestResetNotificationAuthorization"
        ))
        XCTAssertTrue(viewModel.contains("sendTestResetNotification"))
        XCTAssertTrue(view.contains("Text(\"Reset alerts\")"))
        XCTAssertTrue(view.contains("Button(\"Enable\")"))
        XCTAssertTrue(view.contains("Send Test Alert"))
        XCTAssertTrue(view.contains("Button(\"Open Settings\")"))
        XCTAssertTrue(view.contains(
            "com.apple.Notifications-Settings.extension?id=app.codexusage.local"
        ))
    }

    func testForegroundNotificationsRequestBannerAndSound() throws {
        let source = try sourceText(
            at: "Sources/CodexUsageApp/CodexUsageApp.swift"
        )

        XCTAssertTrue(source.contains("UNUserNotificationCenterDelegate"))
        XCTAssertTrue(source.contains("UNUserNotificationCenter.current().delegate = self"))
        XCTAssertTrue(source.contains("willPresent notification"))
        XCTAssertTrue(source.contains("completionHandler([.banner, .sound])"))
    }

    private func sourceText(at relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
