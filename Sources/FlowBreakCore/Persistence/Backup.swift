import Foundation

/// A complete, versioned FlowBreak backup / JSON export.
public struct BackupFile: Codable, Equatable {
    public var formatVersion: Int
    public var app: String
    public var exportedAt: Date
    public var sessions: [FocusSession]
    public var tasks: [TaskItem]
    public var usage: [UsageSample]
    public var reflections: [WeeklyReflection]
    public var settings: AppSettings?

    private enum CodingKeys: String, CodingKey {
        case formatVersion, app, exportedAt, sessions, tasks, usage, reflections, settings
    }

    public init(exportedAt: Date, sessions: [FocusSession], tasks: [TaskItem], usage: [UsageSample], reflections: [WeeklyReflection], settings: AppSettings?) {
        self.formatVersion = BackupService.formatVersion
        self.app = "FlowBreak"
        self.exportedAt = exportedAt
        self.sessions = sessions
        self.tasks = tasks
        self.usage = usage
        self.reflections = reflections
        self.settings = settings
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Version-0 exports (before tasks existed) had no formatVersion.
        formatVersion = try c.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 0
        app = try c.decode(String.self, forKey: .app)
        exportedAt = try c.decode(Date.self, forKey: .exportedAt)
        sessions = try c.decodeIfPresent([FocusSession].self, forKey: .sessions) ?? []
        tasks = try c.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
        usage = try c.decodeIfPresent([UsageSample].self, forKey: .usage) ?? []
        reflections = try c.decodeIfPresent([WeeklyReflection].self, forKey: .reflections) ?? []
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings)
    }
}

public struct BackupPreview: Equatable, Sendable {
    public var exportedAt: Date
    public var formatVersion: Int
    public var sessionCount: Int
    public var taskCount: Int
    public var usageCount: Int
    public var reflectionCount: Int
    public var includesSettings: Bool
    /// Problems that were repaired during validation (shown before restoring).
    public var warnings: [String]
}

public enum BackupError: Error, LocalizedError, Equatable {
    case notABackup(String)
    case newerVersion(Int)
    case duplicateIDs(String)

    public var errorDescription: String? {
        switch self {
        case let .notABackup(reason): return "This file isn't a FlowBreak backup. (\(reason))"
        case let .newerVersion(version): return "This backup was made by a newer FlowBreak (format \(version)). Update FlowBreak to restore it."
        case let .duplicateIDs(what): return "This backup contains duplicate \(what) and can't be restored safely."
        }
    }
}

public enum BackupService {
    public static let formatVersion = 1

    public static func encode(_ backup: BackupFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601WithFractionalSeconds
        return try encoder.encode(backup)
    }

    /// Decodes and checks a backup without changing anything. Returns a repaired copy
    /// (active sessions closed as interrupted, invalid parent links removed) and a
    /// preview to show the user before they confirm.
    public static func validate(_ data: Data, now: Date = Date()) throws -> (BackupFile, BackupPreview) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
        var backup: BackupFile
        do {
            backup = try decoder.decode(BackupFile.self, from: data)
        } catch {
            throw BackupError.notABackup("unreadable JSON")
        }
        guard backup.app == "FlowBreak" else { throw BackupError.notABackup("wrong app") }
        guard backup.formatVersion <= formatVersion else { throw BackupError.newerVersion(backup.formatVersion) }
        if Set(backup.sessions.map(\.id)).count != backup.sessions.count { throw BackupError.duplicateIDs("sessions") }
        if Set(backup.tasks.map(\.id)).count != backup.tasks.count { throw BackupError.duplicateIDs("tasks") }

        var warnings: [String] = []

        var interrupted = 0
        for index in backup.sessions.indices where backup.sessions[index].status.isActive {
            var session = backup.sessions[index]
            let end = session.segments.last?.end ?? session.segments.last?.start ?? session.startedAt
            if var last = session.segments.popLast() {
                last.end = last.end ?? last.start
                session.segments.append(last)
            }
            session.status = .interrupted
            session.deadline = nil
            session.remainingAtPause = nil
            session.endedAt = end
            session.actualDuration = session.activeDuration(asOf: end)
            backup.sessions[index] = session
            interrupted += 1
        }
        if interrupted > 0 { warnings.append("\(interrupted) session(s) that were running when the backup was made will be marked interrupted.") }

