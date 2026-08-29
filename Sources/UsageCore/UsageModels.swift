import Foundation

public enum UsageProvider: String, Codable, CaseIterable, Sendable {
    case codex = "Codex"
}

public struct TokenUsage: Codable, Equatable, Sendable {
    public var inputTokens: Int
    public var cachedInputTokens: Int
    public var cacheCreationInputTokens: Int
    public var outputTokens: Int
    public var reasoningOutputTokens: Int
    public var totalTokens: Int

    public init(
        inputTokens: Int = 0,
        cachedInputTokens: Int = 0,
        cacheCreationInputTokens: Int = 0,
        outputTokens: Int = 0,
        reasoningOutputTokens: Int = 0,
        totalTokens: Int = 0
    ) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalTokens = totalTokens
    }

    public mutating func add(_ other: TokenUsage) {
        inputTokens += other.inputTokens
        cachedInputTokens += other.cachedInputTokens
        cacheCreationInputTokens += other.cacheCreationInputTokens
        outputTokens += other.outputTokens
        reasoningOutputTokens += other.reasoningOutputTokens
        totalTokens += other.totalTokens
    }
}

public struct RollingLimit: Codable, Equatable, Sendable {
    public var usedPercent: Double
    public var windowMinutes: Int
    public var resetsAt: Date?

    public init(usedPercent: Double, windowMinutes: Int, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
    }

    public var remainingPercent: Double {
        max(0, 100 - usedPercent)
    }
}

public struct CodexQuotaSample: Codable, Equatable, Sendable {
    public var capturedAt: Date
    public var usedPercent: Double
    public var windowMinutes: Int
    public var resetsAt: Date

    public init(
        capturedAt: Date,
        usedPercent: Double,
        windowMinutes: Int,
        resetsAt: Date
    ) {
        self.capturedAt = capturedAt
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
    }
}

public struct CodexCycleUsage: Codable, Equatable, Sendable {
    public var tokens: Int
    public var startsAt: Date
    public var resetsAt: Date
    public var isEstimated: Bool

    public init(
        tokens: Int,
        startsAt: Date,
        resetsAt: Date,
        isEstimated: Bool
    ) {
        self.tokens = tokens
        self.startsAt = startsAt
        self.resetsAt = resetsAt
        self.isEstimated = isEstimated
    }
}

public struct CodexCredits: Codable, Equatable, Sendable {
    public var hasCredits: Bool
    public var unlimited: Bool
    public var balance: String?

    public init(hasCredits: Bool, unlimited: Bool, balance: String?) {
        self.hasCredits = hasCredits
        self.unlimited = unlimited
        self.balance = balance
    }
}

public struct ProviderStatus: Codable, Equatable, Sendable {
    public var provider: UsageProvider
    public var planType: String?
    public var primaryLimit: RollingLimit?
    public var secondaryLimit: RollingLimit?
    public var credits: CodexCredits?
    public var latestUsage: TokenUsage?
    public var latestEventAt: Date?
    public var sourceDescription: String
    public var notes: [String]

    public init(
        provider: UsageProvider,
        planType: String? = nil,
        primaryLimit: RollingLimit? = nil,
        secondaryLimit: RollingLimit? = nil,
        credits: CodexCredits? = nil,
        latestUsage: TokenUsage? = nil,
        latestEventAt: Date? = nil,
        sourceDescription: String,
        notes: [String] = []
    ) {
        self.provider = provider
        self.planType = planType
        self.primaryLimit = primaryLimit
        self.secondaryLimit = secondaryLimit
        self.credits = credits
        self.latestUsage = latestUsage
        self.latestEventAt = latestEventAt
        self.sourceDescription = sourceDescription
        self.notes = notes
    }
}

public struct DailyUsage: Codable, Identifiable, Equatable, Sendable {
    public var id: String { "\(provider.rawValue)-\(day)" }
    public var provider: UsageProvider
    public var day: String
    public var usage: TokenUsage
    public var eventCount: Int

    public init(provider: UsageProvider, day: String, usage: TokenUsage, eventCount: Int) {
        self.provider = provider
        self.day = day
        self.usage = usage
        self.eventCount = eventCount
    }
}

public struct SessionUsage: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var provider: UsageProvider
    public var path: String
    public var latestEventAt: Date?
    public var usage: TokenUsage
    public var eventCount: Int

    public init(
        id: String,
        provider: UsageProvider,
        path: String,
        latestEventAt: Date?,
        usage: TokenUsage,
        eventCount: Int
    ) {
        self.id = id
        self.provider = provider
        self.path = path
        self.latestEventAt = latestEventAt
        self.usage = usage
        self.eventCount = eventCount
    }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var statuses: [ProviderStatus]
    public var dailyUsage: [DailyUsage]
    public var sessions: [SessionUsage]
    public var codexQuotaHistory: [CodexQuotaSample]
    public var codexCurrentCycleUsage: CodexCycleUsage?
    public var warnings: [String]

    public init(
        generatedAt: Date,
        statuses: [ProviderStatus],
        dailyUsage: [DailyUsage],
        sessions: [SessionUsage],
        codexQuotaHistory: [CodexQuotaSample] = [],
        codexCurrentCycleUsage: CodexCycleUsage? = nil,
        warnings: [String] = []
    ) {
        self.generatedAt = generatedAt
        self.statuses = statuses
        self.dailyUsage = dailyUsage
        self.sessions = sessions
        self.codexQuotaHistory = codexQuotaHistory
        self.codexCurrentCycleUsage = codexCurrentCycleUsage
        self.warnings = warnings
    }

    public func status(for provider: UsageProvider) -> ProviderStatus? {
        statuses.first { $0.provider == provider }
    }
}
