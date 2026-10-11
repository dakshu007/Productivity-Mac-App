import Foundation

/// The one place where timer state changes.
///
/// Design rules:
/// - Absolute `Date` deadlines are the source of truth. Callers pass `now`
///   explicitly, so tests never wait for real time.
/// - Every public operation first reconciles against `now`, so an expired session
///   always completes (exactly once) before anything else happens.
/// - State and history are persisted *before* the operation returns its events.
///
/// Documented behaviours:
/// - Starting a break while focusing ends that focus session as `endedEarly`
///   (its active time still counts toward focus time, it is not a completed session).
/// - Starting focus during a break ends the break as `endedEarly`.
/// - Starting focus while a break is due skips the break.
/// - Stopping cancels focus (`cancelled`) or ends a break (`endedEarly`).
/// - A focus session that expired while the Mac slept completes at its deadline,
///   not at wake time. Automatic cycles never chain through time the user was away.
/// - If the wall clock moves backwards while a session runs, the deadline moves
///   back by the same amount so remaining time is preserved. Forward jumps cannot be
///   told apart from sleep and are treated as elapsed time.
public final class TimerEngine {
    /// A completion noticed more than this long after its deadline counts as "late".
    public static let lateThreshold: TimeInterval = 15

    public private(set) var state: EngineState
    public private(set) var sessions: [FocusSession]
    public var configuration: TimerConfiguration
    /// The last persistence failure, surfaced in the UI. Cleared after a successful save.
    public private(set) var lastPersistenceError: String?

    private let store: SessionPersisting
    private var lastObservedNow: Date?

    public init(store: SessionPersisting, configuration: TimerConfiguration) {
        self.store = store
        self.configuration = configuration
        var loadError: String?
        var loadedState: EngineState = .idle
        var loadedSessions: [FocusSession] = []
        do {
            loadedSessions = try store.loadSessions()
        } catch {
            loadError = error.localizedDescription
        }
        do {
            loadedState = try store.loadState() ?? .idle
        } catch {
            loadError = error.localizedDescription
        }
        self.sessions = loadedSessions
        self.state = loadedState
        self.lastPersistenceError = loadError
        repairLoadedState()
    }

    // MARK: - Queries

    public var phase: EnginePhase { state.phase }
    public var current: FocusSession? { state.current }

    public func remaining(at now: Date) -> TimeInterval {
        switch state.phase {
        case .focusing, .onBreak:
            return state.current?.remaining(at: now) ?? 0
        case .breakDue:
            return state.breakDue?.suggestedDuration ?? configuration.shortBreakDuration
        case .idle, .breakComplete:
            return configuration.focusDuration
        }
    }

    public func session(id: UUID) -> FocusSession? {
        sessions.first { $0.id == id }
    }

    // MARK: - Reconciliation

    /// Brings state up to date with `now`: completes expired sessions exactly once
    /// and compensates for the clock moving backwards. Safe to call every second.
    @discardableResult
    public func reconcile(at now: Date) -> [EngineEvent] {
        var events: [EngineEvent] = []
        var changed = false

        if let previous = lastObservedNow, now < previous.addingTimeInterval(-2) {
            let delta = previous.timeIntervalSince(now)
            if var session = state.current, session.status == .running, let deadline = session.deadline {
                session.deadline = deadline.addingTimeInterval(-delta)
                if var last = session.segments.popLast() {
                    last.start = last.start.addingTimeInterval(-delta)
                    session.segments.append(last)
                }
                state.current = session
                upsert(session)
                changed = true
                events.append(.clockAdjusted(by: -delta))
            }
        }
        lastObservedNow = now

        // At most a handful of transitions can chain (focus -> auto break -> auto focus).
        for _ in 0..<4 {
            guard let session = state.current, session.status == .running,
                  let deadline = session.deadline, deadline <= now else { break }
            let late = now.timeIntervalSince(deadline) > TimerEngine.lateThreshold
            if session.kind.isFocus {
                events.append(contentsOf: completeFocus(session, at: deadline, late: late))
            } else {
                events.append(contentsOf: completeBreak(session, at: deadline, late: late))
            }
            changed = true
        }

        if changed { persist() }
        return events
    }

    // MARK: - Focus

