import Foundation

public enum TimerMode: String, Codable, CaseIterable, Sendable {
    case focus
    case pomodoro

    public var displayName: String {
        switch self {
        case .focus: return "Focus"
        case .pomodoro: return "Pomodoro"
        }
    }
}

/// Global keyboard shortcut choices. Off by default: FlowBreak never installs a
/// system-wide shortcut unless the user picks one.
public enum ShortcutPreset: String, Codable, CaseIterable, Sendable {
    case off
    case optionCommandT
    case controlOptionT
    case controlOptionSpace
    case optionCommandP
    case controlOptionP
    case optionCommandY
    case controlOptionY

    public var displayName: String {
        switch self {
        case .off: return "Off"
        case .optionCommandT: return "⌥⌘T"
        case .controlOptionT: return "⌃⌥T"
        case .controlOptionSpace: return "⌃⌥Space"
        case .optionCommandP: return "⌥⌘P"
        case .controlOptionP: return "⌃⌥P"
        case .optionCommandY: return "⌥⌘Y"
        case .controlOptionY: return "⌃⌥Y"
        }
    }

    public static let quickAddChoices: [ShortcutPreset] = [.off, .optionCommandT, .controlOptionT, .controlOptionSpace]
    public static let focusChoices: [ShortcutPreset] = [.off, .optionCommandP, .controlOptionP]
    public static let todayChoices: [ShortcutPreset] = [.off, .optionCommandY, .controlOptionY]
}

/// Quiet hours, expressed as minutes after local midnight. May wrap past midnight.
public struct QuietHours: Codable, Equatable, Sendable {
    public var startMinute: Int
    public var endMinute: Int

    public init(startMinute: Int, endMinute: Int) {
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    public func contains(_ date: Date, calendar: Calendar) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if startMinute == endMinute { return false }
        if startMinute < endMinute {
            return minute >= startMinute && minute < endMinute
        }
        return minute >= startMinute || minute < endMinute
    }
}

/// All user preferences. Every field decodes with a default so older saved
/// settings keep working when new options are added.
public struct AppSettings: Codable, Equatable, Sendable {
    public static let focusPresets: [Int] = [25, 45, 60]
    public static let maxRepeatCount = 12

    // Focus
    public var timerMode: TimerMode = .focus
    public var focusMinutes: Int = 45
    public var shortBreakMinutes: Int = 5
    public var pomodoroWorkMinutes: Int = 25
    public var pomodoroShortBreakMinutes: Int = 5
    public var pomodoroLongBreakMinutes: Int = 15
    public var longBreakEvery: Int = 4
    public var autoStartBreaks: Bool = false
    public var autoStartFocus: Bool = false
    public var showMenuBarCountdown: Bool = true
    /// Open the guided break panel when a break starts from the menu or a notification.
    public var openBreakPanel: Bool = true

    // Reminders
    public var notificationsEnabled: Bool = true
    public var repeatIntervalMinutes: Int = 5
    public var repeatCount: Int = 3
    public var soundEnabled: Bool = true
    public var quietHoursEnabled: Bool = false
    public var quietHours: QuietHours = QuietHours(startMinute: 22 * 60, endMinute: 7 * 60)
    /// If a session ended while the Mac was asleep or FlowBreak was not running,
    /// post one catch-up reminder on wake/relaunch.
    public var remindAfterWake: Bool = true

    // Tracking & privacy
    public var appTrackingEnabled: Bool = false
    public var privateMode: Bool = false
    public var excludedBundleIDs: [String] = []

    // Tasks
    public var quickAddShortcut: ShortcutPreset = .off
    public var toggleFocusShortcut: ShortcutPreset = .off
    public var openTodayShortcut: ShortcutPreset = .off
    /// Ask "how did it go?" after a task-linked focus session.
    public var askForOutcome: Bool = true
    /// Move a task to In Progress when a focus session starts on it.
    public var moveToInProgressOnFocus: Bool = true
    /// End of the workday (minutes after midnight), for the Today workload hint.
    public var workdayEndMinute: Int = 18 * 60
    public var hidePrivateTasksInInsights: Bool = true
    public var completionHaptics: Bool = true
    public var lastBackupAt: Date?

