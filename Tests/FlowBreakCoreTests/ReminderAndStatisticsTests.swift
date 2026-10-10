import XCTest
@testable import FlowBreakCore

final class ReminderPlannerTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    func testFocusPlanHasInitialPlusRepeats() {
        let engine = TimerEngine(store: InMemoryStore(), configuration: TimerConfiguration())
        engine.startFocus(at: t0)
        let plan = ReminderPlanner.plan(state: engine.state, settings: ReminderSettings(), defaultBreakDuration: 300, now: t0, calendar: utc)
        XCTAssertEqual(plan.count, 4)
        XCTAssertEqual(plan.first?.kind, .focusEnded)
        XCTAssertEqual(plan.first?.date, t0.addingTimeInterval(45 * 60))
        XCTAssertEqual(plan.last?.date, t0.addingTimeInterval(45 * 60 + 15 * 60))
        XCTAssertEqual(Set(plan.map(\.id)).count, plan.count, "identifiers are unique")
    }

    func testRepeatCountIsBoundedAt12() {
        let engine = TimerEngine(store: InMemoryStore(), configuration: TimerConfiguration())
        engine.startFocus(at: t0)
        let plan = ReminderPlanner.plan(state: engine.state, settings: ReminderSettings(repeatCount: 500), defaultBreakDuration: 300, now: t0, calendar: utc)
        XCTAssertEqual(plan.count, 13)
    }

    func testPausedOrIdleOrBreakStartedHasNoDueReminders() {
        let engine = TimerEngine(store: InMemoryStore(), configuration: TimerConfiguration())
        XCTAssertTrue(ReminderPlanner.plan(state: engine.state, settings: ReminderSettings(), defaultBreakDuration: 300, now: t0).isEmpty)
        engine.startFocus(at: t0)
        engine.pause(at: t0.addingTimeInterval(60))
        XCTAssertTrue(ReminderPlanner.plan(state: engine.state, settings: ReminderSettings(), defaultBreakDuration: 300, now: t0).isEmpty)
        engine.startBreak(at: t0.addingTimeInterval(120))
        let plan = ReminderPlanner.plan(state: engine.state, settings: ReminderSettings(), defaultBreakDuration: 300, now: t0.addingTimeInterval(120))
        XCTAssertEqual(plan.map(\.kind), [.breakEnded])
    }

    func testBreakDueDropsPastRemindersAndSnoozeReschedules() {
        let engine = TimerEngine(store: InMemoryStore(), configuration: TimerConfiguration())
        engine.startFocus(at: t0)
        let due = t0.addingTimeInterval(45 * 60)
        engine.reconcile(at: due)
        let later = due.addingTimeInterval(6 * 60)
        let plan = ReminderPlanner.plan(state: engine.state, settings: ReminderSettings(), defaultBreakDuration: 300, now: later)
        XCTAssertEqual(plan.map(\.date), [due.addingTimeInterval(600), due.addingTimeInterval(900)])

        engine.snooze(for: 300, at: later)
        let snoozed = ReminderPlanner.plan(state: engine.state, settings: ReminderSettings(), defaultBreakDuration: 300, now: later)
        XCTAssertEqual(snoozed.first?.date, later.addingTimeInterval(300))
        XCTAssertEqual(snoozed.count, 4)
    }

    func testDisabledRemindersPlanNothing() {
        let engine = TimerEngine(store: InMemoryStore(), configuration: TimerConfiguration())
        engine.startFocus(at: t0)
        XCTAssertTrue(ReminderPlanner.plan(state: engine.state, settings: ReminderSettings(enabled: false), defaultBreakDuration: 300, now: t0).isEmpty)
    }

    func testQuietHoursWrapMidnight() {
        let quiet = QuietHours(startMinute: 22 * 60, endMinute: 7 * 60)
        let day = utc.startOfDay(for: t0)
        XCTAssertTrue(quiet.contains(day.addingTimeInterval(23 * 3600), calendar: utc))
        XCTAssertTrue(quiet.contains(day.addingTimeInterval(3 * 3600), calendar: utc))
        XCTAssertFalse(quiet.contains(day.addingTimeInterval(12 * 3600), calendar: utc))
    }
}

