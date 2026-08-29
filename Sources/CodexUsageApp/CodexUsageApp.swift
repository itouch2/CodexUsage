import AppKit
import CodexUsageCore
import SwiftUI
import UserNotifications

@main
struct CodexUsageApp: App {
    @NSApplicationDelegateAdaptor(CodexUsageAppDelegate.self)
    private var appDelegate
    @StateObject private var viewModel = AgentUsageViewModel()
    @StateObject private var locationRecorder = CodexLocationRecorder.shared
    @State private var didStartRuntime = false

    var body: some Scene {
        WindowGroup("Codex Usage", id: "dashboard") {
            AgentUsageView(viewModel: viewModel)
                .tint(.codexUsageAccent)
                .frame(
                    minWidth: 680,
                    idealWidth: 760,
                    minHeight: 560,
                    idealHeight: 720
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
                .tint(.codexUsageAccent)
                .frame(width: 340)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chart.xyaxis.line")
                if let remainingPercent = viewModel.codexRemainingPercent {
                    Text("\(remainingPercent)%")
                        .monospacedDigit()
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Codex Usage")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class CodexUsageAppDelegate: NSObject,
    NSApplicationDelegate,
    UNUserNotificationCenterDelegate
{
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        if let iconURL = Bundle.main.url(
            forResource: "CodexUsageIcon",
            withExtension: "icns"
        ), let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        NSApp.setActivationPolicy(.regular)
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

            InfoCard(title: "Account") {
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

            InfoCard(title: "Desktop Widget") {
                CodexUsagePalettePicker(controller: widgetController)

                HStack {
                    Button(
                        widgetController.isEditing ? "Done Editing" : "Edit"
                    ) {
                        widgetController.toggleEditing()
                    }
                    .disabled(!widgetController.isVisible)

                    Button("Refresh") {
                        widgetController.refresh()
                    }

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
                Button("Refresh") {
                    viewModel.refresh()
                }
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
}
