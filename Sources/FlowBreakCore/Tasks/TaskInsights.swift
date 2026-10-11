import Foundation

public struct TaskFocusSummary: Equatable, Identifiable, Sendable {
    public var taskID: UUID
    public var title: String
    public var project: String?
    public var status: TaskStatus?
    public var isHidden: Bool
    /// Focus sessions linked to the task within the period.
    public var sessions: Int
    /// Focus time within the period (breaks never count).
    public var focusTime: TimeInterval
    /// All recorded focus time for the task, for estimate comparisons.
    public var totalFocusTime: TimeInterval
    public var estimatedMinutes: Int?
    public var id: UUID { taskID }
}

public struct ProjectFocus: Equatable, Identifiable, Sendable {
    public var name: String
    public var focusTime: TimeInterval
    public var id: String { name }
}

public struct TaskInsightsSummary: Equatable, Sendable {
    /// Tasks completed within the period.
    public var completedCount: Int
    /// Open tasks that had focus time within the period.
    public var workedOnButOpen: Int
    /// Average number of linked focus sessions (all time) per task completed in the period.
    public var averageSessionsPerCompletedTask: Double?
    public var byTask: [TaskFocusSummary]
    public var byProject: [ProjectFocus]
    /// Focus time in the period that wasn't linked to any task.
    public var unlinkedFocusTime: TimeInterval
    public var completedByDay: [DailyCount]
}

public struct DailyCount: Equatable, Identifiable, Sendable {
    public var day: Date
    public var count: Int
    public var id: Date { day }
}

/// Task statistics derived from task and session records. Estimates are compared
/// with recorded focus time only; nothing is inferred when time wasn't tracked.
public enum TaskInsightsCalculator {
    public static func summary(
        tasks: [TaskItem],
        sessions: [FocusSession],
        interval: DateInterval,
        dayCount: Int,
        now: Date,
        hidePrivate: Bool,
        calendar: Calendar
    ) -> TaskInsightsSummary {
        let byID = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let focus = sessions.filter { $0.kind.isFocus }

        var perTask: [UUID: TaskFocusSummary] = [:]
        var unlinked: TimeInterval = 0
        for session in focus {
            let inPeriod = StatisticsCalculator.activeTime(of: session, in: interval, now: now)
            guard let taskID = session.taskID else {
                unlinked += inPeriod
                continue
            }
            let task = byID[taskID]
            let hidden = hidePrivate && (task?.isPrivate ?? false)
            var entry = perTask[taskID] ?? TaskFocusSummary(
                taskID: taskID,
                title: hidden ? "Private task" : (task?.title ?? "Deleted task"),
                project: hidden ? nil : task?.project,
                status: task?.status,
                isHidden: hidden,
                sessions: 0,
                focusTime: 0,
                totalFocusTime: 0,
                estimatedMinutes: task?.estimatedMinutes
            )
            entry.totalFocusTime += session.actualDuration ?? session.activeDuration(asOf: now)
            if inPeriod > 0 {
                entry.sessions += 1
                entry.focusTime += inPeriod
            }
            perTask[taskID] = entry
        }

        let inPeriod = perTask.values.filter { $0.focusTime > 0 }
        let completedTasks = tasks.filter { task in
            guard task.status == .completed, let completedAt = task.completedAt else { return false }
            return completedAt >= interval.start && completedAt < interval.end
        }
        let sessionCounts = Dictionary(grouping: focus.compactMap(\.taskID), by: { $0 }).mapValues(\.count)
        let average: Double? = completedTasks.isEmpty
            ? nil
            : Double(completedTasks.map { sessionCounts[$0.id] ?? 0 }.reduce(0, +)) / Double(completedTasks.count)

        var projects: [String: TimeInterval] = [:]
        for entry in inPeriod {
            let name = entry.project?.isEmpty == false ? entry.project ?? "No project" : "No project"
            projects[name, default: 0] += entry.focusTime
        }

        var daily: [DailyCount] = []
        var day = calendar.startOfDay(for: interval.start)
        for _ in 0..<max(1, dayCount) {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            let count = completedTasks.filter { ($0.completedAt ?? .distantPast) >= day && ($0.completedAt ?? .distantPast) < next }.count
            daily.append(DailyCount(day: day, count: count))
            day = next
        }

        return TaskInsightsSummary(
            completedCount: completedTasks.count,
            workedOnButOpen: inPeriod.filter { $0.status?.isOpen ?? false }.count,
            averageSessionsPerCompletedTask: average,
            byTask: inPeriod.sorted { $0.focusTime > $1.focusTime },
            byProject: projects.map { ProjectFocus(name: $0.key, focusTime: $0.value) }.sorted { $0.focusTime > $1.focusTime },
            unlinkedFocusTime: unlinked,
            completedByDay: daily
        )
    }

