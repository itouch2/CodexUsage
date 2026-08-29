import Foundation

public struct CodexResetRadarCache {
    public static let defaultKey = "codexUsage.resetRadar.snapshot"

    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = Self.defaultKey
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func load(now: Date = Date()) -> CodexResetRadarSnapshot? {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(
                CodexResetRadarSnapshot.self,
                from: data
              )
        else {
            return nil
        }
        return snapshot.discardingExpiredWatch(at: now)
    }

    public func save(_ snapshot: CodexResetRadarSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }
}
