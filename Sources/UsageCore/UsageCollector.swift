import Darwin
import Foundation

public struct UsageCollector: Sendable {
    private static let resetTimeTolerance: TimeInterval = 60

    private let codexHome: URL
    private let codexExecutable: URL?
    private let initializeTimeout: TimeInterval
    private let accountTimeout: TimeInterval
    private let quotaHistoryCache: CodexQuotaHistoryCache

    public init(
        codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    ) {
        self.codexHome = codexHome
        self.codexExecutable = Self.findCodexExecutable()
        self.initializeTimeout = 2
        self.accountTimeout = 5
        self.quotaHistoryCache = CodexQuotaHistoryCache()
    }

    init(
        codexHome: URL,
        codexExecutable: URL?,
        initializeTimeout: TimeInterval = 2,
        accountTimeout: TimeInterval = 5
    ) {
        self.codexHome = codexHome
        self.codexExecutable = codexExecutable
        self.initializeTimeout = initializeTimeout
        self.accountTimeout = accountTimeout
        self.quotaHistoryCache = CodexQuotaHistoryCache()
    }

    public func collect() -> UsageSnapshot {
        var warnings: [String] = []
        var codex = collectCodex(warnings: &warnings)
        if let accountUsage = collectCodexAccountUsage() {
            codex = merging(accountUsage, into: codex)
        }

        return UsageSnapshot(
            generatedAt: Date(),
            statuses: [codex.status],
            dailyUsage: codex.dailyUsage.sorted { $0.day > $1.day },
            sessions: codex.sessions.sorted {
                ($0.latestEventAt ?? .distantPast) > ($1.latestEventAt ?? .distantPast)
            },
            codexQuotaHistory: codex.codexQuotaHistory,
            codexCurrentCycleUsage: codex.codexCurrentCycleUsage,
            warnings: warnings
        )
    }

    private func collectCodexAccountUsage() -> CodexAccountUsage? {
        guard let codexExecutable else { return nil }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = codexExecutable
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let responses = AppServerResponseBuffer()

        let initializeRequest: [String: Any] = [
            "id": 1,
            "method": "initialize",
            "params": [
                "clientInfo": [
                    "name": "codex-usage",
                    "title": "Codex Usage",
                    "version": "1"
                ],
                "capabilities": ["experimentalApi": true]
            ]
        ]
        let accountRequests: [[String: Any]] = [
            ["method": "initialized", "params": [:]],
            ["id": 2, "method": "account/rateLimits/read"],
            ["id": 3, "method": "account/usage/read"]
        ]

        guard let initializeData = encodedJSONLine(initializeRequest),
              let accountData = encodedJSONLines(accountRequests)
        else {
            return nil
        }

        do {
            try process.run()
            defer {
                close(input.fileHandleForWriting)
                close(output.fileHandleForReading)
                AppServerProcessCleanup.stop(process)
            }
            input.fileHandleForWriting.write(initializeData)
            guard readResponses(
                from: output.fileHandleForReading,
                into: responses,
                timeout: initializeTimeout,
                until: responses.hasInitialized
            ) else {
                return nil
            }
            input.fileHandleForWriting.write(accountData)
            guard readResponses(
                from: output.fileHandleForReading,
                into: responses,
                timeout: accountTimeout,
                until: responses.hasAccountUsage
            ) else {
                return nil
            }
        } catch {
            return nil
        }

        let rateLimitResult = responses.result(withID: 2)
        let usageResult = responses.result(withID: 3)

        guard let rateLimitResult,
              let fallback = rateLimitResult["rateLimits"] as? [String: Any]
        else {
            return nil
        }
        let byLimitID = rateLimitResult["rateLimitsByLimitId"] as? [String: Any]
        let account = byLimitID?["codex"] as? [String: Any] ?? fallback

        let dailyUsage = accountDailyUsage(
            from: usageResult?["dailyUsageBuckets"] as? [[String: Any]]
        )
        let primaryLimit = appServerRollingLimit(
            from: account["primary"] as? [String: Any]
        )

        return CodexAccountUsage(
            primaryLimit: primaryLimit,
            secondaryLimit: appServerRollingLimit(from: account["secondary"] as? [String: Any]),
            credits: appServerCredits(from: account["credits"] as? [String: Any]),
            planType: account["planType"] as? String,
            dailyUsage: dailyUsage,
            currentCycleUsage: currentCycleUsage(
                from: dailyUsage,
                primaryLimit: primaryLimit
            )
        )
    }