    // Behaviour
    public var showInDock: Bool = false
    public var hasCompletedOnboarding: Bool = false

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case timerMode, focusMinutes, shortBreakMinutes, pomodoroWorkMinutes
        case pomodoroShortBreakMinutes, pomodoroLongBreakMinutes, longBreakEvery
        case autoStartBreaks, autoStartFocus, showMenuBarCountdown, openBreakPanel
        case notificationsEnabled, repeatIntervalMinutes, repeatCount, soundEnabled
        case quietHoursEnabled, quietHours, remindAfterWake
        case appTrackingEnabled, privateMode, excludedBundleIDs
        case showInDock, hasCompletedOnboarding
        case quickAddShortcut, toggleFocusShortcut, openTodayShortcut, askForOutcome, moveToInProgressOnFocus
        case workdayEndMinute, hidePrivateTasksInInsights, completionHaptics, lastBackupAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.defaultValue
        timerMode = (try? c.decodeIfPresent(TimerMode.self, forKey: .timerMode)) ?? d.timerMode
        focusMinutes = (try? c.decodeIfPresent(Int.self, forKey: .focusMinutes)) ?? d.focusMinutes
        shortBreakMinutes = (try? c.decodeIfPresent(Int.self, forKey: .shortBreakMinutes)) ?? d.shortBreakMinutes
        pomodoroWorkMinutes = (try? c.decodeIfPresent(Int.self, forKey: .pomodoroWorkMinutes)) ?? d.pomodoroWorkMinutes
        pomodoroShortBreakMinutes = (try? c.decodeIfPresent(Int.self, forKey: .pomodoroShortBreakMinutes)) ?? d.pomodoroShortBreakMinutes
        pomodoroLongBreakMinutes = (try? c.decodeIfPresent(Int.self, forKey: .pomodoroLongBreakMinutes)) ?? d.pomodoroLongBreakMinutes
        longBreakEvery = (try? c.decodeIfPresent(Int.self, forKey: .longBreakEvery)) ?? d.longBreakEvery
        autoStartBreaks = (try? c.decodeIfPresent(Bool.self, forKey: .autoStartBreaks)) ?? d.autoStartBreaks
        autoStartFocus = (try? c.decodeIfPresent(Bool.self, forKey: .autoStartFocus)) ?? d.autoStartFocus
        showMenuBarCountdown = (try? c.decodeIfPresent(Bool.self, forKey: .showMenuBarCountdown)) ?? d.showMenuBarCountdown
        openBreakPanel = (try? c.decodeIfPresent(Bool.self, forKey: .openBreakPanel)) ?? d.openBreakPanel
        notificationsEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled)) ?? d.notificationsEnabled
        repeatIntervalMinutes = (try? c.decodeIfPresent(Int.self, forKey: .repeatIntervalMinutes)) ?? d.repeatIntervalMinutes
        repeatCount = (try? c.decodeIfPresent(Int.self, forKey: .repeatCount)) ?? d.repeatCount
        soundEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .soundEnabled)) ?? d.soundEnabled
        quietHoursEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .quietHoursEnabled)) ?? d.quietHoursEnabled
        quietHours = (try? c.decodeIfPresent(QuietHours.self, forKey: .quietHours)) ?? d.quietHours
        remindAfterWake = (try? c.decodeIfPresent(Bool.self, forKey: .remindAfterWake)) ?? d.remindAfterWake
        appTrackingEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .appTrackingEnabled)) ?? d.appTrackingEnabled
        privateMode = (try? c.decodeIfPresent(Bool.self, forKey: .privateMode)) ?? d.privateMode
        excludedBundleIDs = (try? c.decodeIfPresent([String].self, forKey: .excludedBundleIDs)) ?? d.excludedBundleIDs
        showInDock = (try? c.decodeIfPresent(Bool.self, forKey: .showInDock)) ?? d.showInDock
        hasCompletedOnboarding = (try? c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding)) ?? d.hasCompletedOnboarding
        quickAddShortcut = (try? c.decodeIfPresent(ShortcutPreset.self, forKey: .quickAddShortcut)) ?? d.quickAddShortcut
        toggleFocusShortcut = (try? c.decodeIfPresent(ShortcutPreset.self, forKey: .toggleFocusShortcut)) ?? d.toggleFocusShortcut
        openTodayShortcut = (try? c.decodeIfPresent(ShortcutPreset.self, forKey: .openTodayShortcut)) ?? d.openTodayShortcut
        askForOutcome = (try? c.decodeIfPresent(Bool.self, forKey: .askForOutcome)) ?? d.askForOutcome
        moveToInProgressOnFocus = (try? c.decodeIfPresent(Bool.self, forKey: .moveToInProgressOnFocus)) ?? d.moveToInProgressOnFocus
        workdayEndMinute = (try? c.decodeIfPresent(Int.self, forKey: .workdayEndMinute)) ?? d.workdayEndMinute
        hidePrivateTasksInInsights = (try? c.decodeIfPresent(Bool.self, forKey: .hidePrivateTasksInInsights)) ?? d.hidePrivateTasksInInsights
        completionHaptics = (try? c.decodeIfPresent(Bool.self, forKey: .completionHaptics)) ?? d.completionHaptics
        lastBackupAt = (try? c.decodeIfPresent(Date.self, forKey: .lastBackupAt)) ?? nil
        self = self.sanitized()
    }

    public static let defaultValue = AppSettings()

    /// Clamp values into supported ranges.
    public func sanitized() -> AppSettings {
        var s = self
        s.focusMinutes = min(max(s.focusMinutes, 1), 240)
        s.shortBreakMinutes = min(max(s.shortBreakMinutes, 1), 60)
        s.pomodoroWorkMinutes = min(max(s.pomodoroWorkMinutes, 1), 240)
        s.pomodoroShortBreakMinutes = min(max(s.pomodoroShortBreakMinutes, 1), 60)
        s.pomodoroLongBreakMinutes = min(max(s.pomodoroLongBreakMinutes, 1), 120)
        s.longBreakEvery = min(max(s.longBreakEvery, 2), 12)
        s.repeatIntervalMinutes = min(max(s.repeatIntervalMinutes, 1), 60)
        s.repeatCount = min(max(s.repeatCount, 0), AppSettings.maxRepeatCount)
        s.quietHours.startMinute = min(max(s.quietHours.startMinute, 0), 24 * 60 - 1)
        s.quietHours.endMinute = min(max(s.quietHours.endMinute, 0), 24 * 60 - 1)
        s.workdayEndMinute = min(max(s.workdayEndMinute, 0), 24 * 60 - 1)
        return s
    }

    public var timerConfiguration: TimerConfiguration {
        TimerConfiguration(
            mode: timerMode,
            focusDuration: TimeInterval((timerMode == .pomodoro ? pomodoroWorkMinutes : focusMinutes) * 60),
            shortBreakDuration: TimeInterval((timerMode == .pomodoro ? pomodoroShortBreakMinutes : shortBreakMinutes) * 60),
            longBreakDuration: TimeInterval(pomodoroLongBreakMinutes * 60),
            longBreakEvery: longBreakEvery,
            autoStartBreaks: autoStartBreaks,
            autoStartFocus: autoStartFocus
        )
    }

    public var reminderSettings: ReminderSettings {
        ReminderSettings(
            enabled: notificationsEnabled,
            repeatInterval: TimeInterval(repeatIntervalMinutes * 60),
            repeatCount: repeatCount,
            quietHours: quietHoursEnabled ? quietHours : nil
        )
    }
}

/// The subset of settings the timer engine needs.
public struct TimerConfiguration: Equatable, Sendable {
    public var mode: TimerMode
    public var focusDuration: TimeInterval
    public var shortBreakDuration: TimeInterval
    public var longBreakDuration: TimeInterval
    public var longBreakEvery: Int
    public var autoStartBreaks: Bool
    public var autoStartFocus: Bool

    public init(
        mode: TimerMode = .focus,
        focusDuration: TimeInterval = 45 * 60,
        shortBreakDuration: TimeInterval = 5 * 60,
        longBreakDuration: TimeInterval = 15 * 60,
        longBreakEvery: Int = 4,
        autoStartBreaks: Bool = false,
        autoStartFocus: Bool = false
    ) {
        self.mode = mode
        self.focusDuration = focusDuration
        self.shortBreakDuration = shortBreakDuration
        self.longBreakDuration = longBreakDuration
        self.longBreakEvery = longBreakEvery
        self.autoStartBreaks = autoStartBreaks
        self.autoStartFocus = autoStartFocus
    }

    public var focusKind: SessionKind { mode == .pomodoro ? .pomodoroFocus : .focus }
}