    /// Recorded focus time for one task across all sessions.
    public static func focusTime(for taskID: UUID, sessions: [FocusSession], now: Date) -> (time: TimeInterval, sessions: Int) {
        let linked = sessions.filter { $0.kind.isFocus && $0.taskID == taskID }
        return (linked.reduce(0) { $0 + ($1.actualDuration ?? $1.activeDuration(asOf: now)) }, linked.count)
    }
}

// MARK: - Weekly review

public struct WeeklyReflection: Codable, Equatable, Identifiable, Sendable {
    public var weekStart: Date
    public var helped: String
    public var distracted: String
    public var updatedAt: Date
    public var id: Date { weekStart }

    public init(weekStart: Date, helped: String = "", distracted: String = "", updatedAt: Date) {
        self.weekStart = weekStart
        self.helped = helped
        self.distracted = distracted
        self.updatedAt = updatedAt
    }
}

public protocol ReflectionPersisting: AnyObject {
    func loadReflections() throws -> [WeeklyReflection]
    func saveReflections(_ reflections: [WeeklyReflection]) throws
}

extension JSONFileStore: ReflectionPersisting {
    public func loadReflections() throws -> [WeeklyReflection] {
        try readFile([WeeklyReflection].self, from: directory.appendingPathComponent("reflections.json")) ?? []
    }

    public func saveReflections(_ reflections: [WeeklyReflection]) throws {
        try writeFile(reflections, to: directory.appendingPathComponent("reflections.json"))
    }
}

public struct WeeklyReview: Equatable, Sendable {
    public var week: DateInterval
    public var focusTime: TimeInterval
    public var sessionsCompleted: Int
    public var breaksTaken: Int
    public var tasksCompleted: [TaskItem]
    /// Open tasks that were due this week or earlier.
    public var carriedOver: [TaskItem]
    public var byProject: [ProjectFocus]
    public var reflection: WeeklyReflection?

    public static func week(containing date: Date, calendar: Calendar) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: date) ?? DateInterval(start: calendar.startOfDay(for: date), duration: 7 * 86_400)
    }

    public static func make(
        tasks: [TaskItem],
        sessions: [FocusSession],
        reflections: [WeeklyReflection],
        now: Date,
        hidePrivate: Bool,
        calendar: Calendar
    ) -> WeeklyReview {
        let week = Self.week(containing: now, calendar: calendar)
        let stats = StatisticsCalculator(calendar: calendar).summary(sessions: sessions, interval: week, dayCount: 7, now: now)
        let taskStats = TaskInsightsCalculator.summary(tasks: tasks, sessions: sessions, interval: week, dayCount: 7, now: now, hidePrivate: hidePrivate, calendar: calendar)
        let completed = tasks
            .filter { $0.status == .completed && ($0.completedAt.map { week.contains($0) } ?? false) }
            .sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
        let carried = tasks
            .filter { $0.isOpen && $0.parentID == nil && ($0.dueAt.map { $0 < week.end && $0 < now } ?? false) }
            .sorted { ($0.dueAt ?? .distantPast) < ($1.dueAt ?? .distantPast) }
        return WeeklyReview(
            week: week,
            focusTime: stats.focusTime,
            sessionsCompleted: stats.focusSessionsCompleted,
            breaksTaken: stats.breaksTaken,
            tasksCompleted: completed,
            carriedOver: carried,
            byProject: taskStats.byProject,
            reflection: reflections.first { calendar.isDate($0.weekStart, inSameDayAs: week.start) }
        )
    }

    /// A Markdown summary the user can save or paste. Private task titles are hidden
    /// when `hidePrivate` is on.
    public func markdown(hidePrivate: Bool, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        let lastDay = week.end.addingTimeInterval(-1)
        func name(_ task: TaskItem) -> String { hidePrivate && task.isPrivate ? "Private task" : task.title }

        var lines = [
            "# FlowBreak weekly review — \(formatter.string(from: week.start))–\(formatter.string(from: lastDay))",
            "",
            "- Focus time: \(DurationFormatter.short(focusTime))",
            "- Focus sessions completed: \(sessionsCompleted)",
            "- Breaks taken: \(breaksTaken)",
            "- Tasks completed: \(tasksCompleted.count)",
            "",
        ]
        if !tasksCompleted.isEmpty {
            lines.append("## Completed")
            lines.append(contentsOf: tasksCompleted.map { "- [x] \(name($0))" })
            lines.append("")
        }
        if !carriedOver.isEmpty {
            lines.append("## Carried over")
            lines.append(contentsOf: carriedOver.map { "- [ ] \(name($0))" })
            lines.append("")
        }
        if !byProject.isEmpty {
            lines.append("## Focus by project")
            lines.append(contentsOf: byProject.map { "- \($0.name): \(DurationFormatter.short($0.focusTime))" })
            lines.append("")
        }
        if let reflection, !(reflection.helped.isEmpty && reflection.distracted.isEmpty) {
            lines.append("## Reflection")
            if !reflection.helped.isEmpty { lines.append("**What helped:** \(reflection.helped)") }
            if !reflection.distracted.isEmpty { lines.append("**What distracted me:** \(reflection.distracted)") }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