    @discardableResult
    public func startFocus(at now: Date, duration: TimeInterval? = nil, taskID: UUID? = nil, intent: String? = nil) -> [EngineEvent] {
        var events = reconcile(at: now)
        switch state.phase {
        case .focusing:
            if state.current?.status == .paused {
                events.append(contentsOf: resume(at: now))
            }
            return events
        case .onBreak:
            if let breakSession = state.current {
                events.append(endEarly(breakSession, at: now))
            }
        case .breakDue:
            if let due = state.breakDue {
                if due.suggestedKind == .longBreak { state.completedWorkSessionsInCycle = 0 }
                events.append(.breakSkipped(due))
            }
        case .idle, .breakComplete:
            break
        }
        events.append(beginFocus(at: now, duration: duration ?? configuration.focusDuration, taskID: taskID, intent: intent))
        persist()
        return events
    }

    @discardableResult
    public func pause(at now: Date) -> [EngineEvent] {
        var events = reconcile(at: now)
        guard var session = state.current, session.status == .running else { return events }
        session.remainingAtPause = session.remaining(at: now)
        session.deadline = nil
        session.status = .paused
        if var last = session.segments.popLast() {
            last.end = now
            session.segments.append(last)
        }
        state.current = session
        upsert(session)
        persist()
        events.append(.paused(session))
        return events
    }

    @discardableResult
    public func resume(at now: Date) -> [EngineEvent] {
        var events = reconcile(at: now)
        guard var session = state.current, session.status == .paused else { return events }
        let remaining = max(0, session.remainingAtPause ?? 0)
        session.remainingAtPause = nil
        session.deadline = now.addingTimeInterval(remaining)
        session.status = .running
        session.segments.append(ActiveSegment(start: now))
        state.current = session
        upsert(session)
        persist()
        events.append(.resumed(session))
        // A session resumed with nothing left completes immediately.
        events.append(contentsOf: reconcile(at: now))
        return events
    }

    /// Stops whatever is happening and returns to idle.
    @discardableResult
    public func stop(at now: Date) -> [EngineEvent] {
        var events = reconcile(at: now)
        switch state.phase {
        case .focusing:
            if var session = state.current {
                close(&session, status: .cancelled, at: now)
                upsert(session)
                if session.taskID != nil && (session.actualDuration ?? 0) >= 60 {
                    state.pendingCheckIn = session.id
                }
                events.append(.sessionCancelled(session))
            }
        case .onBreak:
            if let session = state.current {
                events.append(endEarly(session, at: now))
            }
        case .breakDue:
            if let due = state.breakDue {
                if due.suggestedKind == .longBreak { state.completedWorkSessionsInCycle = 0 }
                events.append(.breakSkipped(due))
            }
        case .idle, .breakComplete:
            break
        }
        state.phase = .idle
        state.current = nil
        state.breakDue = nil
        state.lastBreak = nil
        persist()
        return events
    }

    // MARK: - Breaks

    @discardableResult
    public func startBreak(at now: Date, kind requestedKind: SessionKind? = nil) -> [EngineEvent] {
        var events = reconcile(at: now)
        var follows: UUID?
        var kind: SessionKind = requestedKind ?? .shortBreak
        var duration: TimeInterval?

        switch state.phase {
        case .onBreak:
            return events
        case .focusing:
            if let focus = state.current {
                events.append(endEarly(focus, at: now))
                follows = focus.id
            }
        case .breakDue:
            if let due = state.breakDue {
                follows = due.focusSessionID
                if requestedKind == nil {
                    kind = due.suggestedKind
                    duration = due.suggestedDuration
                }
            }
        case .idle, .breakComplete:
            break
        }
        if !kind.isBreak { kind = .shortBreak }
        let length = duration ?? (kind == .longBreak ? configuration.longBreakDuration : configuration.shortBreakDuration)
        if kind == .longBreak { state.completedWorkSessionsInCycle = 0 }

        let session = FocusSession(kind: kind, start: now, plannedDuration: length, followsFocusID: follows)
        state.phase = .onBreak
        state.current = session
        state.breakDue = nil
        state.lastBreak = nil
        upsert(session)
        persist()
        events.append(.breakStarted(session))
        return events
    }

    @discardableResult
    public func extendBreak(by extra: TimeInterval, at now: Date) -> [EngineEvent] {
        var events = reconcile(at: now)
        guard state.phase == .onBreak, var session = state.current, extra > 0 else { return events }
        session.plannedDuration += extra
        if session.status == .running, let deadline = session.deadline {
            session.deadline = deadline.addingTimeInterval(extra)
        } else if session.status == .paused {
            session.remainingAtPause = (session.remainingAtPause ?? 0) + extra
        }
        state.current = session
        upsert(session)
        persist()
        events.append(.breakExtended(session))
        return events
    }

