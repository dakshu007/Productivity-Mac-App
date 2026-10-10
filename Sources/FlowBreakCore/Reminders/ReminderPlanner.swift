import Foundation

public struct ReminderSettings: Equatable, Sendable {
    public var enabled: Bool
    public var repeatInterval: TimeInterval
    /// Extra reminders after the first one. Bounded to `AppSettings.maxRepeatCount`.
    public var repeatCount: Int
    public var quietHours: QuietHours?

    public init(enabled: Bool = true, repeatInterval: TimeInterval = 300, repeatCount: Int = 3, quietHours: QuietHours? = nil) {
        self.enabled = enabled
        self.repeatInterval = repeatInterval
        self.repeatCount = repeatCount
        self.quietHours = quietHours
    }
}

public enum ReminderKind: Equatable, Sendable {
    /// The focus session ends now.
    case focusEnded
    /// A repeated "time for a break" nudge (attempt starts at 1).
    case breakReminder(attempt: Int)
    /// The break ends now.
    case breakEnded
}

public struct PlannedReminder: Equatable, Sendable {
    /// Deterministic identifier, so re-planning replaces rather than duplicates.
    public var id: String
    public var date: Date
    public var kind: ReminderKind
    public var breakMinutes: Int

    public init(id: String, date: Date, kind: ReminderKind, breakMinutes: Int) {
        self.id = id
        self.date = date
        self.kind = kind
        self.breakMinutes = breakMinutes
    }
}

/// Computes exactly which local notifications should be pending for a given state.
///
/// The notification layer removes all of FlowBreak's pending requests and adds this
/// list after every state change, so cancelling is automatic: starting a break,
/// resuming focus, skipping, pausing, or disabling reminders all yield a plan without
/// the old reminders. The plan is always finite (1 + repeatCount reminders at most).
public enum ReminderPlanner {
    public static let identifierPrefix = "flowbreak."

    public static func plan(
        state: EngineState,
        settings: ReminderSettings,
        defaultBreakDuration: TimeInterval,
        now: Date,
        calendar: Calendar = .current
    ) -> [PlannedReminder] {
        guard settings.enabled else { return [] }
        let repeats = min(max(settings.repeatCount, 0), AppSettings.maxRepeatCount)
        let interval = max(60, settings.repeatInterval)
        var result: [PlannedReminder] = []

        switch state.phase {
        case .focusing:
            guard let session = state.current, session.status == .running, let deadline = session.deadline else { break }
            let minutes = Int((defaultBreakDuration / 60).rounded())
            result.append(PlannedReminder(id: "\(identifierPrefix)due.\(session.id.uuidString).0", date: deadline, kind: .focusEnded, breakMinutes: minutes))
            for attempt in stride(from: 1, through: repeats, by: 1) {
                result.append(PlannedReminder(
                    id: "\(identifierPrefix)due.\(session.id.uuidString).\(attempt)",
                    date: deadline.addingTimeInterval(interval * Double(attempt)),
                    kind: .breakReminder(attempt: attempt),
                    breakMinutes: minutes
                ))
            }
        case .breakDue:
            guard let due = state.breakDue else { break }
            let minutes = Int((due.suggestedDuration / 60).rounded())
            if let snoozed = due.snoozedUntil {
                let tag = Int(snoozed.timeIntervalSince1970)
                for attempt in stride(from: 0, through: repeats, by: 1) {
                    result.append(PlannedReminder(
                        id: "\(identifierPrefix)snooze.\(due.focusSessionID.uuidString).\(tag).\(attempt)",
                        date: snoozed.addingTimeInterval(interval * Double(attempt)),
                        kind: .breakReminder(attempt: attempt + 1),
                        breakMinutes: minutes
                    ))
                }
            } else {
                for attempt in stride(from: 1, through: repeats, by: 1) {
                    result.append(PlannedReminder(
                        id: "\(identifierPrefix)due.\(due.focusSessionID.uuidString).\(attempt)",
                        date: due.since.addingTimeInterval(interval * Double(attempt)),
                        kind: .breakReminder(attempt: attempt),
                        breakMinutes: minutes
                    ))
                }
            }
        case .onBreak:
            guard let session = state.current, session.status == .running, let deadline = session.deadline else { break }
            result.append(PlannedReminder(
                id: "\(identifierPrefix)breakend.\(session.id.uuidString)",
                date: deadline,
                kind: .breakEnded,
                breakMinutes: Int((session.plannedDuration / 60).rounded())
            ))
        case .idle, .breakComplete:
            break
        }

        return result.filter { reminder in
            guard reminder.date > now else { return false }
            if let quiet = settings.quietHours, quiet.contains(reminder.date, calendar: calendar) { return false }
            return true
        }
    }
}
