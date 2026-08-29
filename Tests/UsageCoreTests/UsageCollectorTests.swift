import Darwin
import XCTest
@testable import UsageCore

final class UsageCollectorTests: XCTestCase {
    func testCollectsCodexQuotaAndDailyUsage() throws {
        let root = try TemporaryRoot()
        let codexSessions = root.codex.appendingPathComponent("sessions/2026/06/25")
        try FileManager.default.createDirectory(at: codexSessions, withIntermediateDirectories: true)
        let file = codexSessions.appendingPathComponent("rollout.jsonl")
        try write(
            """
            {"timestamp":"2026-06-25T02:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":10,"reasoning_output_tokens":3,"total_tokens":110},"last_token_usage":{"input_tokens":40,"cached_input_tokens":10,"output_tokens":5,"reasoning_output_tokens":2,"total_tokens":45}},"rate_limits":{"primary":{"used_percent":25.0,"window_minutes":300,"resets_at":1782224440},"secondary":{"used_percent":50.0,"window_minutes":10080,"resets_at":1782635077},"plan_type":"prolite"}}}
            """,
            to: file
        )

        let snapshot = UsageCollector(
            codexHome: root.codex,
            codexExecutable: nil
        ).collect()
        let codex = try XCTUnwrap(snapshot.status(for: .codex))

        XCTAssertEqual(codex.planType, "prolite")
        XCTAssertEqual(codex.primaryLimit?.usedPercent, 25)
        XCTAssertEqual(codex.primaryLimit?.remainingPercent, 75)
        XCTAssertEqual(codex.latestUsage?.totalTokens, 45)
        XCTAssertTrue(snapshot.dailyUsage.contains { $0.provider == .codex && $0.usage.totalTokens == 45 })
    }

    func testIgnoresClaudeUsageHistory() throws {
        let root = try TemporaryRoot()
        let claudeProject = root.root.appendingPathComponent(".claude/projects/sample")
        try FileManager.default.createDirectory(at: claudeProject, withIntermediateDirectories: true)
        let file = claudeProject.appendingPathComponent("session.jsonl")
        try write(
            """
            {"timestamp":"2026-06-25T03:00:00.000Z","message":{"model":"claude-opus-4-8","usage":{"input_tokens":10,"cache_creation_input_tokens":2,"cache_read_input_tokens":30,"output_tokens":8}}}
            {"timestamp":"2026-06-25T04:00:00.000Z","message":{"model":"claude-opus-4-8","usage":{"input_tokens":5,"cache_creation_input_tokens":1,"cache_read_input_tokens":20,"output_tokens":4}}}
            """,
            to: file
        )

        let snapshot = UsageCollector(
            codexHome: root.codex,
            codexExecutable: nil
        ).collect()
        XCTAssertEqual(snapshot.statuses.map(\.provider), [.codex])
        XCTAssertTrue(snapshot.sessions.isEmpty)
        XCTAssertTrue(snapshot.dailyUsage.isEmpty)
        XCTAssertFalse(snapshot.warnings.contains { $0.localizedCaseInsensitiveContains("Claude") })
    }

