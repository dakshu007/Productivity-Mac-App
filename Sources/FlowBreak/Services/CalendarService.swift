import EventKit
import FlowBreakCore
import Foundation

struct CalendarInfo: Identifiable, Hashable {
    var id: String
    var title: String
    var source: String
    var allowsWriting: Bool
    var color: CGColor?

    static func == (lhs: CalendarInfo, rhs: CalendarInfo) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum CalendarAccess: Equatable {
    case notDetermined
    case granted
    case denied
    /// macOS 14+ "add events only" access: FlowBreak can schedule blocks but can't see meetings.
    case writeOnly
}

/// Reads meeting times (and, on request, adds focus blocks) through EventKit.
/// Only used when the user turns on calendar awareness. Event details stay in
/// memory; FlowBreak stores nothing from the calendar.
@MainActor
final class CalendarService {
    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    var onChange: (() -> Void)?

    init() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onChange?() }
        }
    }

    var access: CalendarAccess {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .denied
        case .authorized: return .granted
        default:
            // macOS 14 adds .fullAccess (same value as .authorized) and .writeOnly.
            return status.rawValue == 4 ? .writeOnly : .granted
        }
    }

    func requestAccess() async -> CalendarAccess {
        do {
            if #available(macOS 14.0, *) {
                _ = try await store.requestFullAccessToEvents()
            } else {
                _ = try await store.requestAccess(to: .event)
            }
        } catch {
            Log.app.error("Calendar access request failed: \(error.localizedDescription, privacy: .public)")
        }
        store.reset()
        return access
    }

    func calendars() -> [CalendarInfo] {
        guard access == .granted || access == .writeOnly else { return [] }
        return store.calendars(for: .event)
            .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title, source: $0.source.title, allowsWriting: $0.allowsContentModifications, color: $0.cgColor) }
            .sorted { ($0.source, $0.title) < ($1.source, $1.title) }
    }

    /// Busy times between `start` and `end`. All-day events, events marked "free",
    /// cancelled events and invitations you declined don't count as busy.
    func busyBlocks(from start: Date, to end: Date, calendarIDs: [String]) -> [BusyBlock] {
        guard access == .granted else { return [] }
        let all = store.calendars(for: .event)
        let chosen = calendarIDs.isEmpty ? all : all.filter { calendarIDs.contains($0.calendarIdentifier) }
        guard !chosen.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: chosen)
        return store.events(matching: predicate)
            .filter { event in
                guard !event.isAllDay, event.availability != .free, event.status != .canceled else { return false }
                if let me = event.attendees?.first(where: { $0.isCurrentUser }), me.participantStatus == .declined { return false }
                return event.endDate > event.startDate
            }
            .map { BusyBlock(title: $0.title ?? "Busy", interval: DateInterval(start: $0.startDate, end: $0.endDate)) }
    }

    /// Adds a focus block to a calendar. Returns an error message on failure.
    func addFocusBlock(title: String, notes: String?, start: Date, duration: TimeInterval, calendarID: String?) -> String? {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.notes = notes
        event.startDate = start
        event.endDate = start.addingTimeInterval(duration)
        event.availability = .busy
        if let calendarID, let calendar = store.calendar(withIdentifier: calendarID), calendar.allowsContentModifications {
            event.calendar = calendar
        } else if let calendar = store.defaultCalendarForNewEvents {
            event.calendar = calendar
        } else {
            return "No calendar is available for new events."
        }
        do {
            try store.save(event, span: .thisEvent, commit: true)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
