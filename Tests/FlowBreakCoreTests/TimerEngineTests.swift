import XCTest
@testable import FlowBreakCore

final class TimerEngineTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let minute: TimeInterval = 60

    func makeEngine(_ config: TimerConfiguration = TimerConfiguration(), store: InMemoryStore = InMemoryStore()) -> (TimerEngine, InMemoryStore) {
        (TimerEngine(store: store, configuration: config), store)
    }

    // MARK: Start / pause / resume / stop

    func testStartFocusUsesConfiguredDurationAndDeadline() {
        let (engine, store) = makeEngine()
        let events = engine.startFocus(at: t0)
        XCTAssertEqual(engine.phase, .focusing)
        XCTAssertEqual(engine.current?.deadline, t0.addingTimeInterval(45 * minute))
        XCTAssertEqual(engine.remaining(at: t0.addingTimeInterval(10)), 45 * minute - 10, accuracy: 0.001)
        XCTAssertEqual(store.state?.phase, .focusing, "state is persisted before events are returned")
        XCTAssertEqual(store.sessions.count, 1)
        guard case .focusStarted? = events.last else { return XCTFail("expected focusStarted") }
    }

    func testStartFocusWhileRunningIsNoOp() {
        let (engine, _) = makeEngine()
        engine.startFocus(at: t0)
        let id = engine.current?.id
        let events = engine.startFocus(at: t0.addingTimeInterval(5))
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(engine.current?.id, id)
        XCTAssertEqual(engine.sessions.count, 1)
    }

    func testPauseCapturesExactRemainingAndResumeSetsNewDeadline() {
        let (engine, _) = makeEngine()
        engine.startFocus(at: t0)
        engine.pause(at: t0.addingTimeInterval(10 * minute))
        XCTAssertEqual(engine.current?.status, .paused)
        XCTAssertEqual(engine.current?.remainingAtPause, 35 * minute)
        // Time passing while paused does not change remaining.
        XCTAssertEqual(engine.remaining(at: t0.addingTimeInterval(3 * 3600)), 35 * minute)
        XCTAssertTrue(engine.reconcile(at: t0.addingTimeInterval(3 * 3600)).isEmpty)

        let resumeAt = t0.addingTimeInterval(20 * minute)
        engine.resume(at: resumeAt)
        XCTAssertEqual(engine.current?.status, .running)
        XCTAssertEqual(engine.current?.deadline, resumeAt.addingTimeInterval(35 * minute))
        XCTAssertEqual(engine.current?.accumulatedPause, 10 * minute)
        XCTAssertEqual(engine.current?.segments.count, 2)
    }

    func testStopCancelsFocusAndKeepsActiveTime() {
        let (engine, _) = makeEngine()
        engine.startFocus(at: t0)
        engine.stop(at: t0.addingTimeInterval(12 * minute))
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertNil(engine.current)
        XCTAssertEqual(engine.sessions.first?.status, .cancelled)
        XCTAssertEqual(engine.sessions.first?.actualDuration, 12 * minute)
    }

    // MARK: Expiration

    func testFocusExpiresExactlyOnce() {
        let (engine, _) = makeEngine()
        engine.startFocus(at: t0)
        XCTAssertTrue(engine.reconcile(at: t0.addingTimeInterval(45 * minute - 1)).isEmpty)
        let first = engine.reconcile(at: t0.addingTimeInterval(45 * minute))
        XCTAssertEqual(first.count, 1)
        guard case let .focusCompleted(session, late) = first[0] else { return XCTFail() }
        XCTAssertFalse(late)
        XCTAssertEqual(session.status, .completed)
        XCTAssertEqual(session.actualDuration, 45 * minute)
        XCTAssertEqual(engine.phase, .breakDue)
        // Further ticks do nothing: no duplicate completion, no duplicate count.
        for offset in 1...10 {
            XCTAssertTrue(engine.reconcile(at: t0.addingTimeInterval(45 * minute + Double(offset))).isEmpty)
        }
        XCTAssertEqual(engine.sessions.filter { $0.status == .completed }.count, 1)
    }

    func testCompletionUsesDeadlineNotWakeTime() {
        let (engine, _) = makeEngine()
        engine.startFocus(at: t0)
        // Mac slept for two hours past the deadline.
        let events = engine.reconcile(at: t0.addingTimeInterval(45 * minute + 2 * 3600))
        guard case let .focusCompleted(session, late)? = events.first else { return XCTFail() }
        XCTAssertTrue(late)
        XCTAssertEqual(session.endedAt, t0.addingTimeInterval(45 * minute))
        XCTAssertEqual(session.actualDuration, 45 * minute)
        XCTAssertEqual(engine.state.breakDue?.since, t0.addingTimeInterval(45 * minute))
        XCTAssertEqual(engine.state.breakDue?.detectedLate, true)
    }

    func testResumeWithZeroRemainingCompletesImmediately() {
        let (engine, _) = makeEngine(TimerConfiguration(focusDuration: 60))
        engine.startFocus(at: t0)
        engine.pause(at: t0.addingTimeInterval(60))  // reconcile completes first
        XCTAssertEqual(engine.phase, .breakDue)
    }

    // MARK: Breaks

    func testBreakFromDueUsesSuggestionAndLinksFocus() {
        let (engine, _) = makeEngine()
        engine.startFocus(at: t0)
        engine.reconcile(at: t0.addingTimeInterval(45 * minute))
        let focusID = engine.state.breakDue?.focusSessionID
        engine.startBreak(at: t0.addingTimeInterval(46 * minute))
        XCTAssertEqual(engine.phase, .onBreak)
        XCTAssertEqual(engine.current?.kind, .shortBreak)
        XCTAssertEqual(engine.current?.plannedDuration, 5 * minute)
        XCTAssertEqual(engine.current?.followsFocusID, focusID)
        engine.reconcile(at: t0.addingTimeInterval(51 * minute))
        XCTAssertEqual(engine.phase, .breakComplete)
        XCTAssertEqual(engine.state.lastBreak?.status, .completed)
    }

    func testBreakDuringFocusEndsFocusEarly() {
        let (engine, _) = makeEngine()
        engine.startFocus(at: t0)
        engine.startBreak(at: t0.addingTimeInterval(20 * minute))
        let focus = engine.sessions.first { $0.kind.isFocus }
        XCTAssertEqual(focus?.status, .endedEarly)
        XCTAssertEqual(focus?.actualDuration, 20 * minute)
        XCTAssertEqual(engine.phase, .onBreak)
    }

    func testExtendBreakAndReturnToFocusEarly() {
        let (engine, _) = makeEngine()
        engine.startBreak(at: t0)
        engine.extendBreak(by: 5 * minute, at: t0.addingTimeInterval(60))
        XCTAssertEqual(engine.current?.deadline, t0.addingTimeInterval(10 * minute))
        XCTAssertEqual(engine.current?.plannedDuration, 10 * minute)
        engine.startFocus(at: t0.addingTimeInterval(3 * minute))
        XCTAssertEqual(engine.phase, .focusing)
        let breakSession = engine.sessions.first { $0.kind.isBreak }
        XCTAssertEqual(breakSession?.status, .endedEarly)
    }

    func testSnoozeKeepsBreakDueAndSkipReturnsToIdle() {
        let (engine, _) = makeEngine()
        engine.startFocus(at: t0)
        engine.reconcile(at: t0.addingTimeInterval(45 * minute))
        engine.snooze(for: 5 * minute, at: t0.addingTimeInterval(46 * minute))
        XCTAssertEqual(engine.phase, .breakDue)
        XCTAssertEqual(engine.state.breakDue?.snoozedUntil, t0.addingTimeInterval(51 * minute))
        engine.skipBreak(at: t0.addingTimeInterval(47 * minute))
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertNil(engine.state.breakDue)
    }

    func testStartFocusWhileBreakDueSkipsBreak() {
        let (engine, _) = makeEngine()
        engine.startFocus(at: t0)
        engine.reconcile(at: t0.addingTimeInterval(45 * minute))
        let events = engine.startFocus(at: t0.addingTimeInterval(46 * minute))
        XCTAssertTrue(events.contains { if case .breakSkipped = $0 { return true } else { return false } })
        XCTAssertEqual(engine.phase, .focusing)
    }

    // MARK: Pomodoro

    func testPomodoroLongBreakEveryFourWorkSessions() {
        let config = TimerConfiguration(mode: .pomodoro, focusDuration: 25 * minute, shortBreakDuration: 5 * minute, longBreakDuration: 15 * minute, longBreakEvery: 4)
        let (engine, _) = makeEngine(config)
        var now = t0
        var suggestions: [SessionKind] = []
        for _ in 0..<5 {
            engine.startFocus(at: now)
            now = now.addingTimeInterval(25 * minute)
            engine.reconcile(at: now)
            guard let due = engine.state.breakDue else { return XCTFail("expected break due") }
            suggestions.append(due.suggestedKind)
            engine.startBreak(at: now)
            now = now.addingTimeInterval(due.suggestedDuration)
            engine.reconcile(at: now)
        }
        XCTAssertEqual(suggestions, [.shortBreak, .shortBreak, .shortBreak, .longBreak, .shortBreak])
        XCTAssertEqual(engine.sessions.filter { $0.kind == .longBreak }.first?.plannedDuration, 15 * minute)
        XCTAssertEqual(engine.state.completedWorkSessionsInCycle, 1)
    }

    func testAutoCycleStartsBreakAndFocusWhenOnTime() {
        let config = TimerConfiguration(focusDuration: 10 * minute, shortBreakDuration: 2 * minute, autoStartBreaks: true, autoStartFocus: true)
        let (engine, _) = makeEngine(config)
        engine.startFocus(at: t0)
        engine.reconcile(at: t0.addingTimeInterval(10 * minute + 1))
        XCTAssertEqual(engine.phase, .onBreak)
        XCTAssertEqual(engine.current?.startedAt, t0.addingTimeInterval(10 * minute))
        engine.reconcile(at: t0.addingTimeInterval(12 * minute + 1))
        XCTAssertEqual(engine.phase, .focusing)
    }

    func testAutoCycleDoesNotFabricateSessionsAfterSleep() {
        let config = TimerConfiguration(focusDuration: 10 * minute, shortBreakDuration: 2 * minute, autoStartBreaks: true, autoStartFocus: true)
        let (engine, _) = makeEngine(config)
        engine.startFocus(at: t0)
        engine.reconcile(at: t0.addingTimeInterval(5 * 3600))
        XCTAssertEqual(engine.phase, .breakDue)
        XCTAssertEqual(engine.sessions.count, 1)
    }

    // MARK: Relaunch

    func testRelaunchWithRunningSessionRestoresDeadline() {
        let store = InMemoryStore()
        let (engine, _) = makeEngine(store: store)
        engine.startFocus(at: t0)
        let relaunched = TimerEngine(store: store, configuration: TimerConfiguration())
        XCTAssertEqual(relaunched.phase, .focusing)
        XCTAssertEqual(relaunched.remaining(at: t0.addingTimeInterval(15 * minute)), 30 * minute, accuracy: 0.001)
    }

    func testRelaunchWithPausedSession() {
        let store = InMemoryStore()
        let (engine, _) = makeEngine(store: store)
        engine.startFocus(at: t0)
        engine.pause(at: t0.addingTimeInterval(5 * minute))
        let relaunched = TimerEngine(store: store, configuration: TimerConfiguration())
        XCTAssertEqual(relaunched.current?.status, .paused)
        XCTAssertEqual(relaunched.remaining(at: t0.addingTimeInterval(10 * 3600)), 40 * minute)
    }

    func testRelaunchWithExpiredSessionCompletesOnce() {
        let store = InMemoryStore()
        let (engine, _) = makeEngine(store: store)
        engine.startFocus(at: t0)
        let relaunched = TimerEngine(store: store, configuration: TimerConfiguration())
        let events = relaunched.reconcile(at: t0.addingTimeInterval(3 * 3600))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(relaunched.phase, .breakDue)
        // A second relaunch must not complete it again.
        let again = TimerEngine(store: store, configuration: TimerConfiguration())
        XCTAssertTrue(again.reconcile(at: t0.addingTimeInterval(4 * 3600)).isEmpty)
        XCTAssertEqual(again.sessions.filter { $0.status == .completed }.count, 1)
    }

    func testRelaunchRepairsInconsistentState() {
        var orphan = FocusSession(kind: .focus, start: t0, plannedDuration: 600)
        orphan.status = .running
        let store = InMemoryStore(state: EngineState(phase: .idle), sessions: [orphan])
        let engine = TimerEngine(store: store, configuration: TimerConfiguration())
        XCTAssertEqual(engine.sessions.first?.status, .interrupted)
        XCTAssertEqual(engine.phase, .idle)
    }

    // MARK: Clock changes & persistence errors

    func testClockMovingBackwardsPreservesRemaining() {
        let (engine, _) = makeEngine()
        engine.startFocus(at: t0)
        engine.reconcile(at: t0.addingTimeInterval(10 * minute))
        // Clock is set back one hour.
        let back = t0.addingTimeInterval(10 * minute - 3600)
        let events = engine.reconcile(at: back)
        XCTAssertTrue(events.contains(.clockAdjusted(by: -3600)))
        XCTAssertEqual(engine.remaining(at: back), 35 * minute, accuracy: 0.001)
    }

    func testRemainingNeverExceedsSegmentLengthWithoutReconcile() {
        var s = FocusSession(kind: .focus, start: t0, plannedDuration: 600)
        s.status = .running
        XCTAssertEqual(s.remaining(at: t0.addingTimeInterval(-3600)), 600)
    }

    func testPersistenceFailureIsSurfacedNotFatal() {
        let store = InMemoryStore()
        store.failWrites = true
        let (engine, _) = makeEngine(store: store)
        engine.startFocus(at: t0)
        XCTAssertEqual(engine.phase, .focusing)
        XCTAssertNotNil(engine.lastPersistenceError)
        store.failWrites = false
        engine.pause(at: t0.addingTimeInterval(60))
        XCTAssertNil(engine.lastPersistenceError)
    }

    func testClearHistoryKeepsActiveSession() {
        let (engine, _) = makeEngine()
        engine.startFocus(at: t0)
        engine.stop(at: t0.addingTimeInterval(60))
        engine.startFocus(at: t0.addingTimeInterval(120))
        engine.clearHistory()
        XCTAssertEqual(engine.sessions.count, 1)
        XCTAssertEqual(engine.sessions.first?.id, engine.current?.id)
    }
}