final class StatisticsTests: XCTestCase {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
    }

    func completed(_ kind: SessionKind, from start: Date, minutes: Double, follows: UUID? = nil) -> FocusSession {
        var s = FocusSession(kind: kind, start: start, plannedDuration: minutes * 60, followsFocusID: follows)
        let end = start.addingTimeInterval(minutes * 60)
        s.status = .completed
        s.deadline = nil
        s.segments = [ActiveSegment(start: start, end: end)]
        s.endedAt = end
        s.actualDuration = minutes * 60
        return s
    }

    func testEmptyHistoryShowsZeroNotFabricatedData() {
        let summary = StatisticsCalculator(calendar: calendar).summary(sessions: [], range: .today, now: date(10, 12))
        XCTAssertEqual(summary.focusTime, 0)
        XCTAssertNil(summary.adherence)
        XCTAssertNil(summary.longestFocus)
        XCTAssertTrue(summary.isEmpty)
        XCTAssertEqual(summary.daily.count, 1)
    }

    func testMidnightCrossingIsSplitBetweenDays() {
        let focus = completed(.focus, from: date(9, 23, 30), minutes: 60)
        let calc = StatisticsCalculator(calendar: calendar)
        let today = calc.summary(sessions: [focus], range: .today, now: date(10, 9))
        XCTAssertEqual(today.focusTime, 30 * 60, accuracy: 0.001)
        let week = calc.summary(sessions: [focus], range: .last7Days, now: date(10, 9))
        XCTAssertEqual(week.focusTime, 60 * 60, accuracy: 0.001)
        XCTAssertEqual(week.daily.count, 7)
        XCTAssertEqual(week.daily[5].focusTime, 30 * 60, accuracy: 0.001)
        XCTAssertEqual(week.daily[6].focusTime, 30 * 60, accuracy: 0.001)
    }

    func testPausesAreExcludedFromFocusTime() {
        var focus = completed(.focus, from: date(10, 9), minutes: 45)
        focus.segments = [
            ActiveSegment(start: date(10, 9), end: date(10, 9, 20)),
            ActiveSegment(start: date(10, 10), end: date(10, 10, 25)),
        ]
        let s = StatisticsCalculator(calendar: calendar).summary(sessions: [focus], range: .today, now: date(10, 12))
        XCTAssertEqual(s.focusTime, 45 * 60, accuracy: 0.001)
    }

    func testAdherenceAndBreakCounts() {
        let f1 = completed(.focus, from: date(10, 9), minutes: 45)
        let b1 = completed(.shortBreak, from: date(10, 9, 46), minutes: 5, follows: f1.id)
        let f2 = completed(.focus, from: date(10, 10), minutes: 45)
        var cancelled = completed(.focus, from: date(10, 11), minutes: 10)
        cancelled.status = .cancelled
        let s = StatisticsCalculator(calendar: calendar).summary(sessions: [f1, b1, f2, cancelled], range: .today, now: date(10, 12))
        XCTAssertEqual(s.focusSessionsCompleted, 2)
        XCTAssertEqual(s.breaksTaken, 1)
        XCTAssertEqual(s.adherenceNumerator, 1)
        XCTAssertEqual(s.adherenceDenominator, 2)
        XCTAssertEqual(s.adherence ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(s.longestFocus, 45 * 60)
        XCTAssertEqual(s.focusTime, 100 * 60, accuracy: 0.001, "cancelled sessions still count their active time")
        XCTAssertEqual(s.timeline.count, 4)
    }

    func testRunningSessionCountsUpToNow() {
        let focus = FocusSession(kind: .focus, start: date(10, 9), plannedDuration: 45 * 60)
        let s = StatisticsCalculator(calendar: calendar).summary(sessions: [focus], range: .today, now: date(10, 9, 15))
        XCTAssertEqual(s.focusTime, 15 * 60, accuracy: 0.001)
    }

    func testPomodoroCyclesCountLongBreaks() {
        let lb = completed(.longBreak, from: date(10, 12), minutes: 15)
        let s = StatisticsCalculator(calendar: calendar).summary(sessions: [lb], range: .today, now: date(10, 13))
        XCTAssertEqual(s.pomodoroCycles, 1)
    }
}
