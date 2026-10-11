import XCTest
@testable import FlowBreakCore

final class UpdateTests: XCTestCase {
    func manifest(_ version: String, _ build: Int, minimum: String? = nil) -> UpdateManifest {
        UpdateManifest(version: version, build: build, dmgURL: URL(string: "https://example.com/FlowBreak.dmg")!, minimumSystemVersion: minimum)
    }

    func testVersionComparison() {
        XCTAssertEqual(UpdateComparison.compareVersions("1.10.0", "1.9.2"), .orderedDescending)
        XCTAssertEqual(UpdateComparison.compareVersions("1.2", "1.2.0"), .orderedSame)
        XCTAssertEqual(UpdateComparison.compareVersions("1.2.0", "1.2.1"), .orderedAscending)
        XCTAssertEqual(UpdateComparison.compareVersions("2.0-beta", "1.9"), .orderedDescending)
    }

    func testIsNewerUsesVersionThenBuild() {
        XCTAssertTrue(UpdateComparison.isNewer(manifest("1.2.0", 5), thanVersion: "1.1.0", build: 40))
        XCTAssertFalse(UpdateComparison.isNewer(manifest("1.1.0", 50), thanVersion: "1.2.0", build: 1))
        XCTAssertTrue(UpdateComparison.isNewer(manifest("1.2.0", 12), thanVersion: "1.2.0", build: 11))
        XCTAssertFalse(UpdateComparison.isNewer(manifest("1.2.0", 11), thanVersion: "1.2.0", build: 11))
    }

    func testMinimumSystemVersion() {
        let m = manifest("1.2.0", 1, minimum: "14.0")
        XCTAssertFalse(UpdateComparison.isSupported(m, systemVersion: OperatingSystemVersion(majorVersion: 13, minorVersion: 6, patchVersion: 0)))
        XCTAssertTrue(UpdateComparison.isSupported(m, systemVersion: OperatingSystemVersion(majorVersion: 15, minorVersion: 1, patchVersion: 0)))
    }

    func testManifestDecodesCIOutput() throws {
        let json = Data("""
        {"version":"1.2.0","build":42,"dmgURL":"https://github.com/o/r/releases/download/latest-build/FlowBreak-unsigned.dmg",
         "sha256":"abc","publishedAt":"2026-10-11T10:00:00Z","minimumSystemVersion":"13.0","notarized":false}
        """.utf8)
        let m = try UpdateManifest.decode(json)
        XCTAssertEqual(m.build, 42)
        XCTAssertEqual(m.notarized, false)
        XCTAssertNotNil(m.publishedAt)
    }
}

final class CalendarPlanningTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    func block(_ startMin: Double, _ endMin: Double, _ title: String = "Meeting") -> BusyBlock {
        BusyBlock(title: title, interval: DateInterval(start: t0.addingTimeInterval(startMin * 60), end: t0.addingTimeInterval(endMin * 60)))
    }

    func testMergeCurrentNext() {
        let blocks = [block(30, 60, "Standup"), block(50, 90, "Review"), block(120, 150, "1:1")]
        XCTAssertEqual(CalendarPlanning.merged(blocks.map(\.interval)).count, 2)
        XCTAssertNil(CalendarPlanning.current(blocks, at: t0))
        XCTAssertEqual(CalendarPlanning.next(blocks, after: t0)?.title, "Standup")
        XCTAssertEqual(CalendarPlanning.current(blocks, at: t0.addingTimeInterval(55 * 60))?.title, "Standup", "the one ending first")
    }

    func testFreeMinutesSubtractsMergedMeetings() {
        let blocks = [block(30, 60), block(50, 90), block(200, 260)]
        XCTAssertEqual(CalendarPlanning.freeMinutes(blocks, from: t0, until: t0.addingTimeInterval(240 * 60)), 240 - 60 - 40)
        XCTAssertEqual(CalendarPlanning.freeMinutes(blocks, from: t0, until: t0.addingTimeInterval(-60)), 0)
    }

    func testFirstConflict() {
        let blocks = [block(50, 60, "Standup"), block(100, 130, "Review")]
        XCTAssertEqual(CalendarPlanning.firstConflict(blocks, start: t0, duration: 45 * 60)?.title, nil)
        XCTAssertEqual(CalendarPlanning.firstConflict(blocks, start: t0.addingTimeInterval(20 * 60), duration: 45 * 60)?.title, "Standup")
    }

    func testRemindersAreHeldUntilMeetingEnds() {
        let engine = TimerEngine(store: InMemoryStore(), configuration: TimerConfiguration())
        engine.startFocus(at: t0)
        // Focus ends at +45; a meeting runs +40...+55; repeats at +50, +55, +60.
        let meeting = DateInterval(start: t0.addingTimeInterval(40 * 60), end: t0.addingTimeInterval(55 * 60))
        let plan = ReminderPlanner.plan(state: engine.state, settings: ReminderSettings(), defaultBreakDuration: 300, now: t0, busy: [meeting])
        let offsets = plan.map { Int($0.date.timeIntervalSince(t0) / 60) }
        XCTAssertEqual(offsets, [55, 60], "held reminders move to the meeting end; nothing fires during it")
        XCTAssertEqual(plan.first?.kind, .focusEnded)
        XCTAssertTrue(plan.first?.id.hasSuffix(".aftermeeting") ?? false)
        XCTAssertEqual(Set(plan.map(\.id)).count, plan.count)
    }

    func testNoMeetingsLeavesPlanUnchanged() {
        let engine = TimerEngine(store: InMemoryStore(), configuration: TimerConfiguration())
        engine.startFocus(at: t0)
        let a = ReminderPlanner.plan(state: engine.state, settings: ReminderSettings(), defaultBreakDuration: 300, now: t0)
        let b = ReminderPlanner.plan(state: engine.state, settings: ReminderSettings(), defaultBreakDuration: 300, now: t0, busy: [])
        XCTAssertEqual(a, b)
    }
}

