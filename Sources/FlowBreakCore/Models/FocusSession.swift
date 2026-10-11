import Foundation

/// What a session is for.
public enum SessionKind: String, Codable, CaseIterable, Sendable {
    case focus
    case pomodoroFocus
    case shortBreak
    case longBreak

    public var isFocus: Bool { self == .focus || self == .pomodoroFocus }
    public var isBreak: Bool { !isFocus }

    public var displayName: String {
        switch self {
        case .focus: return "Focus"
        case .pomodoroFocus: return "Pomodoro"
        case .shortBreak: return "Short break"
        case .longBreak: return "Long break"
        }
    }
}

/// How a task-linked focus session went, recorded by the user afterwards.
/// A timer ending never completes a task by itself.
public enum SessionOutcome: String, Codable, CaseIterable, Sendable {
    case completed
    case progressMade
    case continueLater
    case wrongTask
    case notRecorded

    public var displayName: String {
        switch self {
        case .completed: return "Completed"
        case .progressMade: return "Progress made"
        case .continueLater: return "Continue later"
        case .wrongTask: return "Wrong task"
        case .notRecorded: return "Not recorded"
        }
    }
}

/// Lifecycle status of a session record.
///
/// - `completed`: ran until its deadline.
/// - `endedEarly`: the user finished it before the deadline (e.g. took a break mid-focus,
///   or returned from a break early). Its active time still counts.
/// - `cancelled`: the user stopped it.
/// - `interrupted`: FlowBreak found it in an inconsistent state (e.g. a corrupt or
///   future-dated record on relaunch) and closed it.
public enum SessionStatus: String, Codable, Sendable {
    case running
    case paused
    case completed
    case endedEarly
    case cancelled
    case interrupted

    public var isActive: Bool { self == .running || self == .paused }

    public var displayName: String {
        switch self {
        case .running: return "Running"
        case .paused: return "Paused"
        case .completed: return "Completed"
        case .endedEarly: return "Ended early"
        case .cancelled: return "Stopped"
        case .interrupted: return "Interrupted"
        }
    }
}

/// A stretch of un-paused time. Pausing closes the current segment; resuming opens a new one.
/// Storing segments (rather than a counter) lets statistics split sessions exactly at midnight.
public struct ActiveSegment: Codable, Equatable, Sendable {
    public var start: Date
    public var end: Date?

    public init(start: Date, end: Date? = nil) {
        self.start = start
        self.end = end
    }

    public func duration(asOf now: Date) -> TimeInterval {
        max(0, (end ?? now).timeIntervalSince(start))
    }
}

/// A persisted focus or break session. Absolute dates are the source of truth;
/// remaining time is always recomputed from `deadline`, never decremented.
public struct FocusSession: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: SessionKind
    public var status: SessionStatus
    public var createdAt: Date
    public var startedAt: Date
    public var plannedDuration: TimeInterval
    /// Set while running: the moment the session completes.
    public var deadline: Date?
    /// Set while paused: the exact time that was left when the user paused.
    public var remainingAtPause: TimeInterval?
    public var segments: [ActiveSegment]
    /// When the session completed, ended early, or was cancelled.
    public var endedAt: Date?
    /// Active (un-paused) time, recorded when the session ends.
    public var actualDuration: TimeInterval?
    /// For breaks: the focus session this break follows, used for break adherence.
    public var followsFocusID: UUID?
    /// For focus sessions: the task worked on, if any.
    public var taskID: UUID?
    /// Optional intention typed when starting ("Draft the intro").
    public var intent: String?
    public var outcome: SessionOutcome?
    public var progressNote: String?
    /// Distraction nudges shown during this focus session (only when nudges are on).
    public var nudges: Int?

    public init(
        id: UUID = UUID(),
        kind: SessionKind,
        start: Date,
        plannedDuration: TimeInterval,
        followsFocusID: UUID? = nil,
        taskID: UUID? = nil,
        intent: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.status = .running
        self.createdAt = start
        self.startedAt = start
        self.plannedDuration = plannedDuration
        self.deadline = start.addingTimeInterval(plannedDuration)
        self.remainingAtPause = nil
        self.segments = [ActiveSegment(start: start)]
        self.endedAt = nil
        self.actualDuration = nil
        self.followsFocusID = followsFocusID
        self.taskID = taskID
        self.intent = intent
        self.outcome = nil
        self.progressNote = nil
    }

    /// When the current pause began, if paused.
    public var pausedAt: Date? {
        status == .paused ? segments.last?.end : nil
    }

    /// Total paused time between active segments.
    public var accumulatedPause: TimeInterval {
        guard segments.count > 1 else { return 0 }
        var total: TimeInterval = 0
        for index in 1..<segments.count {
            if let previousEnd = segments[index - 1].end {
                total += max(0, segments[index].start.timeIntervalSince(previousEnd))
            }
        }
        return total
    }

    /// Un-paused time so far.
    public func activeDuration(asOf now: Date) -> TimeInterval {
        segments.reduce(0) { $0 + $1.duration(asOf: now) }
    }

    /// Remaining time, derived from the deadline (running) or the captured value (paused).
    public func remaining(at now: Date) -> TimeInterval {
        switch status {
        case .paused:
            return max(0, remainingAtPause ?? 0)
        case .running:
            guard let deadline else { return 0 }
            let raw = deadline.timeIntervalSince(now)
            // If the wall clock moved backwards, never report more than was left when
            // this segment began.
            let cap: TimeInterval
            if let segmentStart = segments.last?.start {
                cap = deadline.timeIntervalSince(segmentStart)
            } else {
                cap = plannedDuration
            }
            return min(max(0, raw), max(0, cap))
        default:
            return 0
        }
    }

    /// 0...1 completion fraction.
    public func progress(at now: Date) -> Double {
        guard plannedDuration > 0 else { return 1 }
        let fraction = 1 - remaining(at: now) / plannedDuration
        return min(1, max(0, fraction))
    }
}
