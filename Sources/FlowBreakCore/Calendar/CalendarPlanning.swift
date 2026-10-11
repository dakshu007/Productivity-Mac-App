import Foundation

/// A busy stretch from the user's calendar (only the time and a title are kept,
/// in memory; nothing from the calendar is stored by FlowBreak).
public struct BusyBlock: Equatable, Sendable {
    public var title: String
    public var interval: DateInterval

    public init(title: String, interval: DateInterval) {
        self.title = title
        self.interval = interval
    }
}

/// Calendar-aware planning helpers. Pure functions, so they're unit tested.
public enum CalendarPlanning {
    /// Overlapping or touching intervals merged, sorted by start.
    public static func merged(_ intervals: [DateInterval]) -> [DateInterval] {
        let sorted = intervals.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
        var result: [DateInterval] = []
        for interval in sorted {
            if let last = result.last, interval.start <= last.end {
                result[result.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                result.append(interval)
            }
        }
        return result
    }

    /// The meeting happening at `now`, if any.
    public static func current(_ blocks: [BusyBlock], at now: Date) -> BusyBlock? {
        blocks.filter { $0.interval.start <= now && now < $0.interval.end }.min { $0.interval.end < $1.interval.end }
    }

    /// The next meeting starting after `now`.
    public static func next(_ blocks: [BusyBlock], after now: Date) -> BusyBlock? {
        blocks.filter { $0.interval.start > now }.min { $0.interval.start < $1.interval.start }
    }

    /// Minutes not covered by meetings between `now` and `end`.
    public static func freeMinutes(_ blocks: [BusyBlock], from now: Date, until end: Date) -> Int {
        guard end > now else { return 0 }
        let window = DateInterval(start: now, end: end)
        let busy = merged(blocks.map(\.interval)).reduce(0.0) { total, interval in
            guard let overlap = interval.intersection(with: window) else { return total }
            return total + overlap.duration
        }
        return max(0, Int((window.duration - busy) / 60))
    }

    /// The first meeting that would overlap a session starting at `start`.
    public static func firstConflict(_ blocks: [BusyBlock], start: Date, duration: TimeInterval) -> BusyBlock? {
        let session = DateInterval(start: start, duration: max(1, duration))
        return blocks
            .filter { $0.interval.start < session.end && $0.interval.end > session.start }
            .min { $0.interval.start < $1.interval.start }
    }
}
