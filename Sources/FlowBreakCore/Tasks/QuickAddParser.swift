import Foundation

/// Parses quick-add text such as
/// `Review MyKavo SEO tomorrow #marketing !high 30m +Website`.
///
/// Recognised tokens (everything else stays in the title):
/// - `#tag` — a tag.
/// - `!low`, `!normal`, `!high`, `!critical` (also `!urgent`, `!!` = high, `!!!` = critical).
/// - `+Project` — project name (one word; use `-` or `_` for spaces, they become spaces).
/// - `30m`, `45min`, `1h`, `1.5h`, `1h30m` — estimate.
/// - `today`, `tonight`, `tomorrow`, `tmr`, `2026-10-15`, `in 3 days`, `in 2 weeks`, `next week`.
/// - Weekday names (`fri`, `friday`) only after `on`/`by`/`due`/`next` or as the last word,
///   so "Review Monday report" keeps "Monday" in the title.
/// - `@today`, `@next`, `@someday`, `@inbox` — which list to put the task in.
///
/// The result lists every interpreted token so the UI can preview it before saving.
public struct QuickAddParser {
    public struct Token: Equatable, Sendable {
        public enum Kind: String, Sendable { case tag, priority, project, estimate, due, list }
        public var kind: Kind
        public var source: String
        public var display: String
    }

    public struct Result: Equatable, Sendable {
        public var title: String
        public var tags: [String] = []
        public var priority: TaskPriority?
        public var project: String?
        public var estimatedMinutes: Int?
        public var dueAt: Date?
        public var status: TaskStatus?
        public var tokens: [Token] = []

        public func draft(defaultStatus: TaskStatus, calendar: Calendar, now: Date) -> TaskDraft {
            var status = self.status ?? defaultStatus
            if self.status == nil, status == .inbox, let dueAt, calendar.isDate(dueAt, inSameDayAs: now) || dueAt < now {
                status = .today
            }
            return TaskDraft(
                title: title,
                status: status,
                priority: priority ?? .normal,
                dueAt: dueAt,
                estimatedMinutes: estimatedMinutes,
                project: project,
                tags: tags
            )
        }
    }

    public var calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    private static let weekdays: [String: Int] = [
        "sun": 1, "sunday": 1, "mon": 2, "monday": 2, "tue": 3, "tues": 3, "tuesday": 3,
        "wed": 4, "wednesday": 4, "thu": 5, "thur": 5, "thurs": 5, "thursday": 5,
        "fri": 6, "friday": 6, "sat": 7, "saturday": 7,
    ]
    private static let dateConnectors: Set<String> = ["on", "by", "due"]

    public func parse(_ text: String, now: Date) -> Result {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var keep = Array(repeating: true, count: words.count)
        var result = Result(title: "")
        let today = calendar.startOfDay(for: now)

        func consume(_ indices: [Int], _ kind: Token.Kind, display: String) {
            for i in indices { keep[i] = false }
            // A preceding "on"/"by"/"due" belongs to the date.
            if kind == .due, let first = indices.min(), first > 0, Self.dateConnectors.contains(words[first - 1].lowercased()), keep[first - 1] {
                keep[first - 1] = false
            }
            result.tokens.append(Token(kind: kind, source: indices.map { words[$0] }.joined(separator: " "), display: display))
        }

        var i = 0
        while i < words.count {
            let word = words[i]
            let lower = word.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",.;"))

