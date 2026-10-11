import Foundation

public protocol TaskPersisting: AnyObject {
    func loadTasks() throws -> [TaskItem]
    func saveTasks(_ tasks: [TaskItem]) throws
}

public enum TaskError: Error, LocalizedError, Equatable {
    case emptyTitle
    case notFound
    case parentCycle
    case bigThreeFull

    public var errorDescription: String? {
        switch self {
        case .emptyTitle: return "A task needs a title."
        case .notFound: return "That task no longer exists."
        case .parentCycle: return "A task can't be a subtask of itself or of its own subtasks."
        case .bigThreeFull: return "Today's Big Three is full. Remove one first."
        }
    }
}

/// Values for a new task (from Quick Add or the task window).
public struct TaskDraft: Equatable, Sendable {
    public var title: String
    public var status: TaskStatus
    public var priority: TaskPriority
    public var notes: String?
    public var definitionOfDone: String?
    public var dueAt: Date?
    public var estimatedMinutes: Int?
    public var project: String?
    public var tags: [String]
    public var parentID: UUID?

    public init(
        title: String,
        status: TaskStatus = .inbox,
        priority: TaskPriority = .normal,
        notes: String? = nil,
        definitionOfDone: String? = nil,
        dueAt: Date? = nil,
        estimatedMinutes: Int? = nil,
        project: String? = nil,
        tags: [String] = [],
        parentID: UUID? = nil
    ) {
        self.title = title
        self.status = status
        self.priority = priority
        self.notes = notes
        self.definitionOfDone = definitionOfDone
        self.dueAt = dueAt
        self.estimatedMinutes = estimatedMinutes
        self.project = project
        self.tags = tags
        self.parentID = parentID
    }
}

/// Everything needed to undo a completion.
public struct TaskCompletion: Equatable, Sendable {
    public var task: TaskItem
    public var previousStatus: TaskStatus
    /// The next instance created for a recurring task, if any.
    public var spawnedInstanceID: UUID?
}

/// Lists the task window and popover show.
public enum TaskListKind: Hashable, Sendable {
    case today
    case inbox
    case next
    case someday
    case inProgress
    case completed
    case archived
    case project(String)
    case search(String)

    public var title: String {
        switch self {
        case .today: return "Today"
        case .inbox: return "Inbox"
        case .next: return "Next"
        case .someday: return "Someday"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .archived: return "Archived"
        case let .project(name): return name
        case .search: return "Search"
        }
    }

    /// Status given to tasks created while this list is showing.
    public var defaultStatus: TaskStatus {
        switch self {
        case .today: return .today
        case .next: return .next
        case .someday: return .someday
        case .inProgress: return .inProgress
        default: return .inbox
        }
    }
}

/// In-memory task collection with explicit persistence. All mutations take
/// `now` so behaviour is deterministic in tests.
public final class TaskRepository {
    public static let bigThreeLimit = 3

    public private(set) var tasks: [TaskItem]
    public private(set) var lastPersistenceError: String?
    public var calendar: Calendar
    private let store: TaskPersisting

    public init(store: TaskPersisting, calendar: Calendar = .current) {
        self.store = store
        self.calendar = calendar
        do {
            tasks = try store.loadTasks()
        } catch {
            tasks = []
            lastPersistenceError = error.localizedDescription
        }
    }

    // MARK: Persistence

    /// Writes all tasks atomically. Returns false (and records the error) on failure.
    @discardableResult
    public func save() -> Bool {
        do {
            try store.saveTasks(tasks)
            lastPersistenceError = nil
            return true
        } catch {
            lastPersistenceError = error.localizedDescription
            return false
        }
    }

    // MARK: Queries

    public func task(_ id: UUID) -> TaskItem? {
        tasks.first { $0.id == id }
    }

    public func subtasks(of id: UUID) -> [TaskItem] {
        tasks.filter { $0.parentID == id && $0.status != .archived }.sorted(by: Self.manualOrder)
    }