    private func accountDailyUsage(
        from buckets: [[String: Any]]?
    ) -> [DailyUsage]? {
        buckets?.compactMap { bucket -> DailyUsage? in
            guard let day = bucket["startDate"] as? String else { return nil }
            return DailyUsage(
                provider: .codex,
                day: day,
                usage: TokenUsage(totalTokens: intValue(bucket["tokens"])),
                eventCount: 0
            )
        }
    }

    private func currentCycleUsage(
        from dailyUsage: [DailyUsage]?,
        primaryLimit: RollingLimit?
    ) -> CodexCycleUsage? {
        guard let dailyUsage,
              let primaryLimit,
              primaryLimit.windowMinutes > 0,
              let resetsAt = primaryLimit.resetsAt
        else {
            return nil
        }

        let startsAt = resetsAt.addingTimeInterval(
            -TimeInterval(primaryLimit.windowMinutes * 60)
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let startDay = calendar.startOfDay(for: startsAt)
        let resetDay = calendar.startOfDay(for: resetsAt)
        let tokens = dailyUsage.reduce(into: 0) { total, row in
            guard let day = Self.accountDayFormatter.date(from: row.day),
                  day >= startDay,
                  day < resetDay || (day == resetDay && resetsAt > resetDay)
            else { return }
            total += row.usage.totalTokens
        }

        return CodexCycleUsage(
            tokens: tokens,
            startsAt: startsAt,
            resetsAt: resetsAt,
            isEstimated: startsAt != startDay || resetsAt != resetDay
        )
    }

    private func readResponses(
        from handle: FileHandle,
        into responses: AppServerResponseBuffer,
        timeout: TimeInterval,
        until predicate: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var descriptor = pollfd(
            fd: handle.fileDescriptor,
            events: Int16(POLLIN | POLLHUP),
            revents: 0
        )

        while !predicate() {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return predicate() }
            let timeoutMilliseconds = Int32(
                min(remaining * 1_000, Double(Int32.max)).rounded(.up)
            )
            let result = Darwin.poll(&descriptor, 1, timeoutMilliseconds)
            guard result > 0 else {
                if result == 0 { return predicate() }
                if errno == EINTR { continue }
                return false
            }
            let readableEvents = Int16(POLLIN | POLLHUP)
            guard descriptor.revents & readableEvents != 0 else {
                return predicate()
            }
            let data = handle.availableData
            guard !data.isEmpty else { return predicate() }
            responses.append(data)
        }
        return true
    }

    private func close(_ handle: FileHandle) {
        try? handle.close()
    }

    private func encodedJSONLine(_ object: [String: Any]) -> Data? {
        guard var data = try? JSONSerialization.data(withJSONObject: object) else {
            return nil
        }
        data.append(0x0A)
        return data
    }

    private func encodedJSONLines(_ objects: [[String: Any]]) -> Data? {
        var data = Data()
        for object in objects {
            guard let line = encodedJSONLine(object) else { return nil }
            data.append(line)
        }
        return data
    }

    private func merging(
        _ accountUsage: CodexAccountUsage,
        into collection: ProviderCollection
    ) -> ProviderCollection {
        var status = collection.status
        status.primaryLimit = accountUsage.primaryLimit
        status.secondaryLimit = accountUsage.secondaryLimit
        status.credits = accountUsage.credits
        status.planType = accountUsage.planType ?? status.planType
        status.notes.removeAll { $0.hasPrefix("额度快照时间：") }
        status.notes.append("额度来源：Codex 实时账户状态")
        let dailyUsage = mergedDailyUsage(
            accountUsage.dailyUsage,
            fillingMissingDaysFrom: collection.dailyUsage
        )

        return ProviderCollection(
            status: status,
            dailyUsage: dailyUsage,
            sessions: collection.sessions,
            codexQuotaHistory: quotaHistory(
                collection.codexQuotaHistory,
                matching: accountUsage.primaryLimit
            ),
            codexCurrentCycleUsage: currentCycleUsage(
                from: dailyUsage,
                primaryLimit: accountUsage.primaryLimit
            )
        )
    }