        let ids = Set(backup.tasks.map(\.id))
        var fixedParents = 0
        for index in backup.tasks.indices {
            guard let parent = backup.tasks[index].parentID else { continue }
            if !ids.contains(parent) || hasCycle(start: backup.tasks[index].id, tasks: backup.tasks) {
                backup.tasks[index].parentID = nil
                fixedParents += 1
            }
        }
        if fixedParents > 0 { warnings.append("\(fixedParents) subtask link(s) were invalid and will be removed.") }

        let future = backup.sessions.filter { $0.startedAt > now.addingTimeInterval(86_400) }.count
        if future > 0 { warnings.append("\(future) session(s) are dated in the future. Check your Mac's clock.") }
        if backup.formatVersion == 0 { warnings.append("This is an older export without tasks.") }

        let preview = BackupPreview(
            exportedAt: backup.exportedAt,
            formatVersion: backup.formatVersion,
            sessionCount: backup.sessions.count,
            taskCount: backup.tasks.count,
            usageCount: backup.usage.count,
            reflectionCount: backup.reflections.count,
            includesSettings: backup.settings != nil,
            warnings: warnings
        )
        return (backup, preview)
    }

    private static func hasCycle(start: UUID, tasks: [TaskItem]) -> Bool {
        let parents = Dictionary(tasks.map { ($0.id, $0.parentID) }, uniquingKeysWith: { a, _ in a })
        var seen: Set<UUID> = [start]
        var current = parents[start] ?? nil
        while let id = current {
            if seen.contains(id) { return true }
            seen.insert(id)
            current = parents[id] ?? nil
        }
        return false
    }
}

// MARK: - Task import / export

public enum TaskExporter {
    public static func csv(_ tasks: [TaskItem]) -> String {
        var lines = ["id,title,status,priority,project,tags,due,estimate_minutes,created_at,completed_at,definition_of_done,completion_note,parent_id"]
        for t in tasks.sorted(by: { $0.createdAt < $1.createdAt }) {
            let fields: [String] = [
                t.id.uuidString,
                t.title,
                t.status.rawValue,
                t.priority.displayName.lowercased(),
                t.project ?? "",
                t.tags.joined(separator: " "),
                t.dueAt.map { ISO8601.dateOnly.string(from: $0) } ?? "",
                t.estimatedMinutes.map(String.init) ?? "",
                ISO8601.plain.string(from: t.createdAt),
                t.completedAt.map { ISO8601.plain.string(from: $0) } ?? "",
                t.definitionOfDone ?? "",
                t.completionNote ?? "",
                t.parentID?.uuidString ?? "",
            ]
            lines.append(fields.map(DataExporter.escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Markdown grouped by list, with subtasks nested under their parents.
    public static func markdown(_ tasks: [TaskItem], title: String = "FlowBreak tasks") -> String {
        var lines = ["# \(title)", ""]
        let order: [TaskStatus] = [.inProgress, .today, .next, .inbox, .someday, .completed]
        for status in order {
            let group = tasks.filter { $0.status == status && $0.parentID == nil }
            guard !group.isEmpty else { continue }
            lines.append("## \(status.displayName)")
            for task in group.sorted(by: TaskRepository.manualOrder) {
                let subs = tasks.filter { $0.parentID == task.id && $0.status != .archived }
                lines.append(task.markdown(subtasks: subs))
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

public enum ChecklistImporter {
    public struct Item: Equatable, Sendable {
        public var title: String
        public var done: Bool
    }

    /// Reads a plain-text or Markdown checklist: `- [ ] item`, `- [x] item`,
    /// `* item`, `1. item`, or plain lines. Headings and blank lines are skipped.
    public static func parse(_ text: String) -> [Item] {
        var items: [Item] = []
        for rawLine in text.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix(">") else { continue }
            var done = false
            for prefix in ["- ", "* ", "+ "] where line.hasPrefix(prefix) {
                line = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                break
            }
            if let dot = line.firstIndex(of: "."), line[line.startIndex..<dot].allSatisfy(\.isNumber), !line[line.startIndex..<dot].isEmpty {
                line = String(line[line.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
            }
            let lower = line.lowercased()
            if lower.hasPrefix("[ ]") {
                line = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if lower.hasPrefix("[x]") {
                done = true
                line = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            }
            guard !line.isEmpty else { continue }
            items.append(Item(title: String(line.prefix(500)), done: done))
        }
        return items
    }
}