    public var projects: [String] {
        let names = tasks.filter { $0.status != .archived }.compactMap { $0.project?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return Array(Set(names)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Top-level tasks for a list. Subtasks are shown inside their parent.
    public func tasks(in list: TaskListKind, now: Date) -> [TaskItem] {
        let topLevel = tasks.filter { $0.parentID == nil }
        switch list {
        case .today:
            return topLevel
                .filter { task in
                    guard task.isOpen, task.status != .someday else { return false }
                    return task.status == .today || task.status == .inProgress
                        || task.isDue(onOrBefore: now, calendar: calendar)
                        || task.isBigThree(on: now, calendar: calendar)
                }
                .sorted { a, b in
                    let aBig = a.isBigThree(on: now, calendar: calendar)
                    let bBig = b.isBigThree(on: now, calendar: calendar)
                    if aBig != bBig { return aBig }
                    if a.status == .inProgress, b.status != .inProgress { return true }
                    if b.status == .inProgress, a.status != .inProgress { return false }
                    return Self.priorityThenOrder(a, b)
                }
        case .inbox, .next, .someday, .inProgress:
            let status: TaskStatus
            switch list {
            case .inbox: status = .inbox
            case .next: status = .next
            case .someday: status = .someday
            default: status = .inProgress
            }
            return topLevel.filter { $0.status == status }.sorted(by: Self.manualOrder)
        case .completed:
            return topLevel.filter { $0.status == .completed }.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        case .archived:
            return topLevel.filter { $0.status == .archived }.sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }
        case let .project(name):
            return topLevel
                .filter { $0.project?.caseInsensitiveCompare(name) == .orderedSame && $0.status != .archived }
                .sorted { a, b in
                    if a.isOpen != b.isOpen { return a.isOpen }
                    return Self.priorityThenOrder(a, b)
                }
        case let .search(query):
            return search(query)
        }
    }

    /// Case- and diacritic-insensitive search over title, notes, definition of done,
    /// completion note, project and tags. Every whitespace-separated term must match.
    /// A term starting with `#` matches tags only. Archived tasks are included last.
    public func search(_ query: String) -> [TaskItem] {
        let terms = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !terms.isEmpty else { return [] }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return tasks.filter { task in
            terms.allSatisfy { term in
                if term.hasPrefix("#"), term.count > 1 {
                    let tag = String(term.dropFirst())
                    return task.tags.contains { $0.range(of: tag, options: options) != nil }
                }
                let fields = [task.title, task.notes ?? "", task.definitionOfDone ?? "", task.completionNote ?? "", task.project ?? ""] + task.tags
                return fields.contains { $0.range(of: term, options: options) != nil }
            }
        }
        .sorted { a, b in
            if (a.status == .archived) != (b.status == .archived) { return b.status == .archived }
            if a.isOpen != b.isOpen { return a.isOpen }
            return a.updatedAt > b.updatedAt
        }
    }

    public func bigThree(on day: Date) -> [TaskItem] {
        tasks.filter { $0.isBigThree(on: day, calendar: calendar) }.sorted(by: Self.manualOrder)
    }

    /// Sum of estimates for open tasks in Today (a rough planning aid).
    public func plannedMinutes(today now: Date) -> (minutes: Int, unestimated: Int) {
        let list = tasks(in: .today, now: now)
        let minutes = list.compactMap(\.estimatedMinutes).reduce(0, +)
        return (minutes, list.filter { $0.estimatedMinutes == nil }.count)
    }

    // MARK: Create / edit

    @discardableResult
    public func add(_ draft: TaskDraft, at now: Date) throws -> TaskItem {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw TaskError.emptyTitle }
        if let parentID = draft.parentID, task(parentID) == nil { throw TaskError.notFound }
        var task = TaskItem(
            title: title,
            status: draft.status,
            priority: draft.priority,
            createdAt: now,
            notes: Self.clean(draft.notes),
            definitionOfDone: Self.clean(draft.definitionOfDone),
            dueAt: draft.dueAt,
            estimatedMinutes: draft.estimatedMinutes.map { max(1, $0) },
            project: Self.clean(draft.project),
            tags: Self.normalizedTags(draft.tags),
            parentID: draft.parentID,
            sortOrder: nextSortOrder()
        )
        if task.status == .completed {
            task.completedAt = now
            task.previousStatus = .inbox
        }
        tasks.append(task)
        return task
    }

    /// Applies `change` and bumps `updatedAt`. Title can't become empty; creation
    /// metadata and identity can't be changed through here.
    @discardableResult
    public func update(_ id: UUID, at now: Date, _ change: (inout TaskItem) -> Void) -> TaskItem? {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return nil }
        let original = tasks[index]
        var task = original
        change(&task)
        task.id = original.id
        task.createdAt = original.createdAt
        task.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if task.title.isEmpty { task.title = original.title }
        task.tags = Self.normalizedTags(task.tags)
        if task.parentID != original.parentID, let parent = task.parentID, wouldCreateCycle(child: id, parent: parent) {
            task.parentID = original.parentID
        }
        guard task != original else { return task }
        task.updatedAt = now
        tasks[index] = task
        return task
    }