    private func mergedDailyUsage(
        _ accountDailyUsage: [DailyUsage]?,
        fillingMissingDaysFrom localDailyUsage: [DailyUsage]
    ) -> [DailyUsage] {
        guard let accountDailyUsage else { return localDailyUsage }
        var mergedByDay = Dictionary(
            uniqueKeysWithValues: accountDailyUsage.map { ($0.day, $0) }
        )
        for row in localDailyUsage where mergedByDay[row.day] == nil {
            mergedByDay[row.day] = row
        }
        return Array(mergedByDay.values).sorted { $0.day > $1.day }
    }

    private func appServerRollingLimit(from dictionary: [String: Any]?) -> RollingLimit? {
        guard let dictionary else { return nil }
        return RollingLimit(
            usedPercent: doubleValue(dictionary["usedPercent"]),
            windowMinutes: intValue(dictionary["windowDurationMins"]),
            resetsAt: dateFromUnix(dictionary["resetsAt"])
        )
    }

    private func appServerCredits(from dictionary: [String: Any]?) -> CodexCredits? {
        guard let dictionary else { return nil }
        return CodexCredits(
            hasCredits: dictionary["hasCredits"] as? Bool ?? false,
            unlimited: dictionary["unlimited"] as? Bool ?? false,
            balance: dictionary["balance"] as? String
        )
    }