    /// Postpones the break reminder. The break stays due.
    @discardableResult
    public func snooze(for interval: TimeInterval, at now: Date) -> [EngineEvent] {
        var events = reconcile(at: now)
        guard state.phase == .breakDue, var due = state.breakDue else { return events }
        let until = now.addingTimeInterval(max(60, interval))
        due.snoozedUntil = until
        state.breakDue = due
        persist()
        events.append(.snoozed(until: until))
        return events
    }

    /// Declines the due break and returns to idle.
    @discardableResult
    public func skipBreak(at now: Date) -> [EngineEvent] {
        var events = reconcile(at: now)
        guard state.phase == .breakDue, let due = state.breakDue else { return events }
        if due.suggestedKind == .longBreak { state.completedWorkSessionsInCycle = 0 }
        state.phase = .idle
        state.breakDue = nil
        persist()
        events.append(.breakSkipped(due))
        return events
    }

    /// Acknowledges a finished break without starting focus.
    public func dismissBreakComplete(at now: Date) {
        reconcile(at: now)
        guard state.phase == .breakComplete else { return }
        state.phase = .idle
        state.lastBreak = nil
        persist()
    }

    // MARK: - Tasks

    /// Records how a task-linked focus session went. Never changes the task itself.
    @discardableResult
    public func recordOutcome(sessionID: UUID, outcome: SessionOutcome, note: String?, at now: Date) -> [EngineEvent] {
        var events = reconcile(at: now)
        guard let index = sessions.lastIndex(where: { $0.id == sessionID }) else { return events }
        var session = sessions[index]
        session.outcome = outcome
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty { session.progressNote = trimmed }
        sessions[index] = session
        if state.current?.id == sessionID { state.current = session }
        if state.pendingCheckIn == sessionID { state.pendingCheckIn = nil }
        persist()
        events.append(.outcomeRecorded(session))
        return events
    }

    /// Closes the check-in without an answer.
    public func dismissCheckIn(at now: Date) {
        reconcile(at: now)
        guard let pending = state.pendingCheckIn else { return }
        if let index = sessions.lastIndex(where: { $0.id == pending }), sessions[index].outcome == nil {
            sessions[index].outcome = .notRecorded
        }
        state.pendingCheckIn = nil
        persist()
    }

    /// Links a focus session (finished or current) to a different task, or to none.
    @discardableResult
    public func reassign(sessionID: UUID, to taskID: UUID?, at now: Date) -> Bool {
        reconcile(at: now)
        guard let index = sessions.lastIndex(where: { $0.id == sessionID }), sessions[index].kind.isFocus else { return false }
        sessions[index].taskID = taskID
        if sessions[index].outcome == .wrongTask { sessions[index].outcome = nil }
        if state.current?.id == sessionID { state.current?.taskID = taskID }
        persist()
        return true
    }

    /// Focus sessions linked to a task. Links survive task deletion, so insights can
    /// still show the time as "Deleted task".
    public func sessions(forTask taskID: UUID) -> [FocusSession] {
        sessions.filter { $0.taskID == taskID && $0.kind.isFocus }
    }

    // MARK: - Data management

    /// Deletes history. An in-progress session is kept so the timer keeps working.
    public func clearHistory() {
        if let current = state.current {
            sessions = [current]
        } else {
            sessions = []
        }
        state.completedWorkSessionsInCycle = 0
        state.lastBreak = nil
        state.pendingCheckIn = nil
        persist()
    }

    /// Replaces history (restore from backup). An in-progress session is kept.
    public func replaceHistory(with restored: [FocusSession]) {
        var merged = restored.filter { !$0.status.isActive }
        if let current = state.current {
            merged.removeAll { $0.id == current.id }
            merged.append(current)
        }
        sessions = merged.sorted { $0.startedAt < $1.startedAt }
        state.pendingCheckIn = nil
        state.lastBreak = nil
        persist()
    }

    /// Replaces configuration (e.g. after settings change). Running sessions keep
    /// their own planned duration; new sessions use the new values.
    public func apply(configuration: TimerConfiguration) {
        self.configuration = configuration
    }

    // MARK: - Internals

    private func beginFocus(at start: Date, duration: TimeInterval, taskID: UUID? = nil, intent: String? = nil) -> EngineEvent {
        let cleanIntent = intent?.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = FocusSession(
            kind: configuration.focusKind,
            start: start,
            plannedDuration: max(1, duration),
            taskID: taskID,
            intent: (cleanIntent?.isEmpty ?? true) ? nil : cleanIntent
        )
        state.pendingCheckIn = nil
        state.phase = .focusing
        state.current = session
        state.breakDue = nil
        state.lastBreak = nil
        upsert(session)
        return .focusStarted(session)
    }

