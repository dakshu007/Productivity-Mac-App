import Foundation

/// Exports the user's local data. Nothing leaves the Mac unless the user saves
/// the exported file somewhere themselves.
public enum DataExporter {
    public struct Export: Codable {
        public var exportedAt: Date
        public var app: String
        public var sessions: [FocusSession]
        public var usage: [UsageSample]
    }

    public static func json(sessions: [FocusSession], usage: [UsageSample], now: Date = Date()) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601WithFractionalSeconds
        return try encoder.encode(Export(exportedAt: now, app: "FlowBreak", sessions: sessions, usage: usage))
    }

    public static func sessionsCSV(_ sessions: [FocusSession]) -> String {
        var lines = ["id,type,status,started_at,ended_at,planned_seconds,active_seconds,paused_seconds,follows_focus_id"]
        for s in sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            let fields: [String] = [
                s.id.uuidString,
                s.kind.rawValue,
                s.status.rawValue,
                ISO8601.plain.string(from: s.startedAt),
                s.endedAt.map { ISO8601.plain.string(from: $0) } ?? "",
                String(Int(s.plannedDuration.rounded())),
                String(Int((s.actualDuration ?? s.activeDuration(asOf: s.endedAt ?? Date())).rounded())),
                String(Int(s.accumulatedPause.rounded())),
                s.followsFocusID?.uuidString ?? "",
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func usageCSV(_ samples: [UsageSample]) -> String {
        var lines = ["app_name,bundle_id,start,end,seconds"]
        for s in samples.sorted(by: { $0.start < $1.start }) {
            let fields = [
                s.appName,
                s.bundleID,
                ISO8601.plain.string(from: s.start),
                ISO8601.plain.string(from: s.end),
                String(Int(s.duration.rounded())),
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func escape(_ field: String) -> String {
        var value = field
        // Neutralise spreadsheet formula injection from app names.
        if let first = value.first, "=+-@".contains(first) {
            value = "'" + value
        }
        if value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}

public enum DurationFormatter {
    /// "45:00", "1:05:09" — for countdowns.
    public static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.up)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// "2h 05m", "45m", "0m" — for summaries.
    public static func short(_ interval: TimeInterval) -> String {
        let totalMinutes = max(0, Int((interval / 60).rounded(.down)))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 { return String(format: "%dh %02dm", hours, minutes) }
        if totalMinutes == 0 && interval > 0 { return "<1m" }
        return "\(minutes)m"
    }
}
