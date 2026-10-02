import CodexUsageCore
import Foundation
import UserNotifications

enum CodexResetNotificationAuthorizationState: Equatable {
    case checking
    case notDetermined
    case denied
    case authorized
    case provisional
    case unavailable
    case failed(String)

    var allowsDelivery: Bool {
        switch self {
        case .authorized, .provisional:
            return true
        default:
            return false
        }
    }
}

@MainActor
final class CodexResetRadarNotifier {
    private let center: UNUserNotificationCenter?
    private let defaults: UserDefaults
    private let lastNotifiedWatchSignalIDKey =
        "codexUsage.resetRadar.lastNotifiedSignalID"
    private let lastNotifiedResetSignalIDKey =
        "codexUsage.resetRadar.lastNotifiedResetSignalID"
    private let lastNotifiedScheduledSignalIDKey =
        "codexUsage.resetRadar.lastNotifiedScheduledSignalID"
    private var pendingSignalIDs: Set<String> = []

    init(
        center: UNUserNotificationCenter? = nil,
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main
    ) {
        self.center = center ?? Self.notificationCenter(for: bundle)
        self.defaults = defaults
    }

    func notificationSettings() async -> CodexResetNotificationAuthorizationState {
        guard let center else { return .unavailable }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized:
            return .authorized
        case .provisional, .ephemeral:
            return .provisional
        @unknown default:
            return .unavailable
        }
    }

    func requestAuthorization() async -> CodexResetNotificationAuthorizationState {
        guard let center else { return .unavailable }
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
            return await notificationSettings()
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func notifyIfNeeded(
        _ snapshot: CodexResetRadarSnapshot?
    ) async -> CodexResetNotificationAuthorizationState {
        guard let center else { return .unavailable }
        let authorization = await notificationSettings()
        guard authorization.allowsDelivery else { return authorization }
        let lastWatchSignalID = defaults.string(
            forKey: lastNotifiedWatchSignalIDKey
        )
        let lastResetSignalID = defaults.string(
            forKey: lastNotifiedResetSignalIDKey
        )
        let plans = CodexResetRadarPresentation.notificationPlans(
            snapshot: snapshot,
            lastNotifiedWatchSignalID: lastWatchSignalID,
            lastNotifiedResetSignalID: lastResetSignalID,
            lastNotifiedScheduledSignalID: defaults.string(
                forKey: lastNotifiedScheduledSignalIDKey
            )
        )
        var result = authorization
        for plan in plans {
            let key: String
            switch plan.kind {
            case .watch: key = lastNotifiedWatchSignalIDKey
            case .scheduled: key = lastNotifiedScheduledSignalIDKey
            case .confirmed: key = lastNotifiedResetSignalIDKey
            }
            // Recheck after any prior await; another refresh may have sent it.
            guard defaults.string(forKey: key) != plan.signalID else { continue }
            let pendingID = "\(plan.kind.rawValue):\(plan.signalID)"
            guard !pendingSignalIDs.contains(pendingID) else { continue }
            pendingSignalIDs.insert(pendingID)
            defer { pendingSignalIDs.remove(pendingID) }
            do {
                let content = UNMutableNotificationContent()
                content.title = plan.title
                content.body = plan.body
                content.sound = .default
                content.userInfo = ["sourceURL": plan.sourceURL.absoluteString]
                let request = UNNotificationRequest(
                    identifier: "codexUsage.resetRadar.\(plan.kind.rawValue)",
                    content: content,
                    trigger: nil
                )
                try await center.add(request)
                // Only mark the signal that was successfully submitted.
                defaults.set(plan.signalID, forKey: key)
            } catch {
                result = .failed(error.localizedDescription)
            }
        }
        return result
    }

    func sendTestNotification() async -> CodexResetNotificationAuthorizationState {
        guard let center else { return .unavailable }
        let authorization = await notificationSettings()
        guard authorization.allowsDelivery else { return authorization }

        let content = UNMutableNotificationContent()
        content.title = "Codex Usage"
        content.body = "Possible reset • 80% by end of Saturday"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "codexUsage.resetRadar.test.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
            return authorization
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private static func notificationCenter(
        for bundle: Bundle
    ) -> UNUserNotificationCenter? {
        guard
            bundle.bundleURL.pathExtension == "app",
            bundle.bundleIdentifier != nil
        else {
            return nil
        }
        return UNUserNotificationCenter.current()
    }
}
