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
                .frame(width: 320)
                .modifier(MenuPopoverGlass())
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

private struct MenuPopoverGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if reduceTransparency {
                content.containerBackground(
                    Color(nsColor: .windowBackgroundColor), for: .window
                )
            } else {
                // Let the native popover own the outer corner and clipping.
                // A second rounded glass surface leaves a visible rim beneath it.
                content.containerBackground(for: .window) {
                    Color.clear.glassEffect(.regular, in: Rectangle())
                }
            }
        } else if #available(macOS 15.0, *) {
            content.containerBackground(.regularMaterial, for: .window)
        } else {
            // Older MenuBarExtra windows keep their native material.
            content
        }
    }
}

private struct CodexUsageMenuBarView: View {
    @ObservedObject var viewModel: AgentUsageViewModel
    @ObservedObject private var widgetController =
        CodexUsageDesktopWidgetController.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Codex Usage")
                    .font(.system(size: 14, weight: .semibold))
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
                titleFont: .system(size: 12, weight: .semibold),
                translucent: true
            ) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    if let remainingPercent = viewModel.codexRemainingPercent {
                        Text("\(remainingPercent)% left")
                            .font(.system(size: 20, weight: .semibold).monospacedDigit())
                    } else {
                        Text("Quota unavailable")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    Spacer(minLength: 0)
                    Text(
                        "Updated "
                            + viewModel.snapshot.generatedAt.formatted(
                                date: .omitted,
                                time: .shortened
                            )
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }

                if let radarBadge = CodexResetRadarPresentation.widgetBadge(
                    snapshot: viewModel.resetRadar,
                    now: viewModel.snapshot.generatedAt
                ) {
                    Label(
                        radarBadge,
                        systemImage: "antenna.radiowaves.left.and.right"
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(
                        viewModel.resetRadar?.activeWatch != nil
                            || viewModel.resetRadar?.pendingScheduledReset != nil
                            ? Color.orange
                            : Color.green
                    )
                }
            }

            InfoCard(
                title: "Reset alerts",
                titleFont: .system(size: 12, weight: .semibold),
                translucent: true
            ) {
                HStack(spacing: 10) {
                    Label("Reset signal notifications", systemImage: "bell")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    ResetAlertsControl(viewModel: viewModel)
                }
            }

            InfoCard(
                title: "Desktop Widget",
                titleFont: .system(size: 12, weight: .semibold),
                translucent: true
            ) {
                CodexUsagePalettePicker(controller: widgetController)

                HStack(spacing: 8) {
                    Button {
                        widgetController.toggleEditing()
                    } label: {
                        Text(widgetController.isEditing ? "Done Editing" : "Bring to Front")
                            .frame(maxWidth: .infinity, minHeight: 24)
                    }
                    .disabled(!widgetController.isVisible)

                    Button {
                        if widgetController.isVisible {
                            widgetController.hide()
                        } else {
                            widgetController.show(viewModel: viewModel)
                        }
                    } label: {
                        Text(widgetController.isVisible ? "Hide" : "Show")
                            .frame(maxWidth: .infinity, minHeight: 24)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            HStack {
                Spacer()
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Text("Quit")
                        .frame(minWidth: 48, minHeight: 20)
                }
                .buttonStyle(.bordered)
            }
        }
        .font(.system(size: 12))
        .padding(14)
        .onAppear {
            viewModel.refresh()
        }
    }

    @ViewBuilder
    private var resetSignalBanner: some View {
        if let scheduled = viewModel.resetRadar?.pendingScheduledReset {
            ResetSignalBanner(
                state: .scheduled,
                detail: CodexResetRadarPresentation.scheduledHeadline(
                    scheduled, now: viewModel.snapshot.generatedAt
                ),
                sourceURL: scheduled.source.url
            )
        } else if let watch = viewModel.resetRadar?.activeWatch {
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
        case scheduled
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
                    .font(.system(size: 14, weight: .semibold))

                VStack(alignment: .leading, spacing: 2) {
                    switch state {
                    case .watch:
                        Text("Reset watch")
                            .font(.system(size: 12, weight: .semibold))
                    case .scheduled:
                        Text("Reset scheduled")
                            .font(.system(size: 12, weight: .semibold))
                    case .confirmed:
                        Text("Reset confirmed")
                            .font(.system(size: 12, weight: .semibold))
                    }

                    Text(detail)
                        .font(.system(size: 12, weight: .medium))
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
        case .scheduled:
            return "clock.badge"
        case .watch:
            return "bell.badge.fill"
        case .confirmed:
            return "checkmark.circle.fill"
        }
    }

    private var backgroundColor: Color {
        switch state {
        case .watch, .scheduled:
            return Color.orange
        case .confirmed:
            return Color.green
        }
    }
}