    private func completeFocus(_ original: FocusSession, at deadline: Date, late: Bool) -> [EngineEvent] {
        var session = original
        close(&session, status: .completed, at: deadline)
        upsert(session)
        if session.taskID != nil { state.pendingCheckIn = session.id }

        var suggested: SessionKind = .shortBreak
        if session.kind == .pomodoroFocus {
            state.completedWorkSessionsInCycle += 1
            if state.completedWorkSessionsInCycle >= max(1, configuration.longBreakEvery) {
                suggested = .longBreak
            }
        }
        let duration = suggested == .longBreak ? configuration.longBreakDuration : configuration.shortBreakDuration
        let due = BreakDue(
            focusSessionID: session.id,
            since: deadline,
            suggestedKind: suggested,
            suggestedDuration: duration,
            detectedLate: late
        )
        state.phase = .breakDue
        state.current = nil
        state.breakDue = due
        state.lastBreak = nil
        var events: [EngineEvent] = [.focusCompleted(session, late: late)]

        if configuration.autoStartBreaks && !late {
            if suggested == .longBreak { state.completedWorkSessionsInCycle = 0 }
            let breakSession = FocusSession(kind: suggested, start: deadline, plannedDuration: duration, followsFocusID: session.id)
            state.phase = .onBreak
            state.current = breakSession
            state.breakDue = nil
            upsert(breakSession)
            events.append(.breakStarted(breakSession))
        }
        return events
    }

    private func completeBreak(_ original: FocusSession, at deadline: Date, late: Bool) -> [EngineEvent] {
        var session = original
        close(&session, status: .completed, at: deadline)
        upsert(session)
        state.phase = .breakComplete
        state.current = nil
        state.breakDue = nil
        state.lastBreak = session
        var events: [EngineEvent] = [.breakCompleted(session, late: late)]
        if configuration.autoStartFocus && !late {
            events.append(beginFocus(at: deadline, duration: configuration.focusDuration))
        }
        return events
    }

    private func endEarly(_ original: FocusSession, at now: Date) -> EngineEvent {
        var session = original
        close(&session, status: .endedEarly, at: now)
        upsert(session)
        state.current = nil
        if session.kind.isFocus && session.taskID != nil { state.pendingCheckIn = session.id }
        return session.kind.isFocus ? .focusEndedEarly(session) : .breakEndedEarly(session)
    }

    private func close(_ session: inout FocusSession, status: SessionStatus, at end: Date) {
        if session.status == .running, var last = session.segments.popLast() {
            last.end = max(last.start, end)
            session.segments.append(last)
        }
        session.status = status
        session.deadline = nil
        session.remainingAtPause = nil
        session.endedAt = end
        session.actualDuration = session.activeDuration(asOf: end)
    }

    private func upsert(_ session: FocusSession) {
        if let index = sessions.lastIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
    }

    private func persist() {
        do {
            try store.saveSessions(sessions)
            try store.saveState(state)
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = error.localizedDescription
        }
    }

    /// Makes a freshly loaded state self-consistent.
    private func repairLoadedState() {
        var repaired = false
        switch state.phase {
        case .focusing, .onBreak:
            guard let current = state.current, current.status.isActive else {
                state = EngineState(completedWorkSessionsInCycle: state.completedWorkSessionsInCycle)
                repaired = true
                break
            }
            if current.status == .running && current.deadline == nil {
                var session = current
                close(&session, status: .interrupted, at: session.segments.last?.start ?? session.startedAt)
                upsert(session)
                state.phase = .idle
                state.current = nil
                repaired = true
            } else if !sessions.contains(where: { $0.id == current.id }) {
                upsert(current)
                repaired = true
            }
        case .breakDue:
            if state.breakDue == nil {
                state.phase = .idle
                repaired = true
            }
        case .breakComplete, .idle:
            if state.current != nil {
                state.current = nil
                repaired = true
            }
        }
        // Any other record left "active" by a crash is closed as interrupted.
        for index in sessions.indices where sessions[index].status.isActive && sessions[index].id != state.current?.id {
            var session = sessions[index]
            let end = session.segments.last?.end ?? session.segments.last?.start ?? session.startedAt
            close(&session, status: .interrupted, at: end)
            sessions[index] = session
            repaired = true
        }
        if repaired { persist() }
    }
}