    @discardableResult
    public func setParent(_ id: UUID, parent: UUID?, at now: Date) throws -> TaskItem {
        guard task(id) != nil else { throw TaskError.notFound }
        if let parent {
            guard task(parent) != nil else { throw TaskError.notFound }
            if wouldCreateCycle(child: id, parent: parent) { throw TaskError.parentCycle }
        }
        guard let updated = update(id, at: now, { $0.parentID = parent }) else { throw TaskError.notFound }
        return updated
    }

    @discardableResult
    public func duplicate(_ id: UUID, at now: Date) -> TaskItem? {
        guard let original = task(id) else { return nil }
        var copy = original
        copy.id = UUID()
        copy.title = original.title + " (copy)"
        copy.createdAt = now
        copy.updatedAt = now
        copy.completedAt = nil
        copy.archivedAt = nil
        copy.completionNote = nil
        copy.progressNotes = []
        copy.bigThreeDay = nil
        copy.seriesID = nil
        if !copy.status.isOpen { copy.status = original.previousStatus ?? .inbox }
        copy.previousStatus = nil
        copy.sortOrder = original.sortOrder + 0.5
        tasks.append(copy)
        return copy
    }

    public func move(_ ids: [UUID], to status: TaskStatus, at now: Date) {
        for id in ids {
            update(id, at: now) { task in
                guard task.status != status else { return }
                if status == .completed {
                    task.previousStatus = task.status
                    task.completedAt = now
                } else if status == .archived {
                    task.previousStatus = task.status
                    task.archivedAt = now
                } else {
                    task.completedAt = nil
                    task.archivedAt = nil
                }
                task.status = status
            }
        }
    }

    /// Reorders tasks to match `orderedIDs` (e.g. after drag and drop).
    public func reorder(_ orderedIDs: [UUID], at now: Date) {
        for (offset, id) in orderedIDs.enumerated() {
            update(id, at: now) { $0.sortOrder = Double(offset) }
        }
    }

    public func setBigThree(_ id: UUID, enabled: Bool, on day: Date, at now: Date) throws {
        guard let task = task(id) else { throw TaskError.notFound }
        if enabled {
            if task.isBigThree(on: day, calendar: calendar) { return }
            if bigThree(on: day).filter(\.isOpen).count >= Self.bigThreeLimit { throw TaskError.bigThreeFull }
            update(id, at: now) {
                $0.bigThreeDay = self.calendar.startOfDay(for: day)
                if $0.status == .inbox || $0.status == .next || $0.status == .someday { $0.status = .today }
            }
        } else {
            update(id, at: now) { $0.bigThreeDay = nil }
        }
    }