    private static func findCodexExecutable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            ProcessInfo.processInfo.environment["CODEX_EXECUTABLE"].map {
                URL(fileURLWithPath: $0)
            },
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
            home.appendingPathComponent(".local/bin/codex")
        ].compactMap { $0 }

        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    private func collectCodex(warnings: inout [String]) -> ProviderCollection {
        let sessionRoot = codexHome.appendingPathComponent("sessions")
        let archivedRoot = codexHome.appendingPathComponent("archived_sessions")
        let paths = [
            mostRecentlyModifiedJSONLFile(under: sessionRoot),
            mostRecentlyModifiedJSONLFile(under: archivedRoot)
        ]
        .compactMap { $0 }
        .max { lhs, rhs in
            modificationDate(of: lhs) < modificationDate(of: rhs)
        }
        .map { [$0] } ?? []

        if paths.isEmpty {
            warnings.append("No Codex JSONL history found under \(codexHome.path).")
        }

        var latestEvent: ParsedEvent?
        var daily: [String: DailyAccumulator] = [:]
        var sessions: [SessionUsage] = []

        // 窗口额度可能在最新事件里为 null（如切换到 credits 模式），
        // 因此分别追踪「最近一条非空」的 primary / secondary 及其时间戳。
        var latestAccountPrimary: (Date?, [String: Any])?
        var latestAccountSecondary: (Date?, [String: Any])?
        var latestFallbackPrimary: (Date?, [String: Any])?
        var latestFallbackSecondary: (Date?, [String: Any])?
        var latestCredits: (Date?, CodexCredits)?
        var latestPlanType: (Date?, String)?
        var accountQuotaHistory: [CodexQuotaSample] = []
        var fallbackQuotaHistory: [CodexQuotaSample] = []

        for path in paths {
            var sessionUsage = TokenUsage()
            var sessionEvents = 0
            var sessionLatest: Date?

            forEachTokenCountJSONLine(from: path) { object in
                guard let payload = object["payload"] as? [String: Any],
                      payload["type"] as? String == "token_count"
                else { return }

                let timestamp = parseDate(object["timestamp"] as? String)
                let usage = tokenUsage(from: nested(payload, "info", "total_token_usage"))
                let lastUsage = tokenUsage(from: nested(payload, "info", "last_token_usage"))
                let eventUsage = lastUsage.totalTokens > 0 ? lastUsage : usage

                sessionUsage.add(eventUsage)
                sessionEvents += 1
                sessionLatest = maxDate(sessionLatest, timestamp)
                accumulate(eventUsage, provider: .codex, timestamp: timestamp, daily: &daily)

                let rateLimits = payload["rate_limits"] as? [String: Any]
                let isAccountLimit = rateLimits?["limit_id"] as? String == "codex"
                if let primary = rateLimits?["primary"] as? [String: Any] {
                    if let sample = quotaSample(
                        capturedAt: timestamp,
                        primary: primary
                    ) {
                        if isAccountLimit {
                            accountQuotaHistory.append(sample)
                        } else {
                            fallbackQuotaHistory.append(sample)
                        }
                    }
                    if isAccountLimit {
                        if latestAccountPrimary == nil
                            || (timestamp ?? .distantPast)
                                > (latestAccountPrimary?.0 ?? .distantPast)
                        {
                            latestAccountPrimary = (timestamp, primary)
                        }
                    } else if latestFallbackPrimary == nil
                        || (timestamp ?? .distantPast)
                            > (latestFallbackPrimary?.0 ?? .distantPast)
                    {
                        latestFallbackPrimary = (timestamp, primary)
                    }
                }
                if let secondary = rateLimits?["secondary"] as? [String: Any] {
                    if isAccountLimit {
                        if latestAccountSecondary == nil
                            || (timestamp ?? .distantPast)
                                > (latestAccountSecondary?.0 ?? .distantPast)
                        {
                            latestAccountSecondary = (timestamp, secondary)
                        }
                    } else if latestFallbackSecondary == nil
                        || (timestamp ?? .distantPast)
                            > (latestFallbackSecondary?.0 ?? .distantPast)
                    {
                        latestFallbackSecondary = (timestamp, secondary)
                    }
                }
                if let credits = codexCredits(from: rateLimits?["credits"] as? [String: Any]),
                   latestCredits == nil || (timestamp ?? .distantPast) > (latestCredits?.0 ?? .distantPast) {
                    latestCredits = (timestamp, credits)
                }
                if let plan = rateLimits?["plan_type"] as? String,
                   latestPlanType == nil || (timestamp ?? .distantPast) > (latestPlanType?.0 ?? .distantPast) {
                    latestPlanType = (timestamp, plan)
                }

                let event = ParsedEvent(
                    timestamp: timestamp,
                    usage: usage,
                    latestUsage: lastUsage,
                    rateLimits: rateLimits,
                    source: path.path
                )
                if latestEvent == nil || (timestamp ?? .distantPast) > (latestEvent?.timestamp ?? .distantPast) {
                    latestEvent = event
                }
            }

            if sessionEvents > 0 {
                sessions.append(SessionUsage(
                    id: path.lastPathComponent,
                    provider: .codex,
                    path: path.path,
                    latestEventAt: sessionLatest,
                    usage: sessionUsage,
                    eventCount: sessionEvents
                ))
            }
        }

        var notes: [String] = []
        if latestEvent == nil {
            notes.append("Codex current quota appears once a token_count event exists.")
        }
        // 窗口额度来自本地历史快照，可能不是实时值，标注其采集时间。
        let latestPrimary = latestAccountPrimary ?? latestFallbackPrimary
        let latestSecondary = latestAccountSecondary ?? latestFallbackSecondary
        let primaryLimit = rollingLimit(from: latestPrimary?.1)
        let selectedQuotaHistory = latestAccountPrimary == nil
            ? fallbackQuotaHistory
            : accountQuotaHistory
        let completeQuotaHistory = completeQuotaHistory(
            recentSamples: selectedQuotaHistory,
            matching: primaryLimit,
            roots: [sessionRoot, archivedRoot]
        )
        if let snapshotAt = latestPrimary?.0 ?? latestSecondary?.0 {
            notes.append("额度快照时间：\(Self.noteFormatter.string(from: snapshotAt))（本地历史，非实时）")
        }

        let status = ProviderStatus(
            provider: .codex,
            planType: latestPlanType?.1 ?? latestEvent?.rateLimits?["plan_type"] as? String,
            primaryLimit: primaryLimit,
            secondaryLimit: rollingLimit(from: latestSecondary?.1),
            credits: latestCredits?.1,
            latestUsage: latestEvent?.latestUsage,
            latestEventAt: latestEvent?.timestamp,
            sourceDescription: latestEvent?.source ?? codexHome.path,
            notes: notes
        )

        return ProviderCollection(
            status: status,
            dailyUsage: daily.values.map(\.dailyUsage).sorted { $0.day > $1.day },
            sessions: sessions,
            codexQuotaHistory: completeQuotaHistory,
            codexCurrentCycleUsage: nil
        )
    }

    private func completeQuotaHistory(
        recentSamples: [CodexQuotaSample],
        matching limit: RollingLimit?,
        roots: [URL]
    ) -> [CodexQuotaSample] {
        guard let limit, let resetsAt = limit.resetsAt else { return [] }
        let key = CodexQuotaWindowKey(
            codexHome: codexHome.path,
            windowMinutes: limit.windowMinutes,
            resetMinute: Int(
                (resetsAt.timeIntervalSinceReferenceDate / 60).rounded()
            )
        )
        let cached = quotaHistoryCache.samples(for: key)
        let recovered: [CodexQuotaSample]
        if let cached {
            recovered = cached
        } else {
            let windowStart = resetsAt.addingTimeInterval(
                -TimeInterval(limit.windowMinutes * 60)
            )
            let candidates = roots.flatMap {
                jsonlFilesModified(onOrAfter: windowStart, under: $0)
            }
            recovered = candidates.flatMap { path in
                quotaSamples(from: path, matching: limit)
            }
        }

        let complete = quotaHistory(
            recovered + recentSamples,
            matching: limit
        )
        quotaHistoryCache.setSamples(complete, for: key)
        return complete
    }

    private func jsonlFilesModified(
        onOrAfter start: Date,
        under root: URL
    ) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .contentModificationDateKey,
                .isRegularFileKey
            ],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { item -> URL? in
            guard let url = item as? URL, url.pathExtension == "jsonl",
                  modificationDate(of: url) >= start
            else {
                return nil
            }
            return url
        }
    }

    private func quotaSamples(
        from path: URL,
        matching limit: RollingLimit
    ) -> [CodexQuotaSample] {
        guard let resetsAt = limit.resetsAt else { return [] }
        var samples: [CodexQuotaSample] = []
        forEachTokenCountJSONLine(from: path) { object in
            guard let payload = object["payload"] as? [String: Any],
                  let rateLimits = payload["rate_limits"] as? [String: Any],
                  rateLimits["limit_id"] as? String == "codex",
                  let primary = rateLimits["primary"] as? [String: Any],
                  let sample = quotaSample(
                      capturedAt: parseDate(object["timestamp"] as? String),
                      primary: primary
                  ),
                  sample.windowMinutes == limit.windowMinutes,
                  abs(sample.resetsAt.timeIntervalSince(resetsAt))
                    < Self.resetTimeTolerance
            else {
                return
            }
            samples.append(sample)
        }
        return samples
    }

    private func quotaSample(
        capturedAt: Date?,
        primary: [String: Any]
    ) -> CodexQuotaSample? {
        guard let capturedAt,
              let resetsAt = dateFromUnix(primary["resets_at"])
        else {
            return nil
        }
        let windowMinutes = intValue(primary["window_minutes"])
        guard windowMinutes > 0 else { return nil }
        return CodexQuotaSample(
            capturedAt: capturedAt,
            usedPercent: doubleValue(primary["used_percent"]),
            windowMinutes: windowMinutes,
            resetsAt: resetsAt
        )
    }

    private func quotaHistory(
        _ samples: [CodexQuotaSample],
        matching limit: RollingLimit?
    ) -> [CodexQuotaSample] {
        guard let limit, let resetsAt = limit.resetsAt else { return [] }
        let matching = samples.filter {
            $0.windowMinutes == limit.windowMinutes
                && abs($0.resetsAt.timeIntervalSince(resetsAt))
                    < Self.resetTimeTolerance
        }
        var compacted: [CodexQuotaSample] = []
        for sample in matching.sorted(by: { $0.capturedAt < $1.capturedAt }) {
            if let latest = compacted.last,
               latest.usedPercent == sample.usedPercent {
                continue
            }
            if let latest = compacted.last,
               Calendar.current.isDate(
                   latest.capturedAt,
                   equalTo: sample.capturedAt,
                   toGranularity: .minute
               ) {
                compacted[compacted.count - 1] = sample
            } else {
                compacted.append(sample)
            }
        }
        return Array(compacted.suffix(360))
    }

    private func mostRecentlyModifiedJSONLFile(under root: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var latestURL: URL?
        var latestDate = Date.distantPast

        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let date = modificationDate(of: url)
            if latestURL == nil || date > latestDate {
                latestURL = url
                latestDate = date
            }
        }

        return latestURL
    }

    private func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
    }

    private func forEachTokenCountJSONLine(
        from url: URL,
        body: ([String: Any]) -> Void
    ) {
        let file = url.withUnsafeFileSystemRepresentation { path in
            path.flatMap { fopen($0, "r") }
        }
        guard let file else { return }
        defer { fclose(file) }

        var linePointer: UnsafeMutablePointer<CChar>?
        var lineCapacity = 0
        defer { free(linePointer) }
        let tokenCountMarker = Data(#""token_count""#.utf8)

        while true {
            let lineLength = getline(&linePointer, &lineCapacity, file)
            guard lineLength >= 0, let linePointer else { return }
            parseTokenCountJSONLine(
                Data(bytes: linePointer, count: lineLength),
                marker: tokenCountMarker,
                body: body
            )
        }
    }

    private func parseTokenCountJSONLine(
        _ line: Data,
        marker: Data,
        body: ([String: Any]) -> Void
    ) {
        guard line.range(of: marker) != nil,
              let object = try? JSONSerialization.jsonObject(with: line)
                as? [String: Any]
        else {
            return
        }
        body(object)
    }

    private func tokenUsage(from dictionary: [String: Any]?) -> TokenUsage {
        guard let dictionary else { return TokenUsage() }
        return TokenUsage(
            inputTokens: intValue(dictionary["input_tokens"]),
            cachedInputTokens: intValue(dictionary["cached_input_tokens"]),
            outputTokens: intValue(dictionary["output_tokens"]),
            reasoningOutputTokens: intValue(dictionary["reasoning_output_tokens"]),
            totalTokens: intValue(dictionary["total_tokens"])
        )
    }

    private func rollingLimit(from dictionary: [String: Any]?) -> RollingLimit? {
        guard let dictionary else { return nil }
        return RollingLimit(
            usedPercent: doubleValue(dictionary["used_percent"]),
            windowMinutes: intValue(dictionary["window_minutes"]),
            resetsAt: dateFromUnix(dictionary["resets_at"])
        )
    }

    private func codexCredits(from dictionary: [String: Any]?) -> CodexCredits? {
        guard let dictionary else { return nil }
        return CodexCredits(
            hasCredits: dictionary["has_credits"] as? Bool ?? false,
            unlimited: dictionary["unlimited"] as? Bool ?? false,
            balance: dictionary["balance"] as? String
        )
    }

    private func nested(_ dictionary: [String: Any], _ first: String, _ second: String) -> [String: Any]? {
        (dictionary[first] as? [String: Any])?[second] as? [String: Any]
    }

    private func accumulate(
        _ usage: TokenUsage,
        provider: UsageProvider,
        timestamp: Date?,
        daily: inout [String: DailyAccumulator]
    ) {
        let day = dayString(from: timestamp)
        var accumulator = daily[day] ?? DailyAccumulator(provider: provider, day: day)
        accumulator.usage.add(usage)
        accumulator.eventCount += 1
        daily[day] = accumulator
    }

    private func dayString(from date: Date?) -> String {
        guard let date else { return "unknown" }
        return Self.dayFormatter.string(from: date)
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return Self.isoFormatter.date(from: value)
    }

    private func dateFromUnix(_ value: Any?) -> Date? {
        let seconds = doubleValue(value)
        guard seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (.some(lhs), .some(rhs)): return max(lhs, rhs)
        case let (.some(lhs), .none): return lhs
        case let (.none, .some(rhs)): return rhs
        case (.none, .none): return nil
        }
    }

    private func intValue(_ value: Any?) -> Int {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let string = value as? String { return Int(string) ?? 0 }
        return 0
    }

    private func doubleValue(_ value: Any?) -> Double {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String { return Double(string) ?? 0 }
        return 0
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let accountDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let noteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
}

