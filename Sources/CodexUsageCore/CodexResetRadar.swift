import Foundation

public struct CodexResetSource: Codable, Equatable, Sendable {
    public var type: String
    public var author: String
    public var url: URL

    public init(type: String, author: String, url: URL) {
        self.type = type
        self.author = author
        self.url = url
    }
}

public struct CodexTiboPost: Codable, Equatable, Sendable {
    public var id: String
    public var postedAt: Date
    public var text: String
    public var source: CodexResetSource

    public init(
        id: String,
        postedAt: Date,
        text: String,
        source: CodexResetSource
    ) {
        self.id = id
        self.postedAt = postedAt
        self.text = text
        self.source = source
    }

    public static func decodePublicMonitorHTML(_ data: Data) -> Self? {
        let articleMarker = #"<article data-testid="monitored-account-post">"#
        guard let html = String(data: data, encoding: .utf8),
              let tiboPost = html.range(
                of: #"https://x.com/thsottiaux/status/"#
              ),
              let articleStart = html.range(
                of: articleMarker,
                options: .backwards,
                range: html.startIndex..<tiboPost.lowerBound
              ),
              let articleEnd = html.range(
                of: "</article>",
                range: articleStart.upperBound..<html.endIndex
              )
        else {
            return nil
        }

        let article = String(html[articleStart.lowerBound..<articleEnd.upperBound])
        guard let sourceMatch = firstMatch(
            in: article,
            pattern: #"href="(https://x\.com/thsottiaux/status/([0-9]+))""#
        ),
        sourceMatch.count == 3,
        let sourceURL = URL(string: sourceMatch[1]),
        let textMatch = firstMatch(
            in: article,
            pattern: #"<span[^>]+title="([^"]*)""#
        ),
        textMatch.count == 2,
        let dateMatch = firstMatch(
            in: article,
            pattern: #"dateTime="([^"]+)""#
        ),
        dateMatch.count == 2,
        let postedAt = ISO8601DateFormatter.codexResetRadar.date(from: dateMatch[1])
        else {
            return nil
        }

        return CodexTiboPost(
            id: sourceMatch[2],
            postedAt: postedAt,
            text: decodeHTMLEntities(textMatch[1]),
            source: CodexResetSource(
                type: "x_post",
                author: "thsottiaux",
                url: sourceURL
            )
        )
    }

    private static func firstMatch(
        in text: String,
        pattern: String
    ) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              )
        else {
            return nil
        }
        return (0..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: text) else {
                return nil
            }
            return String(text[range])
        }
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

public struct CodexResetAnnouncement: Codable, Equatable, Sendable {
    public var id: String
    public var announcedAt: Date
    public var text: String
    public var source: CodexResetSource

    public init(
        id: String,
        announcedAt: Date,
        text: String,
        source: CodexResetSource
    ) {
        self.id = id
        self.announcedAt = announcedAt
        self.text = text
        self.source = source
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case announcedAt = "announced_at"
        case text
        case source
    }
}

public struct CodexResetWatch: Codable, Equatable, Sendable {
    public enum Level: String, Codable, Sendable {
        case elevated
        case strong
    }

    public var level: Level
    public var resetChancePercent: Int?
    public var forecastWindow: String
    public var observedAt: Date
    public var expiresAt: Date
    public var text: String
    public var source: CodexResetSource

    public init(
        level: Level,
        resetChancePercent: Int?,
        forecastWindow: String,
        observedAt: Date,
        expiresAt: Date,
        text: String,
        source: CodexResetSource
    ) {
        self.level = level
        self.resetChancePercent = resetChancePercent
        self.forecastWindow = forecastWindow
        self.observedAt = observedAt
        self.expiresAt = expiresAt
        self.text = text
        self.source = source
    }

    private enum CodingKeys: String, CodingKey {
        case level
        case resetChancePercent = "reset_chance_percent"
        case forecastWindow = "forecast_window"
        case observedAt = "observed_at"
        case expiresAt = "expires_at"
        case text
        case source
    }
}

public struct CodexResetStats: Codable, Equatable, Sendable {
    public var total: Int
    public var lastResetAt: Date?
    public var daysSinceLast: Double?
    public var averageIntervalDays: Double?

    public init(
        total: Int,
        lastResetAt: Date?,
        daysSinceLast: Double?,
        averageIntervalDays: Double?
    ) {
        self.total = total
        self.lastResetAt = lastResetAt
        self.daysSinceLast = daysSinceLast
        self.averageIntervalDays = averageIntervalDays
    }

    private enum CodingKeys: String, CodingKey {
        case total
        case lastResetAt = "last_reset_at"
        case daysSinceLast = "days_since_last"
        case averageIntervalDays = "avg_interval_days"
    }
}

public struct CodexResetRadarSnapshot: Codable, Equatable, Sendable {
    public var latestReset: CodexResetAnnouncement?
    public var activeWatch: CodexResetWatch?
    public var latestPost: CodexTiboPost?
    public var stats: CodexResetStats
    public var generatedAt: Date

    public init(
        latestReset: CodexResetAnnouncement?,
        activeWatch: CodexResetWatch?,
        latestPost: CodexTiboPost? = nil,
        stats: CodexResetStats,
        generatedAt: Date
    ) {
        self.latestReset = latestReset
        self.activeWatch = activeWatch
        self.latestPost = latestPost
        self.stats = stats
        self.generatedAt = generatedAt
    }

