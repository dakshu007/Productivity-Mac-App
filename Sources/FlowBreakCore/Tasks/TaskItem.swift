import Foundation

public enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case inbox
    case today
    case next
    case someday
    case inProgress
    case completed
    case archived

    public var displayName: String {
        switch self {
        case .inbox: return "Inbox"
        case .today: return "Today"
        case .next: return "Next"
        case .someday: return "Someday"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .archived: return "Archived"
        }
    }

    /// Open = still something to do.
    public var isOpen: Bool { self != .completed && self != .archived }
}

public enum TaskPriority: Int, Codable, CaseIterable, Comparable, Sendable {
    case low = 0
    case normal = 1
    case high = 2
    case critical = 3

    public static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool { lhs.rawValue < rhs.rawValue }

    public var displayName: String {
        switch self {
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }
}

public enum RecurrenceRule: String, Codable, CaseIterable, Sendable {
    case daily
    case weekdays
    case weekly
    case monthly

    public var displayName: String {
        switch self {
        case .daily: return "Every day"
        case .weekdays: return "Every weekday"
        case .weekly: return "Every week"
        case .monthly: return "Every month"
        }
    }

    /// The next occurrence strictly after `date`, keeping the time of day.
    public func nextDate(after date: Date, calendar: Calendar) -> Date {
        switch self {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
        case .weekdays:
            var next = calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
            while calendar.isDateInWeekend(next) {
                next = calendar.date(byAdding: .day, value: 1, to: next) ?? next.addingTimeInterval(86_400)
            }
            return next
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date) ?? date.addingTimeInterval(7 * 86_400)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date.addingTimeInterval(30 * 86_400)
        }
    }
}

public struct ProgressNote: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var text: String
    public var sessionID: UUID?

    public init(id: UUID = UUID(), createdAt: Date, text: String, sessionID: UUID? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.text = text
        self.sessionID = sessionID
    }
}