            if lower.hasPrefix("#"), lower.count > 1 {
                let tag = String(lower.dropFirst())
                if !result.tags.contains(tag) { result.tags.append(tag) }
                consume([i], .tag, display: "#\(tag)")
            } else if let priority = Self.priority(lower), result.priority == nil {
                result.priority = priority
                consume([i], .priority, display: "\(priority.displayName) priority")
            } else if lower.hasPrefix("+"), word.count > 1, result.project == nil {
                let name = String(word.dropFirst()).replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
                result.project = name
                consume([i], .project, display: "Project: \(name)")
            } else if lower.hasPrefix("@"), let status = Self.list(lower), result.status == nil {
                result.status = status
                consume([i], .list, display: "List: \(status.displayName)")
            } else if let minutes = Self.estimate(lower), result.estimatedMinutes == nil {
                result.estimatedMinutes = minutes
                consume([i], .estimate, display: "Estimate: \(Self.formatMinutes(minutes))")
            } else if result.dueAt == nil, let due = dueDate(words: words, at: i, today: today) {
                let (date, used) = due
                result.dueAt = date
                consume(Array(i..<(i + used)), .due, display: "Due: \(Self.formatDay(date, now: now, calendar: calendar))")
                i += used
                continue
            }
            i += 1
        }

        let title = zip(words, keep).filter { $0.1 }.map { $0.0 }.joined(separator: " ")
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Nothing left for a title: don't interpret anything.
            return Result(title: text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        result.title = title
        return result
    }

    // MARK: Token recognisers

    static func priority(_ word: String) -> TaskPriority? {
        switch word {
        case "!low", "!p4": return .low
        case "!normal", "!p3": return .normal
        case "!high", "!!", "!p2": return .high
        case "!critical", "!urgent", "!!!", "!p1": return .critical
        default: return nil
        }
    }

    static func list(_ word: String) -> TaskStatus? {
        switch word {
        case "@today": return .today
        case "@next": return .next
        case "@someday": return .someday
        case "@inbox": return .inbox
        default: return nil
        }
    }

    static func estimate(_ word: String) -> Int? {
        let scanner = Scanner(string: word)
        scanner.charactersToBeSkipped = nil
        var total: Double = 0
        var matched = false
        while !scanner.isAtEnd {
            guard let value = scanner.scanDouble(), value >= 0 else { return nil }
            if scanner.scanString("hrs") != nil || scanner.scanString("hr") != nil || scanner.scanString("h") != nil {
                total += value * 60
            } else if scanner.scanString("mins") != nil || scanner.scanString("min") != nil || scanner.scanString("m") != nil {
                total += value
            } else {
                return nil
            }
            matched = true
        }
        guard matched else { return nil }
        let minutes = Int(total.rounded())
        return (1...24 * 60).contains(minutes) ? minutes : nil
    }

    func dueDate(words: [String], at index: Int, today: Date) -> (Date, Int)? {
        let lower = words.map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",.;")) }
        let word = lower[index]
        switch word {
        case "today", "tonight":
            return (today, 1)
        case "tomorrow", "tmr", "tmrw":
            return (calendar.date(byAdding: .day, value: 1, to: today) ?? today, 1)
        default:
            break
        }
        if word == "next", index + 1 < lower.count {
            if lower[index + 1] == "week" {
                // Next Monday (or the user's first weekday).
                let target = calendar.firstWeekday == 1 ? 2 : calendar.firstWeekday
                return (nextWeekday(target, after: today, skipThisWeek: true), 2)
            }
            if let weekday = Self.weekdays[lower[index + 1]] {
                return (nextWeekday(weekday, after: today, skipThisWeek: false), 2)
            }
        }
        if word == "in", index + 2 < lower.count, let n = Int(lower[index + 1]), (1...365).contains(n) {
            let unit = lower[index + 2]
            if ["day", "days"].contains(unit) { return (calendar.date(byAdding: .day, value: n, to: today) ?? today, 3) }
            if ["week", "weeks"].contains(unit) { return (calendar.date(byAdding: .day, value: 7 * n, to: today) ?? today, 3) }
        }
        if let weekday = Self.weekdays[word] {
            let previous = index > 0 ? lower[index - 1] : ""
            let isLast = index == lower.count - 1
            if isLast || Self.dateConnectors.contains(previous) {
                return (nextWeekday(weekday, after: today, skipThisWeek: false), 1)
            }
        }
        let parts = word.split(separator: "-").compactMap { Int($0) }
        if word.count == 10, parts.count == 3,
           let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
           calendar.component(.day, from: date) == parts[2] {
            return (calendar.startOfDay(for: date), 1)
        }
        return nil
    }

    /// The next date with `weekday` strictly after `day` (or, with `skipThisWeek`,
    /// in the following week).
    func nextWeekday(_ weekday: Int, after day: Date, skipThisWeek: Bool) -> Date {
        var candidate = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        for _ in 0..<14 {
            if calendar.component(.weekday, from: candidate) == weekday {
                if !skipThisWeek || !calendar.isDate(candidate, equalTo: day, toGranularity: .weekOfYear) {
                    return candidate
                }
            }
            candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        }
        return candidate
    }

    public static func formatMinutes(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }

    public static func formatDay(_ date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return formatter.string(from: date)
    }
}