enum AppServerProcessCleanup {
    static func stop(
        _ process: Process,
        gracePeriod: TimeInterval = 0.25
    ) {
        guard process.isRunning else {
            process.waitUntilExit()
            return
        }

        process.terminate()
        let deadline = Date().addingTimeInterval(gracePeriod)
        while process.isRunning, Date() < deadline {
            usleep(10_000)
        }
        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
    }
}

private struct ParsedEvent {
    var timestamp: Date?
    var usage: TokenUsage
    var latestUsage: TokenUsage
    var rateLimits: [String: Any]?
    var source: String
}

private struct CodexAccountUsage {
    var primaryLimit: RollingLimit?
    var secondaryLimit: RollingLimit?
    var credits: CodexCredits?
    var planType: String?
    var dailyUsage: [DailyUsage]?
    var currentCycleUsage: CodexCycleUsage?
}

private struct CodexQuotaWindowKey: Hashable {
    var codexHome: String
    var windowMinutes: Int
    var resetMinute: Int
}

private final class CodexQuotaHistoryCache: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [CodexQuotaWindowKey: [CodexQuotaSample]] = [:]

    func samples(for key: CodexQuotaWindowKey) -> [CodexQuotaSample]? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    func setSamples(
        _ samples: [CodexQuotaSample],
        for key: CodexQuotaWindowKey
    ) {
        lock.lock()
        storage = [key: samples]
        lock.unlock()
    }
}