    func testCollectsOnlyMostRecentlyModifiedCodexSession() throws {
        let root = try TemporaryRoot()
        let sessions = root.codex.appendingPathComponent("sessions/2026/07/19")
        let archived = root.codex.appendingPathComponent("archived_sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archived, withIntermediateDirectories: true)

        let older = archived.appendingPathComponent("older.jsonl")
        try write(
            """
            {"timestamp":"2026-07-19T01:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":111}},"rate_limits":{"primary":{"used_percent":90.0,"window_minutes":300},"plan_type":"older"}}}
            """,
            to: older
        )

        let latest = sessions.appendingPathComponent("latest.jsonl")
        try write(
            """
            {"timestamp":"2026-07-19T02:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":222}},"rate_limits":{"primary":{"used_percent":20.0,"window_minutes":300},"plan_type":"latest"}}}
            """,
            to: latest
        )

        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: older.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 200)],
            ofItemAtPath: latest.path
        )

        let snapshot = UsageCollector(
            codexHome: root.codex,
            codexExecutable: nil
        ).collect()
        let status = try XCTUnwrap(snapshot.status(for: .codex))

        XCTAssertEqual(snapshot.sessions.map(\.id), ["latest.jsonl"])
        XCTAssertEqual(snapshot.dailyUsage.map(\.usage.totalTokens), [222])
        XCTAssertEqual(status.latestUsage?.totalTokens, 222)
        XCTAssertEqual(status.primaryLimit?.usedPercent, 20)
        XCTAssertEqual(status.planType, "latest")
    }

    func testCollectsQuotaTrendFromLatestSessionCurrentWindow() throws {
        let root = try TemporaryRoot()
        let sessions = root.codex.appendingPathComponent("sessions/2026/08/05")
        try FileManager.default.createDirectory(
            at: sessions,
            withIntermediateDirectories: true
        )
        let file = sessions.appendingPathComponent("latest.jsonl")
        try write(
            """
            {"timestamp":"2026-08-05T01:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":10.0,"window_minutes":300,"resets_at":1785927600}}}}
            {"timestamp":"2026-08-05T01:05:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":10.0,"window_minutes":300,"resets_at":1785927600}}}}
            {"timestamp":"2026-08-05T01:10:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":10.0,"window_minutes":300,"resets_at":1785927600}}}}
            {"timestamp":"2026-08-05T01:20:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":18.0,"window_minutes":300,"resets_at":1785927601}}}}
            {"timestamp":"2026-08-05T01:30:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex_bengalfox","primary":{"used_percent":1.0,"window_minutes":10080,"resets_at":1786500000}}}}
            {"timestamp":"2026-08-05T02:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":24.0,"window_minutes":300,"resets_at":1785927600}}}}
            """,
            to: file
        )

        let snapshot = UsageCollector(
            codexHome: root.codex,
            codexExecutable: nil
        ).collect()

        XCTAssertEqual(snapshot.codexQuotaHistory.map(\.usedPercent), [10, 18, 24])
        XCTAssertEqual(
            snapshot.codexQuotaHistory.first?.capturedAt,
            ISO8601DateFormatter().date(from: "2026-08-05T01:00:00Z")
        )
        XCTAssertTrue(snapshot.codexQuotaHistory.allSatisfy {
            $0.windowMinutes == 300
                && abs(
                    $0.resetsAt.timeIntervalSince(
                        Date(timeIntervalSince1970: 1785927600)
                    )
                ) < 60
        })
    }

    func testQuotaTrendDropsSamplesFromPreviousResetWindow() throws {
        let root = try TemporaryRoot()
        let sessions = root.codex.appendingPathComponent("sessions/2026/08/05")
        try FileManager.default.createDirectory(
            at: sessions,
            withIntermediateDirectories: true
        )
        let file = sessions.appendingPathComponent("latest.jsonl")
        try write(
            """
            {"timestamp":"2026-08-05T01:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":90.0,"window_minutes":300,"resets_at":1785920000}}}}
            {"timestamp":"2026-08-05T02:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":4.0,"window_minutes":300,"resets_at":1785938000}}}}
            {"timestamp":"2026-08-05T02:10:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":7.0,"window_minutes":300,"resets_at":1785938000}}}}
            """,
            to: file
        )

        let snapshot = UsageCollector(
            codexHome: root.codex,
            codexExecutable: nil
        ).collect()

        XCTAssertEqual(snapshot.codexQuotaHistory.map(\.usedPercent), [4, 7])
    }

    func testRecoversCurrentQuotaWindowAcrossRecentSessions() throws {
        let root = try TemporaryRoot()
        let sessions = root.codex.appendingPathComponent("sessions/2026/08/05")
        try FileManager.default.createDirectory(
            at: sessions,
            withIntermediateDirectories: true
        )
        let reset = 1_785_938_000
        let windowStart = Date(timeIntervalSince1970: TimeInterval(reset - 300 * 60))
        let earlier = sessions.appendingPathComponent("earlier.jsonl")
        let latest = sessions.appendingPathComponent("latest.jsonl")
        try write(
            """
            {"timestamp":"2026-08-05T01:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":4.0,"window_minutes":300,"resets_at":1785938000}}}}
            """,
            to: earlier
        )
        try write(
            """
            {"timestamp":"2026-08-05T02:10:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":7.0,"window_minutes":300,"resets_at":1785938000}}}}
            """,
            to: latest
        )
        try FileManager.default.setAttributes(
            [.modificationDate: windowStart.addingTimeInterval(60)],
            ofItemAtPath: earlier.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: windowStart.addingTimeInterval(120)],
            ofItemAtPath: latest.path
        )

        let snapshot = UsageCollector(
            codexHome: root.codex,
            codexExecutable: nil
        ).collect()

        XCTAssertEqual(snapshot.codexQuotaHistory.map(\.usedPercent), [4, 7])
    }

    func testPrefersAccountQuotaOverNewerModelSpecificQuota() throws {
        let root = try TemporaryRoot()
        let sessions = root.codex.appendingPathComponent("sessions/2026/07/26")
        try FileManager.default.createDirectory(
            at: sessions,
            withIntermediateDirectories: true
        )
        let file = sessions.appendingPathComponent("latest.jsonl")
        try write(
            """
            {"timestamp":"2026-07-25T14:26:51.029Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":100}},"rate_limits":{"limit_id":"codex_bengalfox","limit_name":"GPT-5.3-Codex-Spark","primary":{"used_percent":0.0,"window_minutes":10080,"resets_at":1785584791},"plan_type":"prolite"}}}
            {"timestamp":"2026-07-25T16:08:42.917Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":200}},"rate_limits":{"limit_id":"codex","limit_name":null,"primary":{"used_percent":64.0,"window_minutes":10080,"resets_at":1785295643},"plan_type":"prolite"}}}
            {"timestamp":"2026-07-25T16:09:42.917Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":300}},"rate_limits":{"limit_id":"codex_bengalfox","limit_name":"GPT-5.3-Codex-Spark","primary":{"used_percent":1.0,"window_minutes":10080,"resets_at":1785584791},"plan_type":"prolite"}}}
            """,
            to: file
        )

        let status = try XCTUnwrap(
            UsageCollector(
                codexHome: root.codex,
                codexExecutable: nil
            ).collect().status(for: .codex)
        )

        XCTAssertEqual(status.primaryLimit?.usedPercent, 64)
        XCTAssertEqual(status.primaryLimit?.windowMinutes, 10080)
        XCTAssertEqual(
            status.primaryLimit?.resetsAt,
            Date(timeIntervalSince1970: 1785295643)
        )
    }

    func testCollectsLatestCodexCreditsMetadata() throws {
        let root = try TemporaryRoot()
        let sessions = root.codex.appendingPathComponent("sessions/2026/07/24")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let file = sessions.appendingPathComponent("latest.jsonl")
        try write(
            """
            {"timestamp":"2026-07-24T01:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":321}},"rate_limits":{"primary":{"used_percent":51.0,"window_minutes":10080,"resets_at":1785295643},"secondary":null,"credits":{"has_credits":false,"unlimited":false,"balance":"0"},"plan_type":"prolite"}}}
            """,
            to: file
        )

        let status = try XCTUnwrap(
            UsageCollector(
                codexHome: root.codex,
                codexExecutable: nil
            ).collect().status(for: .codex)
        )

        XCTAssertEqual(
            status.credits,
            CodexCredits(hasCredits: false, unlimited: false, balance: "0")
        )
    }

    func testLeavesCreditsNilWhenLatestSnapshotHasNoCreditsObject() throws {
        let root = try TemporaryRoot()
        let sessions = root.codex.appendingPathComponent("sessions/2026/07/24")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let file = sessions.appendingPathComponent("latest.jsonl")
        try write(
            """
            {"timestamp":"2026-07-24T01:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":321}},"rate_limits":{"primary":{"used_percent":20.0,"window_minutes":300},"plan_type":"prolite"}}}
            """,
            to: file
        )

        let status = try XCTUnwrap(
            UsageCollector(
                codexHome: root.codex,
                codexExecutable: nil
            ).collect().status(for: .codex)
        )

        XCTAssertNil(status.credits)
    }

    func testPrefersCurrentAccountUsageFromCodexAppServerOverStaleJSONL() throws {
        let root = try TemporaryRoot()
        let sessions = root.codex.appendingPathComponent("sessions/2026/07/25")
        try FileManager.default.createDirectory(
            at: sessions,
            withIntermediateDirectories: true
        )
        try write(
            """
            {"timestamp":"2026-07-25T16:12:21.458Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":128893}},"rate_limits":{"limit_id":"codex","primary":{"used_percent":65.0,"window_minutes":10080,"resets_at":1785295643},"plan_type":"prolite"}}}
            """,
            to: sessions.appendingPathComponent("stale.jsonl")
        )
        let fakeCodex = root.root.appendingPathComponent("fake-codex")
        try write(
            """
            #!/bin/sh
            while IFS= read -r line; do
              case "$line" in
                *'"id":1'*)
                  printf '%s\\n' '{"id":1,"result":{"codexHome":"/tmp"}}'
                  ;;
                *'"id":2'*)
                  printf '%s\\n' '{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":0,"windowDurationMins":10080,"resetsAt":1785656262},"secondary":null,"credits":{"hasCredits":false,"unlimited":false,"balance":"0"},"planType":"prolite"},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":0,"windowDurationMins":10080,"resetsAt":1785656262},"secondary":null,"credits":{"hasCredits":false,"unlimited":false,"balance":"0"},"planType":"prolite"}}}}'
                  ;;
                *'"id":3'*)
                  printf '%s\\n' '{"id":3,"result":{"summary":{"lifetimeTokens":5694494718},"dailyUsageBuckets":[{"startDate":"2026-07-25","tokens":28360654},{"startDate":"2026-07-26","tokens":123456}]}}'
                  exit 0
                  ;;
              esac
            done
            """,
            to: fakeCodex
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fakeCodex.path
        )

        let snapshot = UsageCollector(
            codexHome: root.codex,
            codexExecutable: fakeCodex
        ).collect()
        let status = try XCTUnwrap(snapshot.status(for: .codex))

        XCTAssertEqual(status.primaryLimit?.usedPercent, 0)
        XCTAssertEqual(status.primaryLimit?.windowMinutes, 10080)
        XCTAssertEqual(
            status.primaryLimit?.resetsAt,
            Date(timeIntervalSince1970: 1785656262)
        )
        XCTAssertEqual(snapshot.dailyUsage.first?.day, "2026-07-26")
        XCTAssertEqual(snapshot.dailyUsage.first?.usage.totalTokens, 123456)
        XCTAssertTrue(status.notes.contains("额度来源：Codex 实时账户状态"))
    }

    func testCollectsCurrentCycleTokensFromAccountDailyBuckets() throws {
        let root = try TemporaryRoot()
        let fakeCodex = root.root.appendingPathComponent("fake-codex")
        let resetsAt = try XCTUnwrap(
            Self.utcDateFormatter.date(from: "2026-08-08T00:00:00Z")
        )
        try write(
            """
            #!/bin/sh
            while IFS= read -r line; do
              case "$line" in
                *'"id":1'*)
                  printf '%s\n' '{"id":1,"result":{"codexHome":"/tmp"}}'
                  ;;
                *'"id":2'*)
                  printf '%s\n' '{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":\(Int(resetsAt.timeIntervalSince1970))},"secondary":null,"planType":"prolite"}}}'
                  ;;
                *'"id":3'*)
                  printf '%s\n' '{"id":3,"result":{"summary":{},"dailyUsageBuckets":[{"startDate":"2026-07-31","tokens":999},{"startDate":"2026-08-01","tokens":100},{"startDate":"2026-08-04","tokens":200},{"startDate":"2026-08-07","tokens":300},{"startDate":"2026-08-08","tokens":888}]}}'
                  exit 0
                  ;;
              esac
            done
            """,
            to: fakeCodex
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fakeCodex.path
        )

        let usage = UsageCollector(
            codexHome: root.codex,
            codexExecutable: fakeCodex
        ).collect().codexCurrentCycleUsage

        XCTAssertEqual(usage?.tokens, 600)
        XCTAssertEqual(
            usage?.startsAt,
            Self.utcDateFormatter.date(from: "2026-08-01T00:00:00Z")
        )
        XCTAssertEqual(usage?.resetsAt, resetsAt)
        XCTAssertEqual(usage?.isEstimated, false)
    }

    func testCurrentCycleTokensIncludeLocalDaysMissingFromStaleAccountBuckets() throws {
        let root = try TemporaryRoot()
        let sessions = root.codex.appendingPathComponent("sessions/2026/08/20")
        try FileManager.default.createDirectory(
            at: sessions,
            withIntermediateDirectories: true
        )
        try write(
            """
            {"timestamp":"2026-08-20T15:30:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":12345}},"rate_limits":{"limit_id":"codex","primary":{"used_percent":8.0,"window_minutes":10080,"resets_at":1787804462},"plan_type":"prolite"}}}
            """,
            to: sessions.appendingPathComponent("latest.jsonl")
        )

        let fakeCodex = root.root.appendingPathComponent("fake-codex")
        try write(
            """
            #!/bin/sh
            while IFS= read -r line; do
              case "$line" in
                *'"id":1'*) printf '%s\n' '{"id":1,"result":{}}' ;;
                *'"id":2'*) printf '%s\n' '{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":8,"windowDurationMins":10080,"resetsAt":1787804462},"planType":"prolite"}}}' ;;
                *'"id":3'*) printf '%s\n' '{"id":3,"result":{"summary":{},"dailyUsageBuckets":[{"startDate":"2026-08-17","tokens":999}]}}'; exit 0 ;;
              esac
            done
            """,
            to: fakeCodex
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fakeCodex.path
        )

        let snapshot = UsageCollector(
            codexHome: root.codex,
            codexExecutable: fakeCodex
        ).collect()

        XCTAssertTrue(snapshot.dailyUsage.contains {
            $0.day == "2026-08-20" && $0.usage.totalTokens == 12345
        })
        XCTAssertEqual(snapshot.codexCurrentCycleUsage?.tokens, 12345)
    }

    func testMarksCycleTokensEstimatedWhenWindowHasPartialBoundaryDays() throws {
        let root = try TemporaryRoot()
        let fakeCodex = root.root.appendingPathComponent("fake-codex")
        let resetsAt = try XCTUnwrap(
            Self.utcDateFormatter.date(from: "2026-08-08T07:30:00Z")
        )
        try write(
            """
            #!/bin/sh
            while IFS= read -r line; do
              case "$line" in
                *'"id":1'*) printf '%s\n' '{"id":1,"result":{}}' ;;
                *'"id":2'*) printf '%s\n' '{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":\(Int(resetsAt.timeIntervalSince1970))}}}}' ;;
                *'"id":3'*) printf '%s\n' '{"id":3,"result":{"summary":{},"dailyUsageBuckets":[{"startDate":"2026-08-01","tokens":100},{"startDate":"2026-08-08","tokens":200}]}}'; exit 0 ;;
              esac
            done
            """,
            to: fakeCodex
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fakeCodex.path
        )

        let usage = UsageCollector(
            codexHome: root.codex,
            codexExecutable: fakeCodex
        ).collect().codexCurrentCycleUsage

        XCTAssertEqual(usage?.tokens, 300)
        XCTAssertEqual(usage?.isEstimated, true)
    }

    func testRepeatedFailedAppServerCollectionsDoNotLeakFileDescriptors() throws {
        let root = try TemporaryRoot()
        let fakeCodex = root.root.appendingPathComponent("fake-codex-exits-early")
        try write(
            """
            #!/bin/sh
            while IFS= read -r line; do
              case "$line" in
                *'"id":1'*)
                  printf '%s\n' '{"id":1,"result":{"codexHome":"/tmp"}}'
                  ;;
                *)
                  exit 0
                  ;;
              esac
            done
            """,
            to: fakeCodex
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fakeCodex.path
        )
        let collector = UsageCollector(
            codexHome: root.codex,
            codexExecutable: fakeCodex,
            initializeTimeout: 0.1,
            accountTimeout: 0.1
        )

        _ = collector.collect()
        let baseline = openFileDescriptorCount()
        for _ in 0..<4 {
            _ = collector.collect()
        }
        usleep(100_000)
        let finalCount = openFileDescriptorCount()

        XCTAssertLessThanOrEqual(
            finalCount,
            baseline + 1,
            "Repeated failed app-server refreshes leaked \(finalCount - baseline) file descriptors"
        )
    }

    func testAppServerCleanupForceKillsAndReapsProcessIgnoringTermination() throws {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "trap '' TERM; printf 'ready\n'; while :; do :; done"
        ]
        process.standardOutput = output
        try process.run()
        defer {
            if process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
        }
        let ready = output.fileHandleForReading.availableData
        XCTAssertEqual(String(data: ready, encoding: .utf8), "ready\n")
        let startedAt = Date()

        AppServerProcessCleanup.stop(process, gracePeriod: 0.05)

        XCTAssertFalse(process.isRunning)
        XCTAssertEqual(process.terminationReason, .uncaughtSignal)
        XCTAssertEqual(process.terminationStatus, SIGKILL)
        XCTAssertLessThan(
            Date().timeIntervalSince(startedAt),
            1,
            "Cleanup failed to force-kill a child process that ignored SIGTERM"
        )
    }

    private func write(_ text: String, to url: URL) throws {
        try text.data(using: .utf8)?.write(to: url)
    }

    private func openFileDescriptorCount() -> Int {
        (0..<getdtablesize()).reduce(into: 0) { count, descriptor in
            if fcntl(descriptor, F_GETFD) != -1 {
                count += 1
            }
        }
    }

    private static let utcDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

}

private struct TemporaryRoot {
    let root: URL
    let codex: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("UsageCollectorTests-\(UUID().uuidString)")
        codex = root.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
    }
}