    public static func decode(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = ISO8601DateFormatter.codexResetRadar.date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid ISO 8601 date"
                )
            }
            return date
        }
        let response = try decoder.decode(CodexResetRadarResponse.self, from: data)
        return CodexResetRadarSnapshot(
            latestReset: response.data.latestReset,
            activeWatch: response.data.activeWatch,
            latestPost: nil,
            stats: response.data.stats,
            generatedAt: response.meta.generatedAt
        )
    }

    public func withLatestPost(_ latestPost: CodexTiboPost?) -> Self {
        CodexResetRadarSnapshot(
            latestReset: latestReset,
            activeWatch: activeWatch,
            latestPost: latestPost,
            stats: stats,
            generatedAt: generatedAt
        )
    }

    public func discardingExpiredWatch(at date: Date) -> Self {
        guard let activeWatch, activeWatch.expiresAt <= date else {
            return self
        }
        return CodexResetRadarSnapshot(
            latestReset: latestReset,
            activeWatch: nil,
            latestPost: latestPost,
            stats: stats,
            generatedAt: generatedAt
        )
    }
}

public struct CodexResetNotificationPlan: Equatable, Sendable {
    public var signalID: String
    public var title: String
    public var body: String
    public var sourceURL: URL

    public init(
        signalID: String,
        title: String,
        body: String,
        sourceURL: URL
    ) {
        self.signalID = signalID
        self.title = title
        self.body = body
        self.sourceURL = sourceURL
    }
}

private struct CodexResetRadarResponse: Decodable {
    var data: Payload
    var meta: Metadata

    struct Payload: Decodable {
        var latestReset: CodexResetAnnouncement?
        var activeWatch: CodexResetWatch?
        var stats: CodexResetStats

        private enum CodingKeys: String, CodingKey {
            case latestReset = "latest_reset"
            case activeWatch = "active_watch"
            case stats
        }
    }

    struct Metadata: Decodable {
        var generatedAt: Date

        private enum CodingKeys: String, CodingKey {
            case generatedAt = "generated_at"
        }
    }
}

private extension ISO8601DateFormatter {
    static let codexResetRadar: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        return formatter
    }()
}

public enum CodexResetRadarPresentation {
    public static func displayText(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"https?://\S+"#,
            with: "",
            options: .regularExpression
        )
        .split(whereSeparator: \Character.isWhitespace)
        .joined(separator: " ")
    }

    public static func watchHeadline(_ watch: CodexResetWatch?) -> String? {
        guard let watch else { return nil }
        if let chance = watch.resetChancePercent {
            return "Possible reset · \(chance)% in \(watch.forecastWindow)"
        }
        return "Possible reset · \(watch.forecastWindow)"
    }

    public static func notificationPlan(
        snapshot: CodexResetRadarSnapshot?,
        lastNotifiedSignalID: String?
    ) -> CodexResetNotificationPlan? {
        notificationPlan(
            snapshot: snapshot,
            lastNotifiedWatchSignalID: lastNotifiedSignalID,
            lastNotifiedResetSignalID: lastNotifiedSignalID
        )
    }

    public static func notificationPlan(
        snapshot: CodexResetRadarSnapshot?,
        lastNotifiedWatchSignalID: String?,
        lastNotifiedResetSignalID: String?
    ) -> CodexResetNotificationPlan? {
        guard let snapshot else { return nil }
        if let watch = snapshot.activeWatch {
            let signalID = watch.source.url.absoluteString
            guard signalID != lastNotifiedWatchSignalID else { return nil }
            return CodexResetNotificationPlan(
                signalID: signalID,
                title: "Codex reset watch",
                body: watchHeadline(watch)
                    ?? "A new reset signal was detected.",
                sourceURL: watch.source.url
            )
        }

        guard let reset = snapshot.latestReset else { return nil }
        let signalID = reset.source.url.absoluteString
        guard signalID != lastNotifiedResetSignalID else { return nil }
        let announcement = displayText(reset.text)
        return CodexResetNotificationPlan(
            signalID: signalID,
            title: "Codex reset confirmed",
            body: announcement.isEmpty
                ? "A new Codex usage reset was confirmed."
                : announcement,
            sourceURL: reset.source.url
        )
    }

    public static func relativeAge(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        let minutes = Int(seconds / 60)
        if minutes < 1 {
            return "just now"
        }
        if minutes < 60 {
            return "\(minutes)m ago"
        }
        let hours = minutes / 60
        if hours < 24 {
            return "\(hours)h ago"
        }
        return "\(hours / 24)d ago"
    }

    public static func widgetBadge(
        snapshot: CodexResetRadarSnapshot?,
        now: Date = Date()
    ) -> String? {
        guard let snapshot else { return nil }
        if let watch = snapshot.activeWatch {
            if let chance = watch.resetChancePercent {
                return "RESET WATCH \(chance)%"
            }
            return "RESET WATCH"
        }
        guard let reset = snapshot.latestReset else { return nil }
        return "RESET " + relativeAge(since: reset.announcedAt, now: now)
    }
}