private final class AppServerResponseBuffer: @unchecked Sendable {
    private let condition = NSCondition()
    private var pendingData = Data()
    private var results: [Int: [String: Any]] = [:]

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        condition.lock()
        pendingData.append(data)
        while let newline = pendingData.firstIndex(of: 0x0A) {
            let line = pendingData[..<newline]
            pendingData.removeSubrange(...newline)
            if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
               let id = object["id"] as? NSNumber,
               let result = object["result"] as? [String: Any]
            {
                results[id.intValue] = result
            }
        }
        condition.broadcast()
        condition.unlock()
    }

    func hasInitialized() -> Bool {
        hasResults(withIDs: [1])
    }

    func hasAccountUsage() -> Bool {
        hasResults(withIDs: [2, 3])
    }

    func result(withID id: Int) -> [String: Any]? {
        condition.lock()
        defer { condition.unlock() }
        return results[id]
    }

    private func hasResults(withIDs ids: [Int]) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        return ids.allSatisfy { results[$0] != nil }
    }
}

private struct DailyAccumulator {
    var provider: UsageProvider
    var day: String
    var usage = TokenUsage()
    var eventCount = 0

    var dailyUsage: DailyUsage {
        DailyUsage(provider: provider, day: day, usage: usage, eventCount: eventCount)
    }
}

private struct ProviderCollection {
    var status: ProviderStatus
    var dailyUsage: [DailyUsage]
    var sessions: [SessionUsage]
    var codexQuotaHistory: [CodexQuotaSample]
    var codexCurrentCycleUsage: CodexCycleUsage?
}
