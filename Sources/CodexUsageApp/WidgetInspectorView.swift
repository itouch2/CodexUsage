import AppKit
import CodexUsageCore
import SwiftUI

struct WidgetInspectorView: View {
    @ObservedObject var viewModel: AgentUsageViewModel
    @ObservedObject var controller: CodexUsageDesktopWidgetController
    @ObservedObject var locationRecorder: CodexLocationRecorder

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Desktop Widget")
                    .font(.title3.weight(.semibold))

                HStack(spacing: 12) {
                    Toggle("Show on Desktop", isOn: widgetVisibility)
                        .toggleStyle(CompactChubbyToggleStyle())

                    Spacer(minLength: 0)

                    Toggle("Bring to Front", isOn: widgetEditing)
                        .toggleStyle(CompactChubbyToggleStyle())
                        .disabled(!controller.isVisible)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Appearance")
                        .font(.subheadline.weight(.semibold))

                    HStack(spacing: 8) {
                        ForEach(CodexUsageWidgetPalette.allCases) { palette in
                            PaletteSwatchButton(
                                palette: palette,
                                isSelected: controller.palette == palette
                            ) {
                                controller.selectPalette(palette)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }

                Divider()

                ResetAlertsSettingsRow(viewModel: viewModel)

                Divider()

                WorkTrailSettingsRow(recorder: locationRecorder)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var widgetVisibility: Binding<Bool> {
        Binding(
            get: { controller.isVisible },
            set: { isVisible in
                if isVisible {
                    controller.show(viewModel: viewModel)
                } else {
                    controller.hide()
                }
            }
        )
    }

    private var widgetEditing: Binding<Bool> {
        Binding(
            get: { controller.isEditing },
            set: { isEditing in
                if isEditing {
                    controller.beginEditing()
                } else {
                    controller.finishEditing()
                }
            }
        )
    }

}

private struct CompactChubbyToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    private let activeColor = Color(
        red: 88.0 / 255.0,
        green: 104.0 / 255.0,
        blue: 244.0 / 255.0
    )

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                configuration.label

                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(
                            configuration.isOn
                                ? activeColor
                                : Color(nsColor: .tertiaryLabelColor).opacity(0.28)
                        )
                        .frame(width: 29.92, height: 17.68)

                    Circle()
                        .fill(.white)
                        .frame(width: 13.6, height: 13.6)
                        .padding(2.04)
                        .shadow(color: .black.opacity(0.16), radius: 1, y: 1)
                }
                .animation(.easeInOut(duration: 0.16), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

private struct PaletteSwatchButton: View {
    let palette: CodexUsageWidgetPalette
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
                .frame(height: 40)
                .overlay {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(palette.referenceLineColor)
                        Circle()
                            .fill(palette.usageLineColor)
                    }
                    .frame(width: 27, height: 11)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(
                            isSelected ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.55),
                            lineWidth: isSelected ? 2 : 1
                        )
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(palette.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(palette.title)
    }
}

private struct ResetAlertsSettingsRow: View {
    @ObservedObject var viewModel: AgentUsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("Reset alerts")
                    .font(.title3.weight(.semibold))

                Spacer()

                control
            }

            resetInformation
        }
    }

    @ViewBuilder
    private var resetInformation: some View {
        if viewModel.resetRadar?.activeWatch != nil
            || viewModel.resetRadar?.latestReset != nil
            || viewModel.resetRadar?.latestPost != nil
        {
            VStack(alignment: .leading, spacing: 10) {
                if let watch = viewModel.resetRadar?.activeWatch {
                    activeWatchContent(watch)
                }

                if viewModel.resetRadar?.activeWatch != nil,
                   viewModel.resetRadar?.latestReset != nil {
                    Divider()
                }

                if let reset = viewModel.resetRadar?.latestReset {
                    latestResetContent(reset)
                }

                if let post = viewModel.resetRadar?.latestPost,
                   post.source.url != viewModel.resetRadar?.latestReset?.source.url {
                    latestPostContent(post)
                }
            }
        } else if viewModel.isResetRadarRefreshing {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking reset signals…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if viewModel.isResetRadarUnavailable {
            Label("Reset information unavailable", systemImage: "wifi.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("No reset information found.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func activeWatchContent(_ watch: CodexResetWatch) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            radarHeading(
                title: "Reset watch",
                date: watch.observedAt,
                color: .orange
            )

            if let headline = CodexResetRadarPresentation.watchHeadline(watch) {
                Text(headline)
                    .font(.caption.weight(.medium))
            }

            Text(CodexResetRadarPresentation.displayText(watch.text))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            sourceLink(watch.source.url)
        }
    }

    private func latestResetContent(
        _ reset: CodexResetAnnouncement
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("Latest reset")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 8)
                Text(CodexResetRadarPresentation.relativeAge(
                    since: reset.announcedAt
                ))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            Text(CodexResetRadarPresentation.displayText(reset.text))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            sourceLink(reset.source.url)
        }
    }

    private func latestPostContent(_ post: CodexTiboPost) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("Latest from Tibo")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 8)
                Text(CodexResetRadarPresentation.relativeAge(
                    since: post.postedAt
                ))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            Text(CodexResetRadarPresentation.displayText(post.text))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            sourceLink(post.source.url)
        }
    }

    private func radarHeading(
        title: String,
        date: Date,
        color: Color
    ) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.caption.weight(.semibold))
            Spacer(minLength: 8)
            Text(CodexResetRadarPresentation.relativeAge(since: date))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func sourceLink(_ url: URL) -> some View {
        Link(destination: url) {
            Label("View on X", systemImage: "arrow.up.right")
                .font(.caption2.weight(.medium))
        }
    }

    @ViewBuilder
    private var control: some View {
        switch viewModel.resetNotificationAuthorization {
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .notDetermined:
            Button("Enable") {
                viewModel.requestResetNotificationAuthorization()
            }
            .controlSize(.small)
        case .denied:
            Button("Open Settings") {
                openNotificationSettings()
            }
            .controlSize(.small)
        case .authorized, .provisional:
            Menu("On") {
                Button("Send Test Alert") {
                    viewModel.sendTestResetNotification()
                }
                Button("Open Notification Settings") {
                    openNotificationSettings()
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        case .unavailable:
            Text("Unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed:
            Button("Try Again") {
                viewModel.requestResetNotificationAuthorization()
            }
            .controlSize(.small)
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=app.codexusage.local"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

private struct WorkTrailSettingsRow: View {
    @ObservedObject var recorder: CodexLocationRecorder

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Toggle("Work Trail", isOn: recordingEnabled)
                    .font(.title3.weight(.semibold))
                    .toggleStyle(CompactChubbyToggleStyle())

                if !recorder.samples.isEmpty {
                    Menu {
                        Button("Clear Location History", role: .destructive) {
                            recorder.clearHistory()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Work Trail options")
                }
            }

            if let latestSample = recorder.latestSample {
                Text(latestSample.displayPlace)
                    .font(.caption.weight(.medium))
                Text(latestSample.accuracyDescription)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else if let error = recorder.lastErrorDescription {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Text("Location stays on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var recordingEnabled: Binding<Bool> {
        Binding(
            get: { recorder.isRecording },
            set: { recorder.setRecordingEnabled($0) }
        )
    }
}