/// A task. Named `TaskItem` to avoid clashing with Swift concurrency's `Task`.
public struct TaskItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var notes: String?
    /// "Proof of Done": the outcome that means this is finished, set before work begins.
    public var definitionOfDone: String?
    /// What actually happened, optionally recorded when completing.
    public var completionNote: String?
    public var status: TaskStatus
    /// Where the task was before it was completed or archived, so reopen/restore return it there.
    public var previousStatus: TaskStatus?
    public var priority: TaskPriority
    public var createdAt: Date
    public var updatedAt: Date
    public var dueAt: Date?
    public var completedAt: Date?
    public var archivedAt: Date?
    public var estimatedMinutes: Int?
    public var project: String?
    public var parentID: UUID?
    public var tags: [String]
    public var sortOrder: Double
    public var recurrence: RecurrenceRule?
    /// Shared by every instance of a recurring task.
    public var seriesID: UUID?
    public var link: String?
    /// Private tasks are shown as "Private task" in Insights and exports of summaries.
    public var isPrivate: Bool
    /// Local start-of-day on which this task is one of the "Big Three".
    public var bigThreeDay: Date?
    public var progressNotes: [ProgressNote]

    public init(
        id: UUID = UUID(),
        title: String,
        status: TaskStatus = .inbox,
        priority: TaskPriority = .normal,
        createdAt: Date,
        notes: String? = nil,
        definitionOfDone: String? = nil,
        dueAt: Date? = nil,
        estimatedMinutes: Int? = nil,
        project: String? = nil,
        tags: [String] = [],
        parentID: UUID? = nil,
        sortOrder: Double = 0
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.definitionOfDone = definitionOfDone
        self.completionNote = nil
        self.status = status
        self.previousStatus = nil
        self.priority = priority
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.dueAt = dueAt
        self.completedAt = nil
        self.archivedAt = nil
        self.estimatedMinutes = estimatedMinutes
        self.project = project
        self.parentID = parentID
        self.tags = tags
        self.sortOrder = sortOrder
        self.recurrence = nil
        self.seriesID = nil
        self.link = nil
        self.isPrivate = false
        self.bigThreeDay = nil
        self.progressNotes = []
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, notes, definitionOfDone, completionNote, status, previousStatus, priority
        case createdAt, updatedAt, dueAt, completedAt, archivedAt, estimatedMinutes, project
        case parentID, tags, sortOrder, recurrence, seriesID, link, isPrivate, bigThreeDay, progressNotes
    }

    /// Tolerant decoding: fields added in later versions default sensibly.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        definitionOfDone = try c.decodeIfPresent(String.self, forKey: .definitionOfDone)
        completionNote = try c.decodeIfPresent(String.self, forKey: .completionNote)
        status = (try? c.decodeIfPresent(TaskStatus.self, forKey: .status)) ?? .inbox
        previousStatus = try? c.decodeIfPresent(TaskStatus.self, forKey: .previousStatus)
        priority = (try? c.decodeIfPresent(TaskPriority.self, forKey: .priority)) ?? .normal
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        dueAt = try c.decodeIfPresent(Date.self, forKey: .dueAt)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        archivedAt = try c.decodeIfPresent(Date.self, forKey: .archivedAt)
        estimatedMinutes = try c.decodeIfPresent(Int.self, forKey: .estimatedMinutes)
        project = try c.decodeIfPresent(String.self, forKey: .project)
        parentID = try c.decodeIfPresent(UUID.self, forKey: .parentID)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        sortOrder = try c.decodeIfPresent(Double.self, forKey: .sortOrder) ?? 0
        recurrence = try? c.decodeIfPresent(RecurrenceRule.self, forKey: .recurrence)
        seriesID = try c.decodeIfPresent(UUID.self, forKey: .seriesID)
        link = try c.decodeIfPresent(String.self, forKey: .link)
        isPrivate = try c.decodeIfPresent(Bool.self, forKey: .isPrivate) ?? false
        bigThreeDay = try c.decodeIfPresent(Date.self, forKey: .bigThreeDay)
        progressNotes = try c.decodeIfPresent([ProgressNote].self, forKey: .progressNotes) ?? []
    }

    public var isOpen: Bool { status.isOpen }

    public func isOverdue(now: Date, calendar: Calendar) -> Bool {
        guard isOpen, let dueAt else { return false }
        return dueAt < calendar.startOfDay(for: now)
    }

    public func isDue(onOrBefore day: Date, calendar: Calendar) -> Bool {
        guard let dueAt else { return false }
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) ?? day
        return dueAt < end
    }

    public func isBigThree(on day: Date, calendar: Calendar) -> Bool {
        guard let bigThreeDay, isOpen || status == .completed else { return false }
        return calendar.isDate(bigThreeDay, inSameDayAs: day)
    }

    /// Plain Markdown, for copy/share/export.
    public func markdown(subtasks: [TaskItem] = []) -> String {
        var lines = ["- [\(status == .completed ? "x" : " ")] \(title)"]
        var meta: [String] = []
        if priority >= .high { meta.append("priority: \(priority.displayName.lowercased())") }
        if let dueAt { meta.append("due: \(ISO8601.dateOnly.string(from: dueAt))") }
        if let estimatedMinutes { meta.append("estimate: \(estimatedMinutes)m") }
        if let project, !project.isEmpty { meta.append("project: \(project)") }
        if !tags.isEmpty { meta.append(tags.map { "#\($0)" }.joined(separator: " ")) }
        if !meta.isEmpty { lines.append("  - " + meta.joined(separator: " · ")) }
        if let definitionOfDone, !definitionOfDone.isEmpty { lines.append("  - Done when: \(definitionOfDone)") }
        if let notes, !notes.isEmpty {
            for line in notes.split(separator: "\n", omittingEmptySubsequences: false) {
                lines.append("  > \(line)")
            }
        }
        for sub in subtasks {
            lines.append("  - [\(sub.status == .completed ? "x" : " ")] \(sub.title)")
        }
        return lines.joined(separator: "\n")
    }
}

extension ISO8601 {
    static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
