import AppKit
import Combine
import FlowBreakCore
import SwiftUI
import UniformTypeIdentifiers

enum AppWindow: String {
    case settings
    case insights
    case onboarding
    case guidedBreak
    case tasks
    case quickAdd
}

enum SettingsTab: String, Hashable {
    case focus, reminders, tasks, privacy, general, about
}

/// The app's single source of observable state. Views call intent methods here;
/// all timer logic is delegated to `TimerEngine`.
@MainActor
final class AppModel: ObservableObject {
    static let snoozeInterval: TimeInterval = 5 * 60
    static let breakExtension: TimeInterval = 5 * 60

    @Published private(set) var state: EngineState
    @Published private(set) var sessions: [FocusSession]
    @Published var usage: [UsageSample] = []
    @Published private(set) var now = Date()
    @Published private(set) var notificationStatus: NotificationAuthorization = .unknown
    @Published var errorMessage: String?
    @Published private(set) var launchAtLoginStatus: LaunchAtLoginService.Status = .disabled
    @Published var settingsTab: SettingsTab = .focus
    @Published var settings: AppSettings {
        didSet { settingsChanged(from: oldValue) }
    }

    // Tasks
    @Published var tasks: [TaskItem] = []
    @Published var reflections: [WeeklyReflection] = []
    @Published var taskList: TaskListKind = .today
    @Published var selectedTaskIDs: Set<UUID> = []
    @Published var toast: TaskToast? = nil
    /// Tasks just completed, kept visible in their list for a moment so the
    /// completion animation can play: id → (list, position).
    @Published var lingering: [UUID: LingeringTask] = [:]
    /// A completion waiting for its Proof of Done confirmation.
    @Published var proofRequest: TaskItem? = nil
    /// Task whose "Start focus" sheet is showing in the Tasks window.
    @Published var focusSheetTask: TaskItem? = nil
    /// Set to ask the Tasks window to focus its search field (⌘F).
    @Published var focusSearch = false
    @Published var pendingRestore: PendingRestore? = nil
    @Published var shortcutErrors: [String] = []
    @Published var nextTaskID: UUID? = nil {
        didSet { UserDefaults.standard.set(nextTaskID?.uuidString, forKey: Self.nextTaskKey) }
    }
    static let nextTaskKey = "FlowBreak.nextTaskID"
    let taskRepo: TaskRepository
    let hotKeys = HotKeyService()
    var taskSaveWork: DispatchWorkItem?
    var toastDismissWork: DispatchWorkItem?

    let calendar = Calendar.current
    var openWindow: ((AppWindow) -> Void)?
    var closePopover: (() -> Void)?

    let engine: TimerEngine
    let store: JSONFileStore
    private let settingsStore: SettingsStore
    private let notifications: NotificationService
    private let launchAtLogin = LaunchAtLoginService()
    private var tracker: AppUsageTracker?
    private var ticker: Timer?
    private var observers: [NSObjectProtocol] = []

    init(
        store: JSONFileStore = JSONFileStore(),
        settingsStore: SettingsStore = SettingsStore(),
        notifications: NotificationService? = nil
    ) {
        self.store = store
        self.settingsStore = settingsStore
        let loaded = settingsStore.load()
        self.settings = loaded
        self.notifications = notifications ?? NotificationService()
        let engine = TimerEngine(store: store, configuration: loaded.timerConfiguration)
        self.engine = engine
        self.state = engine.state
        self.sessions = engine.sessions
        self.errorMessage = engine.lastPersistenceError
        do {
            self.usage = try store.loadUsage()
        } catch {
            self.errorMessage = error.localizedDescription
        }
        let taskRepo = TaskRepository(store: store)
        self.taskRepo = taskRepo
        self.tasks = taskRepo.tasks
        if let taskError = taskRepo.lastPersistenceError { self.errorMessage = taskError }
        self.reflections = (try? store.loadReflections()) ?? []
        if let saved = UserDefaults.standard.string(forKey: Self.nextTaskKey), let id = UUID(uuidString: saved) {
            self.nextTaskID = taskRepo.task(id)?.isOpen == true ? id : nil
        }
        self.notificationStatus = self.notifications.authorization
    }

    // MARK: - Lifecycle

