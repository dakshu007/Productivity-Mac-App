import AppKit
import FlowBreakCore
import SwiftUI

/// Calendar awareness, distraction nudges, update checks, App Intents and diagnostics.
extension AppModel {
    func configureIntegrations() {
        IntentBridge.model = self
        calendarService.onChange = { [weak self] in self?.refreshCalendar() }
        calendarAccess = calendarService.access
        refreshCalendar()
        configureNudges()

        let calendarTimer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshCalendar() }
        }
        let updateTimer = Timer(timeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkForUpdatesIfDue() }
        }
        for timer in [calendarTimer, updateTimer] {
            timer.tolerance = 30
            RunLoop.main.add(timer, forMode: .common)
        }
        integrationTimers = [calendarTimer, updateTimer]
        checkForUpdatesIfDue()
    }

    func integrationSettingsChanged(from old: AppSettings) {
        if old.calendarAwareness != settings.calendarAwareness || old.calendarIDs != settings.calendarIDs {
            refreshCalendar()
        }
        if old.nudgesEnabled != settings.nudgesEnabled {
            configureNudges()
        }
        if !old.checkForUpdatesAutomatically && settings.checkForUpdatesAutomatically {
            checkForUpdatesIfDue()
        }
    }

    // MARK: - Calendar

    var reminderBusyIntervals: [DateInterval] {
        guard settings.calendarAwareness, settings.holdRemindersDuringMeetings else { return [] }
        return busyBlocks.map(\.interval)
    }

    var currentMeeting: BusyBlock? {
        guard settings.calendarAwareness else { return nil }
        return CalendarPlanning.current(busyBlocks, at: now)
    }

    var nextMeeting: BusyBlock? {
        guard settings.calendarAwareness else { return nil }
        return CalendarPlanning.next(busyBlocks, after: now)
    }

    /// The meeting a session of `minutes` starting now would run into.
    func meetingConflict(minutes: Int) -> BusyBlock? {
        guard settings.calendarAwareness else { return nil }
        return CalendarPlanning.firstConflict(busyBlocks, start: now, duration: TimeInterval(minutes * 60))
    }

    /// Free minutes left in the workday after meetings (nil when calendar awareness is off).
    var freeMinutesToday: Int? {
        guard settings.calendarAwareness, calendarAccess == .granted else { return nil }
        let end = calendar.startOfDay(for: now).addingTimeInterval(TimeInterval(settings.workdayEndMinute * 60))
        return CalendarPlanning.freeMinutes(busyBlocks, from: now, until: end)
    }

    func enableCalendarAwareness() {
        Task { @MainActor in
            let access = await calendarService.requestAccess()
            calendarAccess = access
            if access == .granted {
                update { $0.calendarAwareness = true }
            } else if access == .writeOnly {
                errorMessage = "FlowBreak can add focus blocks but can't see your meetings. Allow full calendar access in System Settings › Privacy & Security › Calendars to hold reminders during meetings."
                update { $0.calendarAwareness = false }
            } else {
                update { $0.calendarAwareness = false }
            }
            refreshCalendar()
        }
    }

    func refreshCalendar() {
        calendarAccess = calendarService.access
        calendarList = calendarService.calendars()
        guard settings.calendarAwareness, calendarAccess == .granted else {
            if !busyBlocks.isEmpty {
                busyBlocks = []
                syncNotifications()
            }
            return
        }
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 2, to: start) ?? start.addingTimeInterval(2 * 86_400)
        let blocks = calendarService.busyBlocks(from: start, to: end, calendarIDs: settings.calendarIDs)
        if blocks != busyBlocks {
            busyBlocks = blocks
            syncNotifications()
        }
    }

    func openCalendarPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Adds "Focus: <task>" to the calendar. Returns an error message on failure.
    func scheduleFocusBlock(for task: TaskItem, start: Date, minutes: Int, calendarID: String?) async -> String? {
        if calendarService.access == .notDetermined {
            calendarAccess = await calendarService.requestAccess()
        }
        guard calendarService.access == .granted || calendarService.access == .writeOnly else {
            return "FlowBreak needs calendar access to add focus blocks. You can allow it in System Settings › Privacy & Security › Calendars."
        }
        var notes = "Planned in FlowBreak."
        if let dod = task.definitionOfDone { notes += "\nDone when: \(dod)" }
        let error = calendarService.addFocusBlock(title: "Focus: \(task.title)", notes: notes, start: start, duration: TimeInterval(minutes * 60), calendarID: calendarID ?? settings.focusBlockCalendarID)
        if error == nil {
            if let calendarID { update { $0.focusBlockCalendarID = calendarID } }
            if calendar.isDate(start, inSameDayAs: Date()), task.status == .inbox || task.status == .next || task.status == .someday {
                setStatus([task.id], .today)
            }
            refreshCalendar()
            showToast(TaskToast(kind: .info, title: "Focus block added", detail: "\(start.formatted(date: .abbreviated, time: .shortened)) · \(minutes) min", nextTask: nil))
        }
        return error
    }

    // MARK: - Nudges

    func configureNudges() {
        if settings.nudgesEnabled {
            if nudgeController == nil { nudgeController = NudgeController(model: self) }
            nudgeController?.start()
        } else {
            nudgeController?.stop()
        }
    }

    func recordNudge() {
        engine.recordNudge(at: Date())
        refresh()
    }

    // MARK: - Updates

    var shouldAskAboutUpdates: Bool {
        settings.hasCompletedOnboarding && !settings.hasAnsweredUpdatePrompt && !settings.checkForUpdatesAutomatically
    }

    func answerUpdatePrompt(enable: Bool) {
        update {
            $0.hasAnsweredUpdatePrompt = true
            $0.checkForUpdatesAutomatically = enable
        }
    }

    func checkForUpdatesIfDue() {
        guard settings.checkForUpdatesAutomatically else { return }
        if let last = settings.lastUpdateCheck, Date().timeIntervalSince(last) < UpdateService.checkInterval { return }
        checkForUpdates(userInitiated: false)
    }

    func checkForUpdates(userInitiated: Bool) {
        if case .checking = updateState { return }
        if case .downloading = updateState { return }
        updateState = .checking
        Task { @MainActor in
            let result = await updates.check()
            update { $0.lastUpdateCheck = Date() }
            if !userInitiated, case .failed = result {
                updateState = .idle // stay quiet about background failures
            } else {
                updateState = result
            }
        }
    }

    func downloadUpdate() {
        guard case let .available(manifest) = updateState else { return }
        updateState = .downloading(manifest)
        Task { @MainActor in
            updateState = await updates.download(manifest)
        }
    }

    func dismissUpdate() {
        updateState = .idle
    }

    // MARK: - Diagnostics

    /// A plain-text report for bug reports. Contains settings and counts only —
    /// no task titles, notes, app names or calendar details.
    func diagnosticsReport() -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let arch: String = {
            #if arch(arm64)
            return "arm64"
            #else
            return "x86_64"
            #endif
        }()
        let s = settings
        let lines = [
            "FlowBreak \(versionString) on macOS \(os) (\(arch))",
            "Phase: \(state.phase.rawValue)\(state.isPaused ? " (paused)" : ""), pending check-in: \(state.pendingCheckIn != nil)",
            "Mode: \(s.timerMode.rawValue), focus \(s.focusMinutes)m, break \(s.shortBreakMinutes)m, pomodoro \(s.pomodoroWorkMinutes)/\(s.pomodoroShortBreakMinutes)/\(s.pomodoroLongBreakMinutes) every \(s.longBreakEvery)",
            "Notifications: enabled=\(s.notificationsEnabled), permission=\(String(describing: notificationStatus)), repeat=\(s.repeatCount)x\(s.repeatIntervalMinutes)m, quietHours=\(s.quietHoursEnabled)",
            "Auto cycles: breaks=\(s.autoStartBreaks) focus=\(s.autoStartFocus)",
            "Records: \(sessions.count) sessions, \(tasks.count) tasks (\(tasks.filter(\.isOpen).count) open), \(usage.count) usage samples, \(reflections.count) reflections",
            "Tracking: enabled=\(s.appTrackingEnabled) private=\(s.privateMode) exclusions=\(s.excludedBundleIDs.count)",
            "Calendar: awareness=\(s.calendarAwareness) access=\(String(describing: calendarAccess)) busyBlocks=\(busyBlocks.count) hold=\(s.holdRemindersDuringMeetings)",
            "Nudges: enabled=\(s.nudgesEnabled) apps=\(s.distractingBundleIDs.count) cooldown=\(s.nudgeCooldownMinutes)m",
            "Shortcuts: quickAdd=\(s.quickAddShortcut.rawValue) focus=\(s.toggleFocusShortcut.rawValue) today=\(s.openTodayShortcut.rawValue) errors=\(shortcutErrors.count)",
            "Updates: auto=\(s.checkForUpdatesAutomatically) lastCheck=\(s.lastUpdateCheck.map { ISO8601DateFormatter().string(from: $0) } ?? "never")",
            "Launch at login: \(String(describing: launchAtLoginStatus)), Dock: \(s.showInDock)",
            "Last error: \(errorMessage ?? "none")",
        ]
        return lines.joined(separator: "\n")
    }

    func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnosticsReport(), forType: .string)
        showToast(TaskToast(kind: .info, title: "Diagnostics copied", detail: "No task titles, notes or app names are included.", nextTask: nil))
    }

    /// Opens a pre-filled GitHub issue in the browser. Nothing is sent until you submit it.
    func reportProblem() {
        var components = URLComponents(string: "https://github.com/dakshu007/Productivity-Mac-App/issues/new")
        let body = """
        **What happened?**


        **What did you expect?**


        **Steps to reproduce**
        1.

        ---
        Diagnostics (no personal content):
        ```
        \(diagnosticsReport())
        ```
        """
        components?.queryItems = [
            URLQueryItem(name: "title", value: "Bug: "),
            URLQueryItem(name: "body", value: body),
        ]
        if let url = components?.url { NSWorkspace.shared.open(url) }
    }
}
