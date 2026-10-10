import Foundation

/// The single high-level state the app is in. Views render from this; only
/// `TimerEngine` changes it.
public enum EnginePhase: String, Codable, Sendable {
    /// Ready to start a focus session.
    case idle
    /// A focus session exists (running or paused).
    case focusing
    /// A focus session finished; a break is suggested.
    case breakDue
    /// A break session exists (running or paused).
    case onBreak
    /// A break finished; the next focus session is offered, never started unasked
    /// (unless the user enabled automatic cycles).
    case breakComplete
}

public struct BreakDue: Codable, Equatable, Sendable {
    public var focusSessionID: UUID
    /// When the focus session reached its deadline.
    public var since: Date
    public var suggestedKind: SessionKind
    public var suggestedDuration: TimeInterval
    public var snoozedUntil: Date?
    /// True when FlowBreak noticed the completion only after the fact (system sleep
    /// or the app was not running at the deadline).
    public var detectedLate: Bool

    public init(
        focusSessionID: UUID,
        since: Date,
        suggestedKind: SessionKind,
        suggestedDuration: TimeInterval,
        snoozedUntil: Date? = nil,
        detectedLate: Bool = false
    ) {
        self.focusSessionID = focusSessionID
        self.since = since
        self.suggestedKind = suggestedKind
        self.suggestedDuration = suggestedDuration
        self.snoozedUntil = snoozedUntil
        self.detectedLate = detectedLate
    }
}

public struct EngineState: Codable, Equatable, Sendable {
    public var phase: EnginePhase
    /// The running or paused session while `focusing` / `onBreak`.
    public var current: FocusSession?
    public var breakDue: BreakDue?
    /// The break that just finished, while `breakComplete`.
    public var lastBreak: FocusSession?
    /// Pomodoro work sessions completed since the last long break.
    public var completedWorkSessionsInCycle: Int

    public init(
        phase: EnginePhase = .idle,
        current: FocusSession? = nil,
        breakDue: BreakDue? = nil,
        lastBreak: FocusSession? = nil,
        completedWorkSessionsInCycle: Int = 0
    ) {
        self.phase = phase
        self.current = current
        self.breakDue = breakDue
        self.lastBreak = lastBreak
        self.completedWorkSessionsInCycle = completedWorkSessionsInCycle
    }

    public static let idle = EngineState()

    public var isRunning: Bool { current?.status == .running }
    public var isPaused: Bool { current?.status == .paused }
}

/// Things that happened during an engine operation. The app reacts to these
/// (sounds, catch-up notifications) after the new state has been persisted.
public enum EngineEvent: Equatable, Sendable {
    case focusStarted(FocusSession)
    case paused(FocusSession)
    case resumed(FocusSession)
    case focusCompleted(FocusSession, late: Bool)
    case focusEndedEarly(FocusSession)
    case sessionCancelled(FocusSession)
    case breakStarted(FocusSession)
    case breakCompleted(FocusSession, late: Bool)
    case breakEndedEarly(FocusSession)
    case breakExtended(FocusSession)
    case breakSkipped(BreakDue)
    case snoozed(until: Date)
    case clockAdjusted(by: TimeInterval)
}
