import AppKit
import CodexUsageCore
import SwiftUI
import UserNotifications

enum CodexUsageDockPreference {
    static let defaultsKey = "showInDock"

    @MainActor
    static func applyCurrentPreference(
        defaults: UserDefaults = .standard
    ) {
        defaults.register(defaults: [defaultsKey: true])
        apply(isVisible: defaults.bool(forKey: defaultsKey))
    }

    @MainActor
    static func apply(isVisible: Bool) {
        NSApp.setActivationPolicy(isVisible ? .regular : .accessory)
    }
}

enum CodexResetMenuBarAcknowledgement {
    static let defaultsKey =
        "codex.resetRadar.acknowledgedMenuBarSignalID"
}

@main
struct CodexUsageApp: App {
    @NSApplicationDelegateAdaptor(CodexUsageAppDelegate.self)
    private var appDelegate
    @StateObject private var viewModel = AgentUsageViewModel()
    @StateObject private var locationRecorder = CodexLocationRecorder.shared
    @AppStorage(CodexResetMenuBarAcknowledgement.defaultsKey)
    private var acknowledgedResetSignalID = ""
    @State private var didStartRuntime = false

    var body: some Scene {
        let menuBarSignalID = CodexResetRadarPresentation.menuBarSignalID(
            snapshot: viewModel.resetRadar,
            now: viewModel.snapshot.generatedAt
        )
        let menuBarBadge = CodexResetRadarPresentation.menuBarBadge(
            snapshot: viewModel.resetRadar,
            now: viewModel.snapshot.generatedAt,
            acknowledgedSignalID: acknowledgedResetSignalID
        )

        WindowGroup("Codex Usage", id: "dashboard") {
            AgentUsageView(viewModel: viewModel)
                .frame(
                    minWidth: 860,
                    idealWidth: 1020,
                    minHeight: 560,
                    idealHeight: 660
                )
                .task {
                    guard !didStartRuntime else { return }
                    didStartRuntime = true
                    viewModel.startAutomaticRefresh()
                    viewModel.refreshResetNotificationAuthorization()
                    locationRecorder.resumeIfEnabled()
                    CodexUsageDesktopWidgetController.shared.show(
                        viewModel: viewModel
                    )
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Refresh Usage") {
                    viewModel.refresh()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Show Desktop Widget") {
                    CodexUsageDesktopWidgetController.shared.show(
                        viewModel: viewModel
                    )
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra {
            CodexUsageMenuBarView(viewModel: viewModel)
                .frame(width: 340)
        } label: {
            CodexUsageMenuBarLabel(
                remainingPercent: viewModel.codexRemainingPercent,
                resetBadge: menuBarBadge
            ) {
                guard let menuBarSignalID else { return }
                acknowledgedResetSignalID = menuBarSignalID
            }
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class CodexUsageAppDelegate: NSObject,
    NSApplicationDelegate,
    UNUserNotificationCenterDelegate
{
    func applicationWillFinishLaunching(_ notification: Notification) {
        CodexUsageDockPreference.applyCurrentPreference()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        if let iconURL = Bundle.main.url(
            forResource: "CodexUsageIcon",
            withExtension: "icns"
        ), let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        CodexUsageDesktopWidgetController.shared.savePosition()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (
            UNNotificationPresentationOptions
        ) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

private struct CodexUsageMenuBarView: View {
    @ObservedObject var viewModel: AgentUsageViewModel
    @ObservedObject private var widgetController =
        CodexUsageDesktopWidgetController.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Codex Usage")
                    .font(.headline)
                Spacer()
                Button {
                    openWindow(id: "dashboard")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Image(systemName: "macwindow")
                }
                .buttonStyle(.borderless)
                .help("Open Dashboard")
            }

            resetSignalBanner

            InfoCard(
                title: "Account",
                titleFont: .subheadline.weight(.semibold)
            ) {
                if let remainingPercent = viewModel.codexRemainingPercent {
                    Text("\(remainingPercent)% left")
                        .font(.title3.monospacedDigit().weight(.semibold))
                } else {
                    Text("Quota unavailable")
                        .font(.title3.weight(.semibold))
                }

                Text("\(viewModel.snapshot.sessions.count) local sessions")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)

                Text(
                    "Updated "
                        + viewModel.snapshot.generatedAt.formatted(
                            date: .omitted,
                            time: .shortened
                        )
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if let radarBadge = CodexResetRadarPresentation.widgetBadge(
                    snapshot: viewModel.resetRadar,
                    now: viewModel.snapshot.generatedAt
                ) {
                    Label(
                        radarBadge,
                        systemImage: "antenna.radiowaves.left.and.right"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(
                        viewModel.resetRadar?.activeWatch == nil
                            ? Color.green
                            : Color.orange
                    )
                }
            }

            InfoCard(
                title: "Reset alerts",
                titleFont: .subheadline.weight(.semibold)
            ) {
                HStack(spacing: 10) {
                    Label("Reset signal notifications", systemImage: "bell")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    ResetAlertsControl(viewModel: viewModel)
                }
            }

            InfoCard(
                title: "Desktop Widget",
                titleFont: .subheadline.weight(.semibold)
            ) {
                CodexUsagePalettePicker(controller: widgetController)

                HStack {
                    Button(
                        widgetController.isEditing
                            ? "Done Editing"
                            : "Bring to Front"
                    ) {
                        widgetController.toggleEditing()
                    }
                    .disabled(!widgetController.isVisible)

                    Spacer()

                    if widgetController.isVisible {
                        Button("Hide") {
                            widgetController.hide()
                        }
                    } else {
                        Button("Show") {
                            widgetController.show(viewModel: viewModel)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(16)
        .onAppear {
            viewModel.refresh()
        }
    }

    @ViewBuilder
    private var resetSignalBanner: some View {
        if let watch = viewModel.resetRadar?.activeWatch {
            ResetSignalBanner(
                state: .watch,
                detail: CodexResetRadarPresentation.watchHeadline(watch)
                    ?? "A possible reset signal is active.",
                sourceURL: watch.source.url
            )
        } else if let reset = viewModel.resetRadar?.latestReset,
                  CodexResetRadarPresentation.menuBarBadge(
                      snapshot: viewModel.resetRadar,
                      now: viewModel.snapshot.generatedAt
                  ) != nil {
            ResetSignalBanner(
                state: .confirmed,
                detail: CodexResetRadarPresentation.relativeAge(
                    since: reset.announcedAt
                ),
                sourceURL: reset.source.url
            )
        }
    }
}

private struct ResetSignalBanner: View {
    enum State {
        case watch
        case confirmed
    }

    let state: State
    let detail: String
    let sourceURL: URL

    var body: some View {
        Button {
            NSWorkspace.shared.open(sourceURL)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbolName)
                    .font(.system(size: 15, weight: .semibold))

                VStack(alignment: .leading, spacing: 2) {
                    switch state {
                    case .watch:
                        Text("Reset watch")
                            .font(.subheadline.weight(.bold))
                    case .confirmed:
                        Text("Reset confirmed")
                            .font(.subheadline.weight(.bold))
                    }

                    Text(detail)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(backgroundColor)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.24), lineWidth: 1)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open reset source on X")
    }

    private var symbolName: String {
        switch state {
        case .watch:
            return "bell.badge.fill"
        case .confirmed:
            return "checkmark.circle.fill"
        }
    }

    private var backgroundColor: Color {
        switch state {
        case .watch:
            return Color.orange
        case .confirmed:
            return Color.green
        }
    }
}
