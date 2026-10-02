import Foundation
import XCTest
@testable import CodexUsageCore

final class CodexResetRadarTests: XCTestCase {
    func testDecodesLatestTiboPostFromPublicMonitor() throws {
        let html = #"""
        <article data-testid="monitored-account-post"><a href="https://x.com/thsottiaux/status/2088878697998844277" aria-label="Open latest post from Tibo Sottiaux on X"><span title="Shipping &amp; listening.">Shipping &amp; listening.</span><time dateTime="2026-08-16T06:41:05.000Z">Aug 16</time></a></article>
        <article data-testid="monitored-account-post"><a href="https://x.com/OpenAI/status/1"><span title="Other post">Other post</span><time dateTime="2026-08-15T00:00:00.000Z">Aug 15</time></a></article>
        """#

        let post = try XCTUnwrap(
            CodexTiboPost.decodePublicMonitorHTML(Data(html.utf8))
        )

        XCTAssertEqual(post.id, "2088878697998844277")
        XCTAssertEqual(post.text, "Shipping & listening.")
        XCTAssertEqual(
            post.source.url.absoluteString,
            "https://x.com/thsottiaux/status/2088878697998844277"
        )
        XCTAssertEqual(
            post.postedAt,
            ISO8601DateFormatter().date(from: "2026-08-16T06:41:05Z")
        )
    }

    func testFindsTiboWhenAnotherMonitoredAccountComesFirst() throws {
        let html = #"""
        <article data-testid="monitored-account-post"><a href="https://x.com/OpenAI/status/1"><span title="Other post">Other post</span><time dateTime="2026-08-16T07:00:00.000Z">Aug 16</time></a></article>
        <article data-testid="monitored-account-post"><a href="https://x.com/thsottiaux/status/2"><span title="Tibo post">Tibo post</span><time dateTime="2026-08-16T06:00:00.000Z">Aug 16</time></a></article>
        """#

        XCTAssertEqual(
            CodexTiboPost.decodePublicMonitorHTML(Data(html.utf8))?.id,
            "2"
        )
    }

    func testDecodesLatestResetAndActiveWatchFromPublicAPI() throws {
        let json = #"""
        {
          "data": {
            "latest_reset": {
              "id": "2087706104814023111",
              "announced_at": "2026-08-13T01:01:37.000Z",
              "text": "Enjoy a nice reset everyone. Landing in the next hour or so.",
              "source": {
                "type": "x_post",
                "author": "thsottiaux",
                "url": "https://x.com/thsottiaux/status/2087706104814023111"
              }
            },
            "active_watch": {
              "level": "strong",
              "reset_chance_percent": 78,
              "forecast_window": "next 24h",
              "observed_at": "2026-08-15T04:30:00.000Z",
              "expires_at": "2026-08-16T04:30:00.000Z",
              "text": "Tibo said a reset is likely tomorrow.",
              "source": {
                "type": "x_post",
                "author": "thsottiaux",
                "url": "https://x.com/thsottiaux/status/2088000000000000000"
              }
            },
            "stats": {
              "total": 43,
              "last_reset_at": "2026-08-13T01:01:37.000Z",
              "days_since_last": 2.2,
              "avg_interval_days": 7.9
            }
          },
          "meta": {
            "api_version": "v1",
            "generated_at": "2026-08-15T06:36:38.627Z"
          }
        }
        """#

        let snapshot = try CodexResetRadarSnapshot.decode(Data(json.utf8))

        XCTAssertEqual(snapshot.latestReset?.id, "2087706104814023111")
        XCTAssertEqual(snapshot.latestReset?.source.author, "thsottiaux")
        XCTAssertEqual(snapshot.activeWatch?.level, .strong)
        XCTAssertEqual(snapshot.activeWatch?.resetChancePercent, 78)
        XCTAssertEqual(snapshot.activeWatch?.forecastWindow, "next 24h")
        XCTAssertEqual(snapshot.stats.total, 43)
        XCTAssertEqual(snapshot.stats.averageIntervalDays, 7.9)
    }

    func testDecodesAQuietRadarWithoutAWatch() throws {
        let json = #"""
        {
          "data": {
            "latest_reset": null,
            "active_watch": null,
            "stats": {
              "total": 0,
              "last_reset_at": null,
              "days_since_last": null,
              "avg_interval_days": null
            }
          },
          "meta": {
            "api_version": "v1",
            "generated_at": "2026-08-15T06:36:38.627Z"
          }
        }
        """#

        let snapshot = try CodexResetRadarSnapshot.decode(Data(json.utf8))

        XCTAssertNil(snapshot.latestReset)
        XCTAssertNil(snapshot.activeWatch)
        XCTAssertNil(snapshot.stats.daysSinceLast)
    }

    func testPresentsWatchAsPossibilityInsteadOfACommitment() throws {
        let snapshot = try fixtureSnapshot(withActiveWatch: true)

        XCTAssertEqual(
            CodexResetRadarPresentation.watchHeadline(snapshot.activeWatch),
            "Possible reset · 78% in next 24h"
        )
        XCTAssertEqual(
            CodexResetRadarPresentation.widgetBadge(
                snapshot: snapshot,
                now: Date(timeIntervalSince1970: 1_776_230_400)
            ),
            "RESET WATCH 78%"
        )
        XCTAssertEqual(
            CodexResetRadarPresentation.menuBarBadge(
                snapshot: snapshot,
                now: Date(timeIntervalSince1970: 1_776_230_400)
            ),
            "WATCH"
        )
    }

    func testPlansOneNotificationForANewActiveWatch() throws {
        let snapshot = try fixtureSnapshot(withActiveWatch: true)

        let plan = CodexResetRadarPresentation.notificationPlan(
            snapshot: snapshot,
            lastNotifiedSignalID: nil
        )

        XCTAssertEqual(
            plan?.signalID,
            "https://x.com/thsottiaux/status/2088000000000000000"
        )
        XCTAssertEqual(plan?.title, "Codex reset watch")
        XCTAssertEqual(plan?.body, "Possible reset · 78% in next 24h")
        XCTAssertNil(
            CodexResetRadarPresentation.notificationPlan(
                snapshot: snapshot,
                lastNotifiedWatchSignalID: plan?.signalID,
                lastNotifiedResetSignalID: snapshot.latestReset?.source.url.absoluteString
            )
        )
    }

    func testPlansOneNotificationForANewConfirmedResetWithoutAWatch() throws {
        let snapshot = try fixtureSnapshot(withActiveWatch: false)

        let plan = CodexResetRadarPresentation.notificationPlan(
            snapshot: snapshot,
            lastNotifiedSignalID: nil
        )

        XCTAssertEqual(
            plan?.signalID,
            "https://x.com/thsottiaux/status/1"
        )
        XCTAssertEqual(plan?.title, "Codex reset confirmed")
        XCTAssertEqual(plan?.body, "Usage limits have been reset.")
        XCTAssertEqual(
            plan?.sourceURL.absoluteString,
            "https://x.com/thsottiaux/status/1"
        )
        XCTAssertNil(
            CodexResetRadarPresentation.notificationPlan(
                snapshot: snapshot,
                lastNotifiedSignalID: plan?.signalID
            )
        )
    }

    func testPresentsLastConfirmedResetWhenThereIsNoWatch() throws {
        let snapshot = try fixtureSnapshot(withActiveWatch: false)
        let now = try XCTUnwrap(snapshot.latestReset?.announcedAt)
            .addingTimeInterval(2 * 86_400 + 3_600)

        XCTAssertEqual(
            CodexResetRadarPresentation.relativeAge(
                since: now.addingTimeInterval(-2 * 86_400 - 3_600),
                now: now
            ),
            "2d ago"
        )
        XCTAssertEqual(
            CodexResetRadarPresentation.widgetBadge(
                snapshot: snapshot,
                now: now
            ),
            "RESET 2d ago"
        )
        XCTAssertEqual(
            CodexResetRadarPresentation.menuBarBadge(
                snapshot: snapshot,
                now: try XCTUnwrap(snapshot.latestReset?.announcedAt)
                    .addingTimeInterval(2 * 3_600)
            ),
            "RESET"
        )
        XCTAssertNil(
            CodexResetRadarPresentation.menuBarBadge(
                snapshot: snapshot,
                now: try XCTUnwrap(snapshot.latestReset?.announcedAt)
                    .addingTimeInterval(24 * 3_600)
            )
        )
    }

    func testOmitsMenuBarBadgeWhenThereIsNoResetSignal() throws {
        let snapshot = CodexResetRadarSnapshot(
            latestReset: nil,
            activeWatch: nil,
            latestPost: nil,
            stats: CodexResetStats(
                total: 0,
                lastResetAt: nil,
                daysSinceLast: nil,
                averageIntervalDays: nil
            ),
            generatedAt: Date()
        )

        XCTAssertNil(
            CodexResetRadarPresentation.menuBarBadge(
                snapshot: snapshot,
                now: Date()
            )
        )
    }

    func testAcknowledgedMenuBarSignalHidesItsBadge() throws {
        let snapshot = try fixtureSnapshot(withActiveWatch: false)
        let now = try XCTUnwrap(snapshot.latestReset?.announcedAt)
            .addingTimeInterval(2 * 3_600)
        let signalID = try XCTUnwrap(
            CodexResetRadarPresentation.menuBarSignalID(
                snapshot: snapshot,
                now: now
            )
        )

        XCTAssertEqual(
            signalID,
            "https://x.com/thsottiaux/status/1"
        )
        XCTAssertNil(
            CodexResetRadarPresentation.menuBarBadge(
                snapshot: snapshot,
                now: now,
                acknowledgedSignalID: signalID
            )
        )
    }

    func testNewMenuBarSignalReturnsAfterOlderAcknowledgement() throws {
        var snapshot = try fixtureSnapshot(withActiveWatch: false)
        let previousSignalID = try XCTUnwrap(
            snapshot.latestReset?.source.url.absoluteString
        )
        let now = try XCTUnwrap(snapshot.latestReset?.announcedAt)
            .addingTimeInterval(2 * 3_600)
        snapshot.latestReset = CodexResetAnnouncement(
            id: "2",
            announcedAt: now.addingTimeInterval(-60),
            text: "Another reset was confirmed.",
            source: CodexResetSource(
                type: "x_post",
                author: "thsottiaux",
                url: try XCTUnwrap(
                    URL(string: "https://x.com/thsottiaux/status/2")
                )
            )
        )

        XCTAssertEqual(
            CodexResetRadarPresentation.menuBarBadge(
                snapshot: snapshot,
                now: now,
                acknowledgedSignalID: previousSignalID
            ),
            "RESET"
        )
    }

    func testRemovesTrackingLinksFromDisplayedPostText() {
        XCTAssertEqual(
            CodexResetRadarPresentation.displayText(
                "Reset lands soon. https://t.co/ABC123 Keep building."
            ),
            "Reset lands soon. Keep building."
        )
    }

    func testCacheRestoresAnUnexpiredResetWatch() throws {
        let defaults = try makeIsolatedDefaults()
        let cache = CodexResetRadarCache(defaults: defaults)
        let snapshot = try fixtureSnapshot(withActiveWatch: true)
        let now = try XCTUnwrap(snapshot.activeWatch?.expiresAt)
            .addingTimeInterval(-60)

        cache.save(snapshot)

        XCTAssertEqual(cache.load(now: now), snapshot)
    }

    func testCacheDropsOnlyTheExpiredWatch() throws {
        let defaults = try makeIsolatedDefaults()
        let cache = CodexResetRadarCache(defaults: defaults)
        let snapshot = try fixtureSnapshot(withActiveWatch: true)
        let now = try XCTUnwrap(snapshot.activeWatch?.expiresAt)

        cache.save(snapshot)

        let restored = try XCTUnwrap(cache.load(now: now))
        XCTAssertNil(restored.activeWatch)
        XCTAssertEqual(restored.latestReset, snapshot.latestReset)
        XCTAssertEqual(restored.stats, snapshot.stats)
    }

    // Captured API shape: an observed reset has no author, and scheduled_for
    // has no fractional seconds even though announced_at does.
    private func scheduledSnapshot() throws -> CodexResetRadarSnapshot {
        let json = #"""
        {"data":{"latest_reset":{"id":"observed-20260929T190000Z","reset_type":"banked","announced_at":"2026-09-29T19:00:00.000Z","text":"@theo Shhhhhh","source":{"type":"observed","url":"https://x.com/thsottiaux/status/2105120226027450685"}},"scheduled_reset":{"id":"2105843926221660585","status":"scheduled","reset_type":"regular","announced_at":"2026-10-02T02:14:51.000Z","scheduled_for":"2026-10-02T17:00:00Z","text":"Global reset landing tomorrow 10am PST for all paid ChatGPT accounts. Apologies for the slow start with GPT-6.1 Sol, it's now back to running at expected speeds after the massive load spike in the first two days.","source":{"type":"x_post","author":"thsottiaux","url":"https://x.com/thsottiaux/status/2105843926221660585"}},"active_watch":null,"stats":{"total":56,"last_reset_at":"2026-09-29T19:00:00.000Z","days_since_last":2.6,"avg_interval_days":6.9}},"meta":{"api_version":"v1","generated_at":"2026-10-02T10:23:09.427Z"}}
        """#
        return try CodexResetRadarSnapshot.decode(Data(json.utf8))
    }

    func testDecodesScheduledResetAndObservedSourceWithoutAuthor() throws {
        let snapshot = try scheduledSnapshot()
        XCTAssertNil(snapshot.latestReset?.source.author)
        XCTAssertEqual(snapshot.latestReset?.id, "observed-20260929T190000Z")
        let scheduled = try XCTUnwrap(snapshot.pendingScheduledReset)
        XCTAssertEqual(scheduled.source.author, "thsottiaux")
        XCTAssertEqual(scheduled.scheduledFor,
                       ISO8601DateFormatter().date(from: "2026-10-02T17:00:00Z"))
        XCTAssertNil(snapshot.activeWatch)
    }

    func testScheduledResetSurvivesEnrichmentExpirationAndCacheRoundTrip() throws {
        var snapshot = try scheduledSnapshot()
        snapshot.activeWatch = try fixtureSnapshot(withActiveWatch: true).activeWatch
        let scheduled = try XCTUnwrap(snapshot.pendingScheduledReset)
        let now = scheduled.scheduledFor.addingTimeInterval(-3600)
        let enriched = snapshot.withLatestPost(nil).discardingExpiredWatch(at: now)
        XCTAssertEqual(enriched.scheduledReset, scheduled)
        XCTAssertNil(enriched.activeWatch)
        let cache = CodexResetRadarCache(defaults: try makeIsolatedDefaults())
        cache.save(enriched)
        XCTAssertEqual(cache.load(now: now), enriched)
    }

    func testOldCacheWithoutScheduledFieldStillLoads() throws {
        let snapshot = try fixtureSnapshot(withActiveWatch: false)
        let encoded = try JSONEncoder().encode(snapshot)
        let restored = try JSONDecoder().decode(CodexResetRadarSnapshot.self, from: encoded)
        XCTAssertEqual(restored, snapshot)
        XCTAssertNil(restored.scheduledReset)
    }

    func testScheduledCountdownAndMenuAcknowledgement() throws {
        let snapshot = try scheduledSnapshot()
        let scheduled = try XCTUnwrap(snapshot.pendingScheduledReset)
        let now = scheduled.scheduledFor.addingTimeInterval(-8 * 3600)
        XCTAssertEqual(CodexResetRadarPresentation.widgetBadge(snapshot: snapshot, now: now),
                       "Reset within 8h 0m")
        XCTAssertEqual(CodexResetRadarPresentation.menuBarBadge(snapshot: snapshot, now: now),
                       "SCHEDULED")
        XCTAssertNil(CodexResetRadarPresentation.menuBarBadge(
            snapshot: snapshot, now: now, acknowledgedSignalID: scheduled.signalID
        ))
        XCTAssertEqual(CodexResetRadarPresentation.scheduledHeadline(
            scheduled, now: scheduled.scheduledFor.addingTimeInterval(-1)), "Reset within 1m")
    }

    func testPassedDeadlineWaitsForConfirmationWithoutAnotherScheduledAlert() throws {
        var snapshot = try scheduledSnapshot()
        let scheduled = try XCTUnwrap(snapshot.pendingScheduledReset)
        XCTAssertEqual(CodexResetRadarPresentation.widgetBadge(
            snapshot: snapshot, now: scheduled.scheduledFor),
            "Reset scheduled · Awaiting confirmation")
        XCTAssertTrue(CodexResetRadarPresentation.notificationPlans(
            snapshot: snapshot, lastNotifiedWatchSignalID: nil,
            lastNotifiedResetSignalID: snapshot.latestReset?.source.url.absoluteString,
            lastNotifiedScheduledSignalID: nil, now: scheduled.scheduledFor
        ).isEmpty)
        snapshot.latestReset?.announcedAt = scheduled.scheduledFor
        XCTAssertNil(snapshot.pendingScheduledReset)
    }

    func testScheduledNotificationDeduplicatesAndRescheduleNotifiesAgain() throws {
        var snapshot = try scheduledSnapshot()
        let scheduled = try XCTUnwrap(snapshot.pendingScheduledReset)
        let now = scheduled.scheduledFor.addingTimeInterval(-3600)
        let resetID = snapshot.latestReset?.source.url.absoluteString
        let plans = CodexResetRadarPresentation.notificationPlans(
            snapshot: snapshot, lastNotifiedWatchSignalID: nil,
            lastNotifiedResetSignalID: resetID, lastNotifiedScheduledSignalID: nil, now: now
        )
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans.first?.kind, .scheduled)
        XCTAssertEqual(plans.first?.sourceURL, scheduled.source.url)
        XCTAssertTrue(plans.first?.body.contains("Reset within 1h 0m") == true)
        XCTAssertTrue(CodexResetRadarPresentation.notificationPlans(
            snapshot: snapshot, lastNotifiedWatchSignalID: nil,
            lastNotifiedResetSignalID: resetID,
            lastNotifiedScheduledSignalID: scheduled.signalID, now: now
        ).isEmpty)
        snapshot.scheduledReset?.scheduledFor.addTimeInterval(3600)
        XCTAssertEqual(CodexResetRadarPresentation.notificationPlans(
            snapshot: snapshot, lastNotifiedWatchSignalID: nil,
            lastNotifiedResetSignalID: resetID,
            lastNotifiedScheduledSignalID: scheduled.signalID, now: now
        ).first?.kind, .scheduled)
        snapshot.scheduledReset?.status = "cancelled"
        XCTAssertNil(snapshot.pendingScheduledReset)
    }

    func testNotifiedWatchDoesNotSuppressNewConfirmedReset() throws {
        let snapshot = try fixtureSnapshot(withActiveWatch: true)
        let plans = CodexResetRadarPresentation.notificationPlans(
            snapshot: snapshot,
            lastNotifiedWatchSignalID: snapshot.activeWatch?.source.url.absoluteString,
            lastNotifiedResetSignalID: nil, lastNotifiedScheduledSignalID: nil
        )
        XCTAssertEqual(plans.map(\.kind), [.confirmed])
        XCTAssertEqual(plans.first?.signalID, snapshot.latestReset?.source.url.absoluteString)
    }

    func testAllNewSignalKindsAreIndependentlyPlanned() throws {
        var snapshot = try scheduledSnapshot()
        snapshot.activeWatch = try fixtureSnapshot(withActiveWatch: true).activeWatch
        let scheduled = try XCTUnwrap(snapshot.pendingScheduledReset)
        let now = scheduled.scheduledFor.addingTimeInterval(-60)
        snapshot.activeWatch?.expiresAt = scheduled.scheduledFor
        let plans = CodexResetRadarPresentation.notificationPlans(
            snapshot: snapshot, lastNotifiedWatchSignalID: nil,
            lastNotifiedResetSignalID: nil, lastNotifiedScheduledSignalID: nil, now: now
        )
        XCTAssertEqual(plans.map(\.kind), [.scheduled, .watch, .confirmed])
        // A confirmed reset can share its source with a previously scheduled one.
        snapshot.latestReset?.source = scheduled.source
        snapshot.latestReset?.announcedAt = scheduled.scheduledFor
        let confirmed = CodexResetRadarPresentation.notificationPlans(
            snapshot: snapshot,
            lastNotifiedWatchSignalID: snapshot.activeWatch?.source.url.absoluteString,
            lastNotifiedResetSignalID: nil,
            lastNotifiedScheduledSignalID: scheduled.signalID, now: scheduled.scheduledFor
        )
        XCTAssertEqual(confirmed.map(\.kind), [.confirmed])
    }

    private func fixtureSnapshot(
        withActiveWatch: Bool
    ) throws -> CodexResetRadarSnapshot {
        let watch = withActiveWatch
            ? #"""
              {
                "level": "strong",
                "reset_chance_percent": 78,
                "forecast_window": "next 24h",
                "observed_at": "2026-04-15T06:00:00.000Z",
                "expires_at": "2026-04-16T06:00:00.000Z",
                "text": "A reset may be coming.",
                "source": {
                  "type": "x_post",
                  "author": "thsottiaux",
                  "url": "https://x.com/thsottiaux/status/2088000000000000000"
                }
              }
              """#
            : "null"
        let json = """
        {
          "data": {
            "latest_reset": {
              "id": "1",
              "announced_at": "2026-04-13T23:00:00.000Z",
              "text": "Usage limits have been reset.",
              "source": {
                "type": "x_post",
                "author": "thsottiaux",
                "url": "https://x.com/thsottiaux/status/1"
              }
            },
            "active_watch": \(watch),
            "stats": {
              "total": 43,
              "last_reset_at": "2026-04-13T23:00:00.000Z",
              "days_since_last": 2.2,
              "avg_interval_days": 7.9
            }
          },
          "meta": {
            "api_version": "v1",
            "generated_at": "2026-04-16T00:00:00.000Z"
          }
        }
        """
        return try CodexResetRadarSnapshot.decode(Data(json.utf8))
    }

    private func makeIsolatedDefaults() throws -> UserDefaults {
        let suiteName = "CodexResetRadarTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