final class NudgeTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let policy = NudgePolicy(enabled: true, distractingBundleIDs: ["com.tinyspeck.slackmacgap"], cooldown: 300)

    func testNudgesOnlyDuringRunningFocusForListedApps() {
        let engine = TimerEngine(store: InMemoryStore(), configuration: TimerConfiguration())
        let tracker = NudgeTracker()
        XCTAssertFalse(tracker.shouldNudge(bundleID: "com.tinyspeck.slackmacgap", state: engine.state, policy: policy, now: t0), "idle: never")
        engine.startFocus(at: t0)
        XCTAssertTrue(tracker.shouldNudge(bundleID: "com.tinyspeck.slackmacgap", state: engine.state, policy: policy, now: t0))
        XCTAssertFalse(tracker.shouldNudge(bundleID: "com.apple.dt.Xcode", state: engine.state, policy: policy, now: t0), "unlisted apps never")
        var off = policy
        off.enabled = false
        XCTAssertFalse(tracker.shouldNudge(bundleID: "com.tinyspeck.slackmacgap", state: engine.state, policy: off, now: t0), "off by setting")
        engine.pause(at: t0.addingTimeInterval(60))
        XCTAssertFalse(tracker.shouldNudge(bundleID: "com.tinyspeck.slackmacgap", state: engine.state, policy: policy, now: t0.addingTimeInterval(61)), "paused: never")
    }

    func testCooldownAllowForSessionAndResetOnNewSession() {
        let engine = TimerEngine(store: InMemoryStore(), configuration: TimerConfiguration())
        let tracker = NudgeTracker()
        let app = "com.tinyspeck.slackmacgap"
        engine.startFocus(at: t0)
        XCTAssertTrue(tracker.shouldNudge(bundleID: app, state: engine.state, policy: policy, now: t0))
        tracker.recordNudge(bundleID: app, now: t0)
        engine.recordNudge(at: t0)
        XCTAssertFalse(tracker.shouldNudge(bundleID: app, state: engine.state, policy: policy, now: t0.addingTimeInterval(120)))
        XCTAssertTrue(tracker.shouldNudge(bundleID: app, state: engine.state, policy: policy, now: t0.addingTimeInterval(301)))
        tracker.allowForSession(bundleID: app)
        XCTAssertFalse(tracker.shouldNudge(bundleID: app, state: engine.state, policy: policy, now: t0.addingTimeInterval(900)))
        XCTAssertEqual(engine.current?.nudges, 1)

        engine.stop(at: t0.addingTimeInterval(1000))
        engine.startFocus(at: t0.addingTimeInterval(1100))
        XCTAssertTrue(tracker.shouldNudge(bundleID: app, state: engine.state, policy: policy, now: t0.addingTimeInterval(1101)), "allowance resets with a new session")
        XCTAssertEqual(engine.sessions.first?.nudges, 1, "the count is kept on the finished session")
    }

    func testNewSettingsDefaultOff() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertFalse(settings.nudgesEnabled)
        XCTAssertFalse(settings.calendarAwareness)
        XCTAssertFalse(settings.checkForUpdatesAutomatically)
        XCTAssertTrue(settings.holdRemindersDuringMeetings)
    }
}
