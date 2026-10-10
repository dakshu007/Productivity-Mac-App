import Foundation
import FlowBreakCore
import UserNotifications

enum NotificationAuthorization: Equatable {
    case unknown
    case notDetermined
    case denied
    case authorized
    /// Running outside an app bundle (e.g. `swift run`), where macOS offers no notifications.
    case unavailable
}

enum NotificationAction: String {
    case takeBreak = "flowbreak.action.takeBreak"
    case snooze = "flowbreak.action.snooze"
    case dismiss = "flowbreak.action.dismiss"
    case startFocus = "flowbreak.action.startFocus"
    /// The user clicked the notification body.
    case open = "flowbreak.action.open"
}

/// Bridges UNUserNotificationCenter callbacks (delivered on arbitrary threads) to the main actor.
final class NotificationDelegateProxy: NSObject, UNUserNotificationCenterDelegate {
    var onAction: (@MainActor (NotificationAction) -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Menu-bar apps are often "active"; still show the banner.
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.actionIdentifier
        let action: NotificationAction?
        switch identifier {
        case UNNotificationDefaultActionIdentifier: action = .open
        case UNNotificationDismissActionIdentifier: action = nil
        default: action = NotificationAction(rawValue: identifier)
        }
        let handler = onAction
        if let action, let handler {
            Task { @MainActor in handler(action) }
        }
        completionHandler()
    }
}

/// Schedules FlowBreak's local notifications from a `ReminderPlanner` plan.
/// Every sync replaces FlowBreak's pending requests with the current plan, so
/// reminders are cancelled automatically when the state changes.
@MainActor
final class NotificationService {
    static let breakDueCategory = "flowbreak.category.breakDue"
    static let breakDoneCategory = "flowbreak.category.breakDone"

    private let proxy = NotificationDelegateProxy()
    private var center: UNUserNotificationCenter?
    private(set) var authorization: NotificationAuthorization = .unknown
    var onAuthorizationChange: ((NotificationAuthorization) -> Void)?

    init() {
        // UNUserNotificationCenter crashes when there is no bundle identifier.
        guard Bundle.main.bundleIdentifier != nil, Bundle.main.bundleURL.pathExtension == "app" else {
            authorization = .unavailable
            return
        }
        let center = UNUserNotificationCenter.current()
        self.center = center
        center.delegate = proxy
        let takeBreak = UNNotificationAction(identifier: NotificationAction.takeBreak.rawValue, title: "Take a break", options: [.foreground])
        let snooze = UNNotificationAction(identifier: NotificationAction.snooze.rawValue, title: "Snooze 5 min", options: [])
        let dismiss = UNNotificationAction(identifier: NotificationAction.dismiss.rawValue, title: "Dismiss", options: [])
        let startFocus = UNNotificationAction(identifier: NotificationAction.startFocus.rawValue, title: "Start focus", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.breakDueCategory, actions: [takeBreak, snooze, dismiss], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: Self.breakDoneCategory, actions: [startFocus], intentIdentifiers: [], options: []),
        ])
    }

    func setActionHandler(_ handler: @escaping @MainActor (NotificationAction) -> Void) {
        proxy.onAction = handler
    }

    func refreshAuthorization() {
        guard let center else { return }
        center.getNotificationSettings { settings in
            let status: NotificationAuthorization
            switch settings.authorizationStatus {
            case .authorized, .provisional: status = .authorized
            case .denied: status = .denied
            case .notDetermined: status = .notDetermined
            @unknown default: status = .denied
            }
            Task { @MainActor [weak self] in self?.update(status) }
        }
    }

    func requestAuthorization() {
        guard let center else { return }
        center.requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                Log.notifications.error("Authorization request failed: \(error.localizedDescription, privacy: .public)")
            }
            Task { @MainActor [weak self] in self?.refreshAuthorization() }
        }
    }

    private func update(_ status: NotificationAuthorization) {
        guard status != authorization else { return }
        authorization = status
        onAuthorizationChange?(status)
    }

    /// Replaces all pending FlowBreak reminders with `plan`.
    func sync(plan: [PlannedReminder], state: EngineState, soundEnabled: Bool) {
        guard let center else { return }
        let desired = plan
        let desiredIDs = Set(plan.map(\.id))
        center.getPendingNotificationRequests { requests in
            let stale = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(ReminderPlanner.identifierPrefix) && !desiredIDs.contains($0) }
            if !stale.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: stale)
            }
        }
        for reminder in desired {
            let request = UNNotificationRequest(
                identifier: reminder.id,
                content: content(for: reminder, soundEnabled: soundEnabled),
                trigger: trigger(for: reminder.date)
            )
            center.add(request) { error in
                if let error {
                    Log.notifications.error("Scheduling failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        // Once the break is handled, clear its banners from Notification Center.
        if state.phase != .breakDue {
            center.getDeliveredNotifications { delivered in
                let handled = delivered
                    .map(\.request.identifier)
                    .filter { $0.hasPrefix(ReminderPlanner.identifierPrefix + "due.") || $0.hasPrefix(ReminderPlanner.identifierPrefix + "snooze.") || $0.hasPrefix(ReminderPlanner.identifierPrefix + "away.") }
                if !handled.isEmpty {
                    center.removeDeliveredNotifications(withIdentifiers: handled)
                }
            }
        }
    }

    /// One catch-up notice when a session ended while the Mac slept or FlowBreak was closed.
    func postCatchUp(focusEnded: Bool, breakMinutes: Int, soundEnabled: Bool) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        if focusEnded {
            content.title = "Your focus session ended while you were away"
            content.body = "Take a \(breakMinutes)-minute break when you're ready."
            content.categoryIdentifier = Self.breakDueCategory
        } else {
            content.title = "Your break ended while you were away"
            content.body = "Start a new focus session when you're ready."
            content.categoryIdentifier = Self.breakDoneCategory
        }
        content.sound = soundEnabled ? .default : nil
        let request = UNNotificationRequest(identifier: ReminderPlanner.identifierPrefix + "away.\(UUID().uuidString)", content: content, trigger: nil)
        center.add(request, withCompletionHandler: nil)
    }

    func removeAll() {
        guard let center else { return }
        center.getPendingNotificationRequests { requests in
            let ours = requests.map(\.identifier).filter { $0.hasPrefix(ReminderPlanner.identifierPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)
        }
    }

    private func content(for reminder: PlannedReminder, soundEnabled: Bool) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        switch reminder.kind {
        case .focusEnded:
            content.title = "Time to reset"
            content.body = "Take a \(reminder.breakMinutes)-minute break."
            content.categoryIdentifier = Self.breakDueCategory
        case let .breakReminder(attempt):
            content.title = "Your break is still waiting"
            content.body = attempt <= 1
                ? "A \(reminder.breakMinutes)-minute pause helps you come back sharper."
                : "Step away for \(reminder.breakMinutes) minutes whenever you're ready."
            content.categoryIdentifier = Self.breakDueCategory
        case .breakEnded:
            content.title = "Break complete"
            content.body = "Ready to focus again?"
            content.categoryIdentifier = Self.breakDoneCategory
        }
        content.threadIdentifier = "flowbreak"
        content.sound = soundEnabled ? .default : nil
        return content
    }

    private func trigger(for date: Date) -> UNNotificationTrigger {
        // Calendar triggers are anchored to wall-clock time, so they still fire at the
        // right moment (or promptly after wake) if the Mac sleeps in between.
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }
}
