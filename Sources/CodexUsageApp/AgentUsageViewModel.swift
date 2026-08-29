import CodexUsageCore
import Foundation
import UsageCore

@MainActor
final class AgentUsageViewModel: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot
    @Published private(set) var isRefreshing = false
    @Published private(set) var resetRadar: CodexResetRadarSnapshot?
    @Published private(set) var isResetRadarRefreshing = false
    @Published private(set) var isResetRadarUnavailable = false
    @Published private(set) var resetNotificationAuthorization:
        CodexResetNotificationAuthorizationState = .checking

    private let collector: UsageCollector
    private let resetRadarClient = CodexResetRadarClient()
    private let resetRadarNotifier = CodexResetRadarNotifier()
    private let resetRadarCache: CodexResetRadarCache
    private var refreshTimer: Timer?
    private var lastRadarRefreshAt: Date?
    private let radarRefreshInterval: TimeInterval = 30 * 60

    init(
        collector: UsageCollector = UsageCollector(),
        defaults: UserDefaults = .standard
    ) {
        self.collector = collector
        let resetRadarCache = CodexResetRadarCache(defaults: defaults)
        self.resetRadarCache = resetRadarCache
        self.snapshot = UsageSnapshot(
            generatedAt: Date(),
            statuses: [],
            dailyUsage: [],
            sessions: []
        )
        self.resetRadar = resetRadarCache.load()
        refresh()
    }

    func refresh(forceRadar: Bool = true) {
        discardExpiredResetWatchIfNeeded()
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshResetRadarIfNeeded(force: forceRadar)
        let collector = collector

        Task {
            let next = await Task.detached(priority: .userInitiated) {
                collector.collect()
            }.value
            await MainActor.run {
                snapshot = next
                isRefreshing = false
            }
        }
    }

    func startAutomaticRefresh() {
        guard refreshTimer == nil else { return }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(forceRadar: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func stopAutomaticRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refreshResetNotificationAuthorization() {
        let notifier = resetRadarNotifier
        Task {
            resetNotificationAuthorization = await notifier.notificationSettings()
        }
    }

    func requestResetNotificationAuthorization() {
        let notifier = resetRadarNotifier
        Task {
            let authorization = await notifier.requestAuthorization()
            resetNotificationAuthorization = authorization
            guard authorization.allowsDelivery else { return }
            resetNotificationAuthorization = await notifier.notifyIfNeeded(
                resetRadar
            )
        }
    }

    func sendTestResetNotification() {
        let notifier = resetRadarNotifier
        Task {
            resetNotificationAuthorization = await notifier.sendTestNotification()
        }
    }

    var codexRemainingPercent: Int? {
        guard let primaryLimit = snapshot.status(for: .codex)?.primaryLimit else {
            return nil
        }
        return Int(primaryLimit.remainingPercent.rounded())
    }

    private func refreshResetRadarIfNeeded(force: Bool) {
        guard !isResetRadarRefreshing else { return }
        if !force,
           let lastRadarRefreshAt,
           Date().timeIntervalSince(lastRadarRefreshAt) < radarRefreshInterval {
            return
        }

        lastRadarRefreshAt = Date()
        isResetRadarRefreshing = true
        let client = resetRadarClient
        Task {
            do {
                let next = try await client.fetch()
                    .discardingExpiredWatch(at: Date())
                resetRadarCache.save(next)
                resetRadar = next
                resetNotificationAuthorization = await resetRadarNotifier
                    .notifyIfNeeded(next)
                isResetRadarUnavailable = false
            } catch {
                isResetRadarUnavailable = resetRadar == nil
            }
            isResetRadarRefreshing = false
        }
    }

    private func discardExpiredResetWatchIfNeeded() {
        guard let resetRadar else { return }
        let current = resetRadar.discardingExpiredWatch(at: Date())
        guard current != resetRadar else { return }
        resetRadarCache.save(current)
        self.resetRadar = current
    }
}
