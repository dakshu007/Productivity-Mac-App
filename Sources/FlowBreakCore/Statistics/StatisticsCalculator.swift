import Foundation

public enum InsightsRange: String, CaseIterable, Identifiable, Sendable {
    case today
    case last7Days
    case last30Days

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .today: return "Today"
        case .last7Days: return "7 Days"
        case .last30Days: return "30 Days"
        }
    }

    public var dayCount: Int {
        switch self {
        case .today: return 1
        case .last7Days: return 7
        case .last30Days: return 30
        }
    }

    /// From local midnight `dayCount - 1` days ago until the end of today.
    public func interval(now: Date, calendar: Calendar) -> DateInterval {
        let startOfToday = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(dayCount - 1), to: startOfToday) ?? startOfToday
        let end = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
        return DateInterval(start: start, end: end)
    }
}

public struct DailyFocus: Equatable, Identifiable, Sendable {
    public var day: Date
    public var focusTime: TimeInterval
    public var id: Date { day }
}

public struct InsightsSummary: Equatable, Sendable {
    public var interval: DateInterval
    /// Un-paused time spent in focus sessions (any outcome), clipped to the period.
    public var focusTime: TimeInterval
    /// Focus sessions that ran to their deadline within the period.
    public var focusSessionsCompleted: Int
    /// Break sessions started within the period.
    public var breaksTaken: Int
    /// Completed focus sessions that were followed by a break.
    public var adherenceNumerator: Int
    /// Completed focus sessions.
    public var adherenceDenominator: Int
    public var longestFocus: TimeInterval?
    /// Long breaks started (each closes a full Pomodoro cycle).
    public var pomodoroCycles: Int
    public var daily: [DailyFocus]
    /// Sessions overlapping the period, newest first.
    public var timeline: [FocusSession]

    public var adherence: Double? {
        adherenceDenominator > 0 ? Double(adherenceNumerator) / Double(adherenceDenominator) : nil
    }

    public var isEmpty: Bool { timeline.isEmpty }
}

/// Derives every displayed statistic from persisted session records. Nothing is
/// stored as a counter, so the dashboard can never drift from the history.
public struct StatisticsCalculator {
    public var calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// Active focus time of `session` that falls inside `interval`. Sessions that
    /// cross midnight are split exactly at the boundary using their active segments.
    public static func activeTime(of session: FocusSession, in interval: DateInterval, now: Date) -> TimeInterval {
        session.segments.reduce(0) { total, segment in
            let end = segment.end ?? now
            let start = max(segment.start, interval.start)
            let clippedEnd = min(end, interval.end)
            return total + max(0, clippedEnd.timeIntervalSince(start))
        }
    }

    public func summary(sessions: [FocusSession], range: InsightsRange, now: Date) -> InsightsSummary {
        summary(sessions: sessions, interval: range.interval(now: now, calendar: calendar), dayCount: range.dayCount, now: now)
    }

    public func summary(sessions: [FocusSession], interval: DateInterval, dayCount: Int, now: Date) -> InsightsSummary {
        let focusSessions = sessions.filter { $0.kind.isFocus }
        let breakSessions = sessions.filter { $0.kind.isBreak }

        let focusTime = focusSessions.reduce(0) { $0 + Self.activeTime(of: $1, in: interval, now: now) }

        let completed = focusSessions.filter {
            $0.status == .completed && ($0.endedAt.map { interval.contains($0) && $0 < interval.end } ?? false)
        }
        let breaksInPeriod = breakSessions.filter { interval.contains($0.startedAt) && $0.startedAt < interval.end }
        let followedIDs = Set(breakSessions.compactMap { $0.followsFocusID })
        let adhered = completed.filter { followedIDs.contains($0.id) }.count

        let longest = focusSessions
            .filter { interval.contains($0.startedAt) && $0.startedAt < interval.end }
            .map { $0.actualDuration ?? $0.activeDuration(asOf: now) }
            .max()

        let cycles = breaksInPeriod.filter { $0.kind == .longBreak }.count

        var daily: [DailyFocus] = []
        var day = calendar.startOfDay(for: interval.start)
        for _ in 0..<max(1, dayCount) {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            let dayInterval = DateInterval(start: day, end: next)
            let total = focusSessions.reduce(0) { $0 + Self.activeTime(of: $1, in: dayInterval, now: now) }
            daily.append(DailyFocus(day: day, focusTime: total))
            day = next
        }

        let timeline = sessions
            .filter { session in
                let end = session.endedAt ?? now
                return session.startedAt < interval.end && end >= interval.start
            }
            .sorted { $0.startedAt > $1.startedAt }

        return InsightsSummary(
            interval: interval,
            focusTime: focusTime,
            focusSessionsCompleted: completed.count,
            breaksTaken: breaksInPeriod.count,
            adherenceNumerator: adhered,
            adherenceDenominator: completed.count,
            longestFocus: longest,
            pomodoroCycles: cycles,
            daily: daily,
            timeline: timeline
        )
    }

    /// Focus time and breaks for "today", used by the menu-bar summary.
    public func today(sessions: [FocusSession], now: Date) -> (focusTime: TimeInterval, breaks: Int) {
        let s = summary(sessions: sessions, range: .today, now: now)
        return (s.focusTime, s.breaksTaken)
    }
}