    @discardableResult
    public func addProgressNote(_ id: UUID, text: String, sessionID: UUID?, at now: Date) -> TaskItem? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return task(id) }
        return update(id, at: now) { $0.progressNotes.append(ProgressNote(createdAt: now, text: trimmed, sessionID: sessionID)) }
    }

    // MARK: Lifecycle

    /// Completes a task ("Flow Finish"). Completing twice is a no-op that returns nil,
    /// so duplicate clicks can't create duplicate recurrences.
    @discardableResult
    public func complete(_ id: UUID, note: String? = nil, at now: Date) -> TaskCompletion? {
        guard let original = task(id), original.isOpen else { return nil }
        let previous = original.status
        guard let completed = update(id, at: now, { task in
            task.previousStatus = task.status
            task.status = .completed
            task.completedAt = now
            task.completionNote = Self.clean(note) ?? task.completionNote
        }) else { return nil }
        let spawned = spawnNextOccurrence(of: completed, at: now)
        return TaskCompletion(task: completed, previousStatus: previous, spawnedInstanceID: spawned?.id)
    }

    /// Reverts a completion. A recurrence instance created by it is removed if it
    /// hasn't been edited since.
    public func undo(_ completion: TaskCompletion, at now: Date) {
        if let spawnedID = completion.spawnedInstanceID, let spawned = task(spawnedID), spawned.updatedAt == spawned.createdAt {
            tasks.removeAll { $0.id == spawnedID }
        }
        update(completion.task.id, at: now) { task in
            task.status = completion.previousStatus
            task.previousStatus = nil
            task.completedAt = nil
            task.completionNote = completion.task.completionNote == task.completionNote ? nil : task.completionNote
        }
    }

    /// Reopens a completed or archived task into the list it came from.
    public func reopen(_ id: UUID, at now: Date) {
        update(id, at: now) { task in
            guard !task.isOpen else { return }
            let target = task.previousStatus.flatMap { $0.isOpen ? $0 : nil } ?? .inbox
            task.status = target == .inProgress ? .today : target
            task.previousStatus = nil
            task.completedAt = nil
            task.archivedAt = nil
        }
    }

    /// Archiving is the safe default; it hides tasks without deleting history.
    public func archive(_ ids: [UUID], at now: Date) {
        for id in ids + ids.flatMap { descendants(of: $0) } {
            update(id, at: now) { task in
                guard task.status != .archived else { return }
                task.previousStatus = task.status
                task.status = .archived
                task.archivedAt = now
            }
        }
    }

    public func restore(_ ids: [UUID], at now: Date) {
        for id in ids + ids.flatMap { descendants(of: $0) } {
            update(id, at: now) { task in
                guard task.status == .archived else { return }
                task.status = task.previousStatus ?? .inbox
                task.previousStatus = .archived
                task.archivedAt = nil
                if task.status == .completed, task.completedAt == nil { task.completedAt = now }
            }
        }
    }

    /// Permanently deletes tasks and their subtasks. Returns what was removed (for undo).
    @discardableResult
    public func delete(_ ids: [UUID]) -> [TaskItem] {
        let doomed = Set(ids + ids.flatMap { descendants(of: $0) })
        let removed = tasks.filter { doomed.contains($0.id) }
        tasks.removeAll { doomed.contains($0.id) }
        return removed
    }

    /// Puts back tasks removed by `delete`.
    public func reinsert(_ removed: [TaskItem]) {
        let existing = Set(tasks.map(\.id))
        tasks.append(contentsOf: removed.filter { !existing.contains($0.id) })
    }

    public func replaceAll(_ newTasks: [TaskItem]) {
        tasks = newTasks
    }

    /// Makes sure every recurring series whose latest instance is finished has its
    /// next open instance. Idempotent: running it again (e.g. after relaunch) never
    /// creates duplicates.
    @discardableResult
    public func ensureRecurringInstances(at now: Date) -> [TaskItem] {
        var created: [TaskItem] = []
        let series = Dictionary(grouping: tasks.filter { $0.recurrence != nil }) { $0.seriesID ?? $0.id }
        for (_, members) in series {
            guard !members.contains(where: \.isOpen) else { continue }
            guard let latest = members.filter({ $0.status == .completed }).max(by: { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }) else { continue }
            if let spawned = spawnNextOccurrence(of: latest, at: now) { created.append(spawned) }
        }
        return created
    }

    // MARK: Helpers

    private func spawnNextOccurrence(of task: TaskItem, at now: Date) -> TaskItem? {
        guard let rule = task.recurrence else { return nil }
        let seriesID = task.seriesID ?? task.id
        // Idempotency: one open instance per series.
        if tasks.contains(where: { ($0.seriesID ?? $0.id) == seriesID && $0.isOpen && $0.id != task.id }) { return nil }
        if task.seriesID == nil {
            update(task.id, at: now) { $0.seriesID = seriesID }
        }
        let anchor = task.dueAt ?? calendar.startOfDay(for: task.completedAt ?? now).addingTimeInterval(9 * 3600)
        var nextDue = rule.nextDate(after: anchor, calendar: calendar)
        // Don't create an instance that's already overdue: catch up to today.
        let startOfToday = calendar.startOfDay(for: now)
        var guardCount = 0
        while nextDue < startOfToday && guardCount < 1000 {
            nextDue = rule.nextDate(after: nextDue, calendar: calendar)
            guardCount += 1
        }
        var next = TaskItem(
            title: task.title,
            status: calendar.isDate(nextDue, inSameDayAs: now) ? .today : .next,
            priority: task.priority,
            createdAt: now,
            notes: task.notes,
            definitionOfDone: task.definitionOfDone,
            dueAt: nextDue,
            estimatedMinutes: task.estimatedMinutes,
            project: task.project,
            tags: task.tags,
            parentID: task.parentID,
            sortOrder: task.sortOrder
        )
        next.recurrence = rule
        next.seriesID = seriesID
        next.isPrivate = task.isPrivate
        next.link = task.link
        tasks.append(next)
        return next
    }

    private func descendants(of id: UUID) -> [UUID] {
        var result: [UUID] = []
        var frontier = [id]
        var seen: Set<UUID> = [id]
        while let current = frontier.popLast() {
            for child in tasks where child.parentID == current && !seen.contains(child.id) {
                seen.insert(child.id)
                result.append(child.id)
                frontier.append(child.id)
            }
        }
        return result
    }

    private func wouldCreateCycle(child: UUID, parent: UUID) -> Bool {
        if child == parent { return true }
        return descendants(of: child).contains(parent)
    }

    private func nextSortOrder() -> Double {
        (tasks.map(\.sortOrder).max() ?? 0) + 1
    }

    static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in tags {
            let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#")).lowercased()
            guard !tag.isEmpty, !seen.contains(tag) else { continue }
            seen.insert(tag)
            result.append(tag)
        }
        return result
    }

    static func manualOrder(_ a: TaskItem, _ b: TaskItem) -> Bool {
        a.sortOrder == b.sortOrder ? a.createdAt < b.createdAt : a.sortOrder < b.sortOrder
    }

    static func priorityThenOrder(_ a: TaskItem, _ b: TaskItem) -> Bool {
        if a.priority != b.priority { return a.priority > b.priority }
        return manualOrder(a, b)
    }
}

/// In-memory task store for tests and previews.
public final class InMemoryTaskStore: TaskPersisting {
    public var tasks: [TaskItem]
    public var failWrites = false

    public init(tasks: [TaskItem] = []) { self.tasks = tasks }

    public func loadTasks() throws -> [TaskItem] { tasks }

    public func saveTasks(_ tasks: [TaskItem]) throws {
        if failWrites { throw PersistenceError.unwritable(file: "tasks.json", underlying: "test") }
        self.tasks = tasks
    }
}

extension JSONFileStore: TaskPersisting {
    public var tasksURL: URL { directory.appendingPathComponent("tasks.json") }

    public func loadTasks() throws -> [TaskItem] {
        try readFile([TaskItem].self, from: tasksURL) ?? []
    }

    public func saveTasks(_ tasks: [TaskItem]) throws {
        try writeFile(tasks, to: tasksURL)
    }
}