    func start() {
        notifications.onAuthorizationChange = { [weak self] status in
            self?.notificationStatus = status
        }
        notifications.setActionHandler { [weak self] action in
            self?.handle(notificationAction: action)
        }
        notifications.refreshAuthorization()
        launchAtLoginStatus = launchAtLogin.status

        // Reconcile against the clock immediately (relaunch with an active or expired session).
        reconcile(reason: "launch")

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reconcile(reason: nil) }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer

        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reconcile(reason: "wake") }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.reconcile(reason: "activate")
                self?.notifications.refreshAuthorization()
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reconcile(reason: "clock") }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.objectWillChange.send() }
        })

        observers.append(NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.ensureRecurringTasks() }
        })

        configureTracking()
        configureShortcuts()
        ensureRecurringTasks()
        syncNotifications()
    }

    func prepareForTermination() {
        tracker?.flush()
        tracker?.stop()
        ticker?.invalidate()
    }

    // MARK: - Derived state

    var remaining: TimeInterval { engine.remaining(at: now) }

    var progress: Double {
        switch state.phase {
        case .focusing, .onBreak: return state.current?.progress(at: now) ?? 0
        case .breakDue, .breakComplete, .idle: return 0
        }
    }

    var configuration: TimerConfiguration { settings.timerConfiguration }

    var todaySummary: (focusTime: TimeInterval, breaks: Int, completed: Int, tasksDone: Int) {
        let summary = StatisticsCalculator(calendar: calendar).summary(sessions: sessions, range: .today, now: now)
        let done = tasks.filter { $0.status == .completed && ($0.completedAt.map { calendar.isDate($0, inSameDayAs: now) } ?? false) }.count
        return (summary.focusTime, summary.breaksTaken, summary.focusSessionsCompleted, done)
    }

    func summary(for range: InsightsRange) -> InsightsSummary {
        StatisticsCalculator(calendar: calendar).summary(sessions: sessions, range: range, now: now)
    }

    var isNotificationProblem: Bool {
        settings.notificationsEnabled && (notificationStatus == .denied || notificationStatus == .notDetermined)
    }

    var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    // MARK: - Timer intents

    /// Starts focus on the selected "next up" task, if there is one.
    func startFocus(minutes: Int? = nil) {
        let taskID = nextTaskID.flatMap { taskRepo.task($0)?.isOpen == true ? $0 : nil }
        startFocus(on: taskID, minutes: minutes, intent: nil)
    }

    func pause() { apply(engine.pause(at: Date())) }
    func resume() { apply(engine.resume(at: Date())) }
    func stop() { apply(engine.stop(at: Date())) }

    func startBreak(kind: SessionKind? = nil, openPanel: Bool = true) {
        apply(engine.startBreak(at: Date(), kind: kind))
        if openPanel && settings.openBreakPanel && state.phase == .onBreak {
            closePopover?()
            openWindow?(.guidedBreak)
        }
    }

    func extendBreak() { apply(engine.extendBreak(by: Self.breakExtension, at: Date())) }
    func snooze() { apply(engine.snooze(for: Self.snoozeInterval, at: Date())) }
    func skipBreak() { apply(engine.skipBreak(at: Date())) }

    func dismissBreakComplete() {
        engine.dismissBreakComplete(at: Date())
        refresh()
        syncNotifications()
    }

    // MARK: - Notifications

    func requestNotificationPermission() {
        notifications.requestAuthorization()
    }

    func openNotificationSettings() {
        let bundleID = Bundle.main.bundleIdentifier ?? "app.flowbreak.mac"
        let urls = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleID)",
            "x-apple.systempreferences:com.apple.preference.notifications",
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    func handle(notificationAction action: NotificationAction) {
        reconcile(reason: "notification")
        switch action {
        case .takeBreak:
            startBreak()
        case .snooze:
            snooze()
        case .dismiss:
            skipBreak()
        case .startFocus:
            startFocus()
        case .open:
            if state.phase == .onBreak {
                openWindow?(.guidedBreak)
            }
        }
    }

    // MARK: - Settings

    func update(_ change: (inout AppSettings) -> Void) {
        var copy = settings
        change(&copy)
        settings = copy.sanitized()
    }

    private func settingsChanged(from old: AppSettings) {
        settingsStore.save(settings)
        engine.apply(configuration: settings.timerConfiguration)
        if old.showInDock != settings.showInDock {
            NSApp.setActivationPolicy(settings.showInDock ? .regular : .accessory)
        }
        if old.appTrackingEnabled != settings.appTrackingEnabled
            || old.privateMode != settings.privateMode
            || old.excludedBundleIDs != settings.excludedBundleIDs {
            configureTracking()
        }
        if old.quickAddShortcut != settings.quickAddShortcut
            || old.toggleFocusShortcut != settings.toggleFocusShortcut
            || old.openTodayShortcut != settings.openTodayShortcut {
            configureShortcuts()
        }
        if old.notificationsEnabled != settings.notificationsEnabled && settings.notificationsEnabled && notificationStatus == .notDetermined {
            notifications.requestAuthorization()
        }
        syncNotifications()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        if let error = launchAtLogin.setEnabled(enabled) {
            errorMessage = "Launch at login couldn't be changed: \(error)"
        }
        launchAtLoginStatus = launchAtLogin.status
    }

    func refreshLaunchAtLogin() {
        launchAtLoginStatus = launchAtLogin.status
    }

    func openLoginItemsSettings() {
        launchAtLogin.openLoginItemsSettings()
    }

    func completeOnboarding() {
        update { $0.hasCompletedOnboarding = true }
    }

    func dismissError() {
        errorMessage = nil
    }

    // MARK: - Tracking

    private func configureTracking() {
        let policy = UsagePolicy(settings: settings)
        if policy.enabled {
            if let tracker {
                tracker.update(policy: policy)
            } else {
                let tracker = AppUsageTracker(policy: policy) { [weak self] sample in
                    self?.record(sample)
                }
                self.tracker = tracker
                tracker.start()
            }
        } else if let tracker {
            tracker.update(policy: policy)
            tracker.stop()
            self.tracker = nil
        }
    }

    private func record(_ sample: UsageSample) {
        usage.append(sample)
        saveUsage()
    }

    private func saveUsage() {
        do {
            try store.saveUsage(usage)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    struct RunningApp: Identifiable {
        var bundleID: String
        var name: String
        var id: String { bundleID }
    }

    func runningApplicationsForExclusion() -> [RunningApp] {
        let ownID = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        var result: [RunningApp] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let id = app.bundleIdentifier, id != ownID, !seen.contains(id) else { continue }
            seen.insert(id)
            result.append(RunningApp(bundleID: id, name: app.localizedName ?? id))
        }
        return result
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func appName(for bundleID: String) -> String {
        if let sample = usage.last(where: { $0.bundleID == bundleID }) { return sample.appName }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }

    func usageAggregates(for range: InsightsRange) -> [UsageAggregate] {
        UsageAggregator.aggregate(usage, in: range.interval(now: now, calendar: calendar))
    }

    // MARK: - Data management

    enum ExportKind {
        case json, sessionsCSV, usageCSV
    }

    func export(_ kind: ExportKind) {
        tracker?.flush()
        let panel = NSSavePanel()
        let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        switch kind {
        case .json:
            panel.nameFieldStringValue = "FlowBreak-export-\(stamp).json"
            panel.allowedContentTypes = [.json]
        case .sessionsCSV:
            panel.nameFieldStringValue = "FlowBreak-sessions-\(stamp).csv"
            panel.allowedContentTypes = [.commaSeparatedText]
        case .usageCSV:
            panel.nameFieldStringValue = "FlowBreak-app-usage-\(stamp).csv"
            panel.allowedContentTypes = [.commaSeparatedText]
        }
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data: Data
            switch kind {
            case .json: data = try BackupService.encode(makeBackup())
            case .sessionsCSV: data = Data(DataExporter.sessionsCSV(sessions).utf8)
            case .usageCSV: data = Data(DataExporter.usageCSV(usage).utf8)
            }
            try data.write(to: url, options: .atomic)
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    func deleteAllData() {
        engine.clearHistory()
        usage.removeAll()
        saveUsage()
        taskRepo.replaceAll([])
        saveTasksNow()
        reflections = []
        try? store.saveReflections([])
        nextTaskID = nil
        selectedTaskIDs = []
        refresh()
    }

    // MARK: - Screenshot rendering support

    /// Drives the engine with explicit timestamps. Used only by `--render-previews`,
    /// which runs against a temporary store, never the user's data.
    func driveForPreview(now: Date, _ body: (TimerEngine) -> Void) {
        body(engine)
        self.now = now
        refresh()
    }

    func setPreviewState(notificationStatus: NotificationAuthorization, usage: [UsageSample]? = nil, error: String? = nil) {
        self.notificationStatus = notificationStatus
        if let usage { self.usage = usage }
        self.errorMessage = error
    }

    // MARK: - Internals

    func reconcile(reason: String?) {
        now = Date()
        let events = engine.reconcile(at: now)
        if !events.isEmpty || reason != nil {
            if let reason, !events.isEmpty {
                Log.timer.info("Reconciled on \(reason, privacy: .public): \(events.count) event(s)")
            }
            apply(events, refreshNow: false)
        }
    }

    func apply(_ events: [EngineEvent], refreshNow: Bool = true) {
        if refreshNow { now = Date() }
        refresh()
        for event in events {
            switch event {
            case let .focusCompleted(_, late) where late && settings.remindAfterWake && settings.notificationsEnabled:
                let minutes = Int(((state.breakDue?.suggestedDuration ?? configuration.shortBreakDuration) / 60).rounded())
                notifications.postCatchUp(focusEnded: true, breakMinutes: minutes, soundEnabled: settings.soundEnabled)
            case let .breakCompleted(_, late) where late && settings.remindAfterWake && settings.notificationsEnabled:
                notifications.postCatchUp(focusEnded: false, breakMinutes: 0, soundEnabled: settings.soundEnabled)
            default:
                break
            }
        }
        if !events.isEmpty { syncNotifications() }
    }

    func refresh() {
        if state != engine.state { state = engine.state }
        if sessions != engine.sessions { sessions = engine.sessions }
        if let error = engine.lastPersistenceError {
            errorMessage = error
        }
        if !settings.askForOutcome, engine.state.pendingCheckIn != nil {
            engine.dismissCheckIn(at: Date())
            if state != engine.state { state = engine.state }
            if sessions != engine.sessions { sessions = engine.sessions }
        }
    }

    func syncNotifications() {
        let plan = ReminderPlanner.plan(
            state: engine.state,
            settings: settings.reminderSettings,
            defaultBreakDuration: configuration.shortBreakDuration,
            now: Date(),
            calendar: calendar
        )
        notifications.sync(plan: plan, state: engine.state, soundEnabled: settings.soundEnabled)
    }
}
