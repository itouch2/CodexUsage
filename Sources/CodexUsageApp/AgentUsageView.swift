import CodexUsageCore
import SwiftUI
import UsageCore

struct AgentUsageView: View {
    @ObservedObject var viewModel: AgentUsageViewModel
    @ObservedObject private var widgetController =
        CodexUsageDesktopWidgetController.shared
    @ObservedObject private var locationRecorder =
        CodexLocationRecorder.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ProviderCard(
                    status: viewModel.snapshot.status(for: .codex),
                    currentCycleUsage: viewModel.snapshot.codexCurrentCycleUsage
                )

                WorkTrailCard(recorder: locationRecorder)

                ResetRadarCard(viewModel: viewModel)

                InfoCard(title: "Desktop Widget") {
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

                        Button("Refresh") {
                            widgetController.refresh()
                        }

                        Spacer()

                        if widgetController.isVisible {
                            Button("Hide Widget") {
                                widgetController.hide()
                            }
                        } else {
                            Button("Show Widget") {
                                widgetController.show(viewModel: viewModel)
                            }
                        }
                    }
                }

                InfoCard(title: "Daily Usage") {
                    if viewModel.snapshot.dailyUsage.isEmpty {
                        Text("No local daily usage records found.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(Array(viewModel.snapshot.dailyUsage.prefix(8))) { row in
                                MetricRow(
                                    title: "\(row.provider.rawValue) · \(row.day)",
                                    value: formatTokens(row.usage.totalTokens),
                                    detail: "\(row.eventCount) events"
                                )
                                if row.id != viewModel.snapshot.dailyUsage.prefix(8).last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }

                InfoCard(title: "Recent Sessions") {
                    if viewModel.snapshot.sessions.isEmpty {
                        Text("No local sessions found.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(Array(viewModel.snapshot.sessions.prefix(10))) { session in
                                MetricRow(
                                    title: "\(session.provider.rawValue) · \(session.id)",
                                    value: formatTokens(session.usage.totalTokens),
                                    detail: session.latestEventAt.map {
                                        CompactTimestampFormatter.string(for: $0)
                                    } ?? session.path
                                )
                                if session.id != viewModel.snapshot.sessions.prefix(10).last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }

                if !viewModel.snapshot.warnings.isEmpty {
                    InfoCard(title: "Notes") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(viewModel.snapshot.warnings, id: \.self) { warning in
                                Text(warning)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .overlay(alignment: .topTrailing) {
                Button {
                    viewModel.refresh()
                } label: {
                    if viewModel.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(viewModel.isRefreshing)
                .help("Refresh")
            }
            .padding(24)
        }
        .tint(widgetController.palette.tintColor)
    }
}

private struct WorkTrailCard: View {
    @ObservedObject var recorder: CodexLocationRecorder

    var body: some View {
        InfoCard(title: "Work Trail") {
            Toggle(
                "Record time and location",
                isOn: Binding(
                    get: { recorder.isRecording },
                    set: { recorder.setRecordingEnabled($0) }
                )
            )

            VStack(alignment: .leading, spacing: 4) {
                Label(
                    recorder.statusTitle,
                    systemImage: recorder.isRecording ? "location.fill" : "location.slash"
                )
                .font(.subheadline.weight(.medium))

                if let latestSample = recorder.latestSample {
                    Text(
                        CompactTimestampFormatter.string(for: latestSample.capturedAt)
                            + " · "
                            + latestSample.accuracyDescription
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }

                if let error = recorder.lastErrorDescription {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if !recorder.samples.isEmpty {
                Divider()

                VStack(spacing: 10) {
                    ForEach(Array(recorder.samples.prefix(3))) { sample in
                        MetricRow(
                            title: sample.displayPlace,
                            value: CompactTimestampFormatter.string(for: sample.capturedAt),
                            detail: sample.accuracyDescription
                        )
                        if sample.id != recorder.samples.prefix(3).last?.id {
                            Divider()
                        }
                    }
                }

                Button("Clear Location History", role: .destructive) {
                    recorder.clearHistory()
                }
                .controlSize(.small)
            }

            Text(
                "Location stays on this Mac and is used to match Codex work with where it happened."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct ResetRadarCard: View {
    @ObservedObject var viewModel: AgentUsageViewModel

    private var snapshot: CodexResetRadarSnapshot? {
        viewModel.resetRadar
    }

    var body: some View {
        InfoCard(title: "Reset Radar") {
            VStack(alignment: .leading, spacing: 12) {
                if let latestPost = snapshot?.latestPost {
                    latestPostContent(latestPost)
                    Divider()
                }

                radarContent

                Divider()

                Text("Community signal · not your scheduled quota reset")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("Independent tracker · not affiliated with OpenAI")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Divider()

                notificationControls
            }
        }
    }

    @ViewBuilder
    private var notificationControls: some View {
        switch viewModel.resetNotificationAuthorization {
        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking notification access…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .notDetermined:
            HStack {
                Label("Reset alerts are available", systemImage: "bell")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Enable Reset Alerts") {
                    viewModel.requestResetNotificationAuthorization()
                }
                .controlSize(.small)
            }
        case .denied:
            HStack {
                Label("Notifications are off", systemImage: "bell.slash")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Link(
                    "Open Settings",
                    destination: URL(
                        string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=app.codexusage.local"
                    )!
                )
                .controlSize(.small)
            }
        case .authorized, .provisional:
            HStack {
                Label("Reset alerts are on", systemImage: "bell.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Send Test Alert") {
                    viewModel.sendTestResetNotification()
                }
                .controlSize(.small)
            }
        case .unavailable:
            Label(
                "Notifications are unavailable in this build",
                systemImage: "bell.slash"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        case let .failed(message):
            VStack(alignment: .leading, spacing: 8) {
                Label("Notification permission failed", systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button("Try Again") {
                    viewModel.requestResetNotificationAuthorization()
                }
                .controlSize(.small)
            }
        }
    }

    private func latestPostContent(_ post: CodexTiboPost) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Latest from Tibo")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(CodexResetRadarPresentation.relativeAge(since: post.postedAt))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(CodexResetRadarPresentation.displayText(post.text))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(4)

            sourceLink(post.source.url)
        }
    }

    @ViewBuilder
    private var radarContent: some View {
        if let watch = snapshot?.activeWatch {
            activeWatchContent(watch)
        } else if let reset = snapshot?.latestReset {
            latestResetContent(reset)
        } else if viewModel.isResetRadarRefreshing {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking Tibo's public reset signals…")
                    .foregroundStyle(.secondary)
            }
        } else if viewModel.isResetRadarUnavailable {
            Label("Reset radar is temporarily unavailable", systemImage: "wifi.slash")
                .foregroundStyle(.secondary)
        } else {
            Text("No public reset signal found.")
                .foregroundStyle(.secondary)
        }
    }

    private func activeWatchContent(_ watch: CodexResetWatch) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StatusPill(
                    title: watch.level == .strong
                        ? "Strong signal"
                        : "Elevated signal",
                    systemImage: "dot.radiowaves.left.and.right",
                    color: .orange
                )
                Spacer()
                Text("Tibo · " + CodexResetRadarPresentation.relativeAge(
                    since: watch.observedAt
                ))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            if let headline = CodexResetRadarPresentation.watchHeadline(watch) {
                Text(headline)
                    .font(.title3.weight(.semibold))
            }

            Text(CodexResetRadarPresentation.displayText(watch.text))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(4)

            sourceLink(watch.source.url)
        }
    }

    private func latestResetContent(
        _ reset: CodexResetAnnouncement
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StatusPill(
                    title: "No active watch",
                    systemImage: "checkmark.circle",
                    color: .green
                )
                Spacer()
                Text("Tibo · " + CodexResetRadarPresentation.relativeAge(
                    since: reset.announcedAt
                ))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            Text("Last surprise reset")
                .font(.title3.weight(.semibold))

            Text(CodexResetRadarPresentation.displayText(reset.text))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            sourceLink(reset.source.url)
        }
    }

    private func sourceLink(_ sourceURL: URL) -> some View {
        Link(destination: sourceURL) {
            Label("View Tibo's post", systemImage: "arrow.up.right")
                .font(.caption.weight(.medium))
        }
    }
}

private struct ProviderCard: View {
    var status: ProviderStatus?
    var currentCycleUsage: CodexCycleUsage?

    var body: some View {
        InfoCard(title: "Usage") {
            VStack(alignment: .leading, spacing: 12) {
                MetricRow(
                    title: "Latest event",
                    value: tokenSummary(status?.latestUsage),
                    detail: status?.latestEventAt.map {
                        CompactTimestampFormatter.string(for: $0)
                    } ?? "No local event"
                )

                if let currentCycleUsage {
                    MetricRow(
                        title: "Current cycle",
                        value: formatTokens(currentCycleUsage.tokens),
                        detail: currentCycleDetail(currentCycleUsage)
                    )
                }

                if let primary = status?.primaryLimit {
                    MetricRow(
                        title: "Primary window",
                        value: "\(Int(primary.remainingPercent.rounded()))% left",
                        detail: "\(primary.windowMinutes / 60)h rolling window"
                    )
                } else {
                    MetricRow(
                        title: "Quota",
                        value: "No data",
                        detail: "No local quota snapshot was found."
                    )
                }

                if let plan = status?.planType {
                    StatusPill(
                        title: plan,
                        systemImage: "person.crop.circle",
                        color: .purple
                    )
                }
            }
        }
    }

    private func currentCycleDetail(_ usage: CodexCycleUsage) -> String {
        let prefix = usage.isEstimated ? "Approx. · " : ""
        return prefix
            + "Since "
            + CompactTimestampFormatter.string(for: usage.startsAt)
            + " · account tokens"
    }
}
