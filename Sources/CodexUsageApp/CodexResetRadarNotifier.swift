import CodexUsageCore
import Foundation
import UserNotifications

@MainActor
final class CodexResetRadarNotifier {
    private let center: UNUserNotificationCenter?
    private let defaults: UserDefaults
    private let lastNotifiedSignalIDKey =
        "codexUsage.resetRadar.lastNotifiedSignalID"
    private var pendingSignalIDs: Set<String> = []

    init(
        center: UNUserNotificationCenter? = nil,
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main
    ) {
        self.center = center ?? Self.notificationCenter(for: bundle)
        self.defaults = defaults
    }

    func prepareAuthorization() {
        guard let center else { return }
        Task {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    func notifyIfNeeded(_ snapshot: CodexResetRadarSnapshot) {
        guard let center else { return }
        let lastSignalID = defaults.string(forKey: lastNotifiedSignalIDKey)
        guard let plan = CodexResetRadarPresentation.notificationPlan(
            snapshot: snapshot,
            lastNotifiedSignalID: lastSignalID
        ) else {
            return
        }
        guard !pendingSignalIDs.contains(plan.signalID) else { return }
        pendingSignalIDs.insert(plan.signalID)

        Task {
            defer { pendingSignalIDs.remove(plan.signalID) }
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                guard granted else { return }

                let content = UNMutableNotificationContent()
                content.title = plan.title
                content.body = plan.body
                content.sound = .default
                content.userInfo = [
                    "sourceURL": plan.sourceURL.absoluteString
                ]
                let request = UNNotificationRequest(
                    identifier: "codexUsage.resetRadar.watch",
                    content: content,
                    trigger: nil
                )
                try await center.add(request)
                defaults.set(plan.signalID, forKey: lastNotifiedSignalIDKey)
            } catch {
                return
            }
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
