import AppKit
import FlowBreakCore
import SwiftUI
import UniformTypeIdentifiers

/// Bottom toast shown after completing, archiving or deleting tasks.
struct TaskToast: Identifiable, Equatable {
    enum Kind: Equatable {
        case completed(TaskCompletion)
        case archived([UUID])
        case deleted([TaskItem])
        /// Information only; no undo.
        case info
    }

    var canUndo: Bool {
        if case .info = kind { return false }
        return true
    }

    let id = UUID()
    var kind: Kind
    var title: String
    var detail: String?
    var nextTask: TaskItem?

    static func == (lhs: TaskToast, rhs: TaskToast) -> Bool { lhs.id == rhs.id }
}

struct LingeringTask: Equatable {
    var list: TaskListKind
    var index: Int
}

struct PendingRestore: Identifiable {
    let id = UUID()
    var backup: BackupFile
    var preview: BackupPreview
}

extension AppModel {
    // MARK: - Queries

    func task(_ id: UUID?) -> TaskItem? {
        guard let id else { return nil }
        return tasks.first { $0.id == id }
    }

    /// Tasks for a list, plus just-completed tasks kept briefly in place.
    func visibleTasks(_ list: TaskListKind) -> [TaskItem] {
        var result = taskRepo.tasks(in: list, now: now)
        for (id, linger) in lingering.sorted(by: { $0.value.index < $1.value.index }) where linger.list == list {
            guard let task = self.task(id), !result.contains(where: { $0.id == id }) else { continue }
            result.insert(task, at: min(linger.index, result.count))
        }
        return result
    }

    func subtasks(of id: UUID) -> [TaskItem] {
        taskRepo.subtasks(of: id)
    }

    var projects: [String] { taskRepo.projects }

    var currentTask: TaskItem? {
        guard state.phase == .focusing else { return nil }
        return task(state.current?.taskID)
    }

    var nextTask: TaskItem? {
        guard let task = self.task(nextTaskID), task.isOpen else { return nil }
        return task
    }

    /// Tasks offered in the popover's "next up" menu.
    var focusCandidates: [TaskItem] {
        let today = taskRepo.tasks(in: .today, now: now)
        let inProgress = taskRepo.tasks(in: .inProgress, now: now).filter { task in !today.contains { $0.id == task.id } }
        return Array((today + inProgress).prefix(12))
    }

    var bigThreeToday: [TaskItem] {
        tasks.filter { $0.isBigThree(on: now, calendar: calendar) }.sorted { a, b in
            a.sortOrder == b.sortOrder ? a.createdAt < b.createdAt : a.sortOrder < b.sortOrder
        }
    }

    var pendingCheckInSession: FocusSession? {
        guard settings.askForOutcome, let id = state.pendingCheckIn else { return nil }
        return sessions.last { $0.id == id }
    }

    var pendingCheckInTask: TaskItem? {
        task(pendingCheckInSession?.taskID)
    }

    func focusStats(for taskID: UUID) -> (time: TimeInterval, sessions: Int) {
        TaskInsightsCalculator.focusTime(for: taskID, sessions: sessions, now: now)
    }

    func linkedSessions(for taskID: UUID) -> [FocusSession] {
        sessions.filter { $0.kind.isFocus && $0.taskID == taskID }.sorted { $0.startedAt > $1.startedAt }
    }

    func count(for list: TaskListKind) -> Int {
        taskRepo.tasks(in: list, now: now).count
    }

    /// Rough planning aid for Today: estimates vs. time left in the workday.
    var todayWorkload: (planned: Int, unestimated: Int, minutesLeft: Int) {
        let planned = taskRepo.plannedMinutes(today: now)
        let start = calendar.startOfDay(for: now)
        let end = start.addingTimeInterval(TimeInterval(settings.workdayEndMinute * 60))
        let left = max(0, Int(end.timeIntervalSince(now) / 60))
        return (planned.minutes, planned.unestimated, left)
    }

    // MARK: - Create & edit

    /// Adds a task from Quick Add text. Returns nil (and sets an error) for an empty title.
    @discardableResult
    func addTask(text: String, parse: Bool, in list: TaskListKind) -> TaskItem? {
        let now = Date()
        var draft: TaskDraft
        if parse {
            draft = QuickAddParser(calendar: calendar).parse(text, now: now).draft(defaultStatus: list.defaultStatus, calendar: calendar, now: now)
        } else {
            draft = TaskDraft(title: text, status: list.defaultStatus)
        }
        if case let .project(name) = list, draft.project == nil { draft.project = name }
        do {
            let task = try taskRepo.add(draft, at: now)
            saveTasksNow()
            return task
        } catch {
            return nil
        }
    }

    func addSubtask(to parentID: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let parentStatus = task(parentID)?.status ?? .inbox
        _ = try? taskRepo.add(TaskDraft(title: trimmed, status: parentStatus.isOpen ? parentStatus : .inbox, parentID: parentID), at: Date())
        saveTasksNow()
    }

    /// Field edits are saved shortly after the user stops typing.
    func updateTask(_ id: UUID, _ change: (inout TaskItem) -> Void) {
        taskRepo.update(id, at: Date(), change)
        tasks = taskRepo.tasks
        scheduleTaskSave()
    }

    func setStatus(_ ids: [UUID], _ status: TaskStatus) {
        if status == .completed {
            for id in ids { completeTask(id, note: nil, skipProof: true) }
            return
        }
        if status == .archived {
            archive(ids)
            return
        }
        taskRepo.move(ids, to: status, at: Date())
        saveTasksNow()
    }

    func setBigThree(_ id: UUID, _ enabled: Bool) {
        do {
            try taskRepo.setBigThree(id, enabled: enabled, on: Date(), at: Date())
            saveTasksNow()
        } catch {
            showToast(TaskToast(kind: .info, title: error.localizedDescription, detail: nil, nextTask: nil))
        }
    }

    func duplicate(_ id: UUID) {
        if let copy = taskRepo.duplicate(id, at: Date()) {
            saveTasksNow()
            selectedTaskIDs = [copy.id]
        }
    }

    func setParent(_ id: UUID, parent: UUID?) {
        do {
            try taskRepo.setParent(id, parent: parent, at: Date())
            saveTasksNow()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addProgressNote(_ id: UUID, text: String, sessionID: UUID? = nil) {
        taskRepo.addProgressNote(id, text: text, sessionID: sessionID, at: Date())
        saveTasksNow()
    }

    func reorder(_ ids: [UUID]) {
        taskRepo.reorder(ids, at: Date())
        saveTasksNow()
    }

    // MARK: - Flow Finish

    /// Starts completing a task. If it has a Definition of Done, asks for proof first.
    func requestComplete(_ id: UUID) {
        guard let task = self.task(id), task.isOpen else { return }
        if let dod = task.definitionOfDone, !dod.isEmpty {
            // Proof of Done is confirmed in the Tasks window.
            proofRequest = task
            closePopover?()
            openWindow?(.tasks)
        } else {
            completeTask(id, note: nil, skipProof: true)
        }
    }

    /// Completes a task: record, haptic, toast with estimate vs. recorded focus time.
    func completeTask(_ id: UUID, note: String?, skipProof: Bool) {
        let listAtCompletion = taskList
        let index = visibleTasks(listAtCompletion).firstIndex { $0.id == id }
        guard let completion = taskRepo.complete(id, note: note, at: Date()) else { return }
        saveTasksNow()
        proofRequest = nil
        if nextTaskID == id { nextTaskID = nil }

        if let index {
            lingering[id] = LingeringTask(list: listAtCompletion, index: index)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                withAnimation(.easeOut(duration: 0.25)) { _ = self?.lingering.removeValue(forKey: id) }
            }
        }
        if settings.completionHaptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        // A pending check-in for this task is answered by completing it.
        if let session = pendingCheckInSession, session.taskID == id {
            apply(engine.recordOutcome(sessionID: session.id, outcome: .completed, note: note, at: Date()))
        }
        let stats = focusStats(for: id)
        let next = focusCandidates.first { $0.id != id }
        showToast(TaskToast(
            kind: .completed(completion),
            title: "Done. You moved this forward.",
            detail: Self.estimateComparison(estimate: completion.task.estimatedMinutes, focused: stats.time, sessions: stats.sessions),
            nextTask: next
        ))
    }

    static func estimateComparison(estimate: Int?, focused: TimeInterval, sessions: Int) -> String? {
        let focusedText = sessions > 0 ? "\(DurationFormatter.short(focused)) focused in \(sessions) session\(sessions == 1 ? "" : "s")" : "Focus time not tracked"
        if let estimate {
            return "Estimated \(QuickAddParser.formatMinutes(estimate)) · \(focusedText)"
        }
        return sessions > 0 ? focusedText : nil
    }

    func undoToast() {
        guard let toast else { return }
        switch toast.kind {
        case let .completed(completion):
            taskRepo.undo(completion, at: Date())
            lingering.removeValue(forKey: completion.task.id)
        case let .archived(ids):
            taskRepo.restore(ids, at: Date())
        case let .deleted(removed):
            taskRepo.reinsert(removed)
        case .info:
            break
        }
        saveTasksNow()
        dismissToast()
    }

    func reopen(_ id: UUID) {
        taskRepo.reopen(id, at: Date())
        saveTasksNow()
    }

    func archive(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        taskRepo.archive(ids, at: Date())
        saveTasksNow()
        selectedTaskIDs.subtract(ids)
        showToast(TaskToast(kind: .archived(ids), title: ids.count == 1 ? "Task archived" : "\(ids.count) tasks archived", detail: nil, nextTask: nil))
    }

    func restore(_ ids: [UUID]) {
        taskRepo.restore(ids, at: Date())
        saveTasksNow()
    }

    func deletePermanently(_ ids: [UUID]) {
        let removed = taskRepo.delete(ids)
        guard !removed.isEmpty else { return }
        saveTasksNow()
        selectedTaskIDs.subtract(removed.map(\.id))
        if let next = nextTaskID, removed.contains(where: { $0.id == next }) { nextTaskID = nil }
        showToast(TaskToast(kind: .deleted(removed), title: removed.count == 1 ? "Task deleted" : "\(removed.count) tasks deleted", detail: nil, nextTask: nil))
    }

    func showToast(_ toast: TaskToast) {
        toastDismissWork?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { self.toast = toast }
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.dismissToast() }
        }
        toastDismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
    }

    func dismissToast() {
        toastDismissWork?.cancel()
        withAnimation(.easeIn(duration: 0.2)) { toast = nil }
    }

    // MARK: - Focus on a task

    /// Shows the "Start focus" sheet for a task in the Tasks window.
    func presentStartFocus(_ task: TaskItem) {
        closePopover?()
        focusSheetTask = task
        openWindow?(.tasks)
    }

    func startFocus(on taskID: UUID?, minutes: Int?, intent: String?) {
        if let taskID, settings.moveToInProgressOnFocus, let task = self.task(taskID), task.isOpen, task.status != .inProgress {
            taskRepo.move([taskID], to: .inProgress, at: Date())
            saveTasksNow()
        }
        if let taskID { nextTaskID = taskID }
        apply(engine.startFocus(at: Date(), duration: minutes.map { TimeInterval($0 * 60) }, taskID: taskID, intent: intent))
    }

    /// Links the running session to another task (or none).
    func relinkCurrentSession(to taskID: UUID?) {
        guard let current = state.current, current.kind.isFocus else { return }
        engine.reassign(sessionID: current.id, to: taskID, at: Date())
        if let taskID { nextTaskID = taskID }
        refresh()
    }

    // MARK: - Check-in

    func recordCheckIn(_ outcome: SessionOutcome, note: String? = nil) {
        guard let session = pendingCheckInSession else { return }
        let taskID = session.taskID
        apply(engine.recordOutcome(sessionID: session.id, outcome: outcome, note: note, at: Date()))
        guard let taskID else { return }
        switch outcome {
        case .completed:
            completeTask(taskID, note: note, skipProof: true)
        case .progressMade:
            if let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                addProgressNote(taskID, text: note, sessionID: session.id)
            }
        case .continueLater:
            nextTaskID = taskID
        case .wrongTask, .notRecorded:
            break
        }
    }

    func reassignPendingSession(to taskID: UUID?) {
        guard let session = pendingCheckInSession else { return }
        engine.reassign(sessionID: session.id, to: taskID, at: Date())
        refresh()
    }

    func dismissCheckIn() {
        engine.dismissCheckIn(at: Date())
        refresh()
    }

    // MARK: - Weekly review

    func weeklyReview() -> WeeklyReview {
        WeeklyReview.make(tasks: tasks, sessions: sessions, reflections: reflections, now: now, hidePrivate: settings.hidePrivateTasksInInsights, calendar: calendar)
    }

    func saveReflection(helped: String, distracted: String) {
        let week = WeeklyReview.week(containing: Date(), calendar: calendar)
        var all = reflections.filter { !calendar.isDate($0.weekStart, inSameDayAs: week.start) }
        all.append(WeeklyReflection(weekStart: week.start, helped: helped, distracted: distracted, updatedAt: Date()))
        reflections = all.sorted { $0.weekStart < $1.weekStart }
        do {
            try store.saveReflections(reflections)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportWeeklySummary() {
        let markdown = weeklyReview().markdown(hidePrivate: settings.hidePrivateTasksInInsights, calendar: calendar)
        save(Data(markdown.utf8), suggestedName: "FlowBreak-week-\(Self.stamp()).md", type: UTType(filenameExtension: "md") ?? .plainText)
    }

    // MARK: - Import / export / backup

    func copyMarkdown(_ id: UUID) {
        guard let task = self.task(id) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(task.markdown(subtasks: subtasks(of: id)), forType: .string)
    }

    func openLink(_ id: UUID) {
        guard let raw = task(id)?.link?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return }
        let url: URL?
        if raw.hasPrefix("/") || raw.hasPrefix("~") {
            url = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
        } else if let parsed = URL(string: raw), let scheme = parsed.scheme?.lowercased(), ["http", "https", "file", "mailto"].contains(scheme) {
            url = parsed
        } else {
            url = URL(string: "https://" + raw)
        }
        if let url { NSWorkspace.shared.open(url) }
    }

    enum TaskExportKind { case markdown, csv }

    func exportTasks(_ kind: TaskExportKind) {
        let live = tasks.filter { $0.status != .archived }
        switch kind {
        case .markdown:
            save(Data(TaskExporter.markdown(live).utf8), suggestedName: "FlowBreak-tasks-\(Self.stamp()).md", type: UTType(filenameExtension: "md") ?? .plainText)
        case .csv:
            save(Data(TaskExporter.csv(tasks).utf8), suggestedName: "FlowBreak-tasks-\(Self.stamp()).csv", type: .commaSeparatedText)
        }
    }

    func importChecklist() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText, UTType(filenameExtension: "taskpaper") ?? .plainText]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            errorMessage = "That file couldn't be read as text."
            return
        }
        let items = ChecklistImporter.parse(text)
        let now = Date()
        for item in items {
            if let task = try? taskRepo.add(TaskDraft(title: item.title, status: .inbox), at: now), item.done {
                taskRepo.complete(task.id, at: now)
            }
        }
        saveTasksNow()
        taskList = .inbox
        showToast(TaskToast(kind: .info, title: "Imported \(items.count) task\(items.count == 1 ? "" : "s") into Inbox", detail: nil, nextTask: nil))
    }

    func makeBackup() -> BackupFile {
        BackupFile(exportedAt: Date(), sessions: sessions, tasks: tasks, usage: usage, reflections: reflections, settings: settings)
    }

    func backUpNow() {
        do {
            let data = try BackupService.encode(makeBackup())
            if save(data, suggestedName: "FlowBreak-backup-\(Self.stamp()).json", type: .json) {
                update { $0.lastBackupAt = Date() }
            }
        } catch {
            errorMessage = "Backup failed: \(error.localizedDescription)"
        }
    }

    /// Reads and validates a backup, then asks for confirmation (nothing changes yet).
    func chooseBackupToRestore() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let (backup, preview) = try BackupService.validate(data)
            pendingRestore = PendingRestore(backup: backup, preview: preview)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Replaces local data with the validated backup, after saving a safety copy.
    func confirmRestore() {
        guard let pending = pendingRestore else { return }
        pendingRestore = nil
        do {
            let safety = store.directory.appendingPathComponent("Backups", isDirectory: true)
            try FileManager.default.createDirectory(at: safety, withIntermediateDirectories: true)
            try BackupService.encode(makeBackup()).write(to: safety.appendingPathComponent("before-restore-\(Self.stamp(withTime: true)).json"), options: .atomic)
        } catch {
            errorMessage = "Restore cancelled: couldn't save a safety copy first (\(error.localizedDescription))."
            return
        }
        let backup = pending.backup
        engine.replaceHistory(with: backup.sessions)
        taskRepo.replaceAll(backup.tasks)
        saveTasksNow()
        usage = backup.usage
        try? store.saveUsage(usage)
        reflections = backup.reflections
        try? store.saveReflections(reflections)
        if var restoredSettings = backup.settings {
            restoredSettings.hasCompletedOnboarding = true
            restoredSettings.lastBackupAt = settings.lastBackupAt
            settings = restoredSettings.sanitized()
        }
        selectedTaskIDs = []
        refresh()
        syncNotifications()
        showToast(TaskToast(kind: .info, title: "Backup restored", detail: "\(pending.preview.taskCount) tasks · \(pending.preview.sessionCount) sessions", nextTask: nil))
    }

    // MARK: - Persistence & shortcuts

    func saveTasksNow() {
        taskSaveWork?.cancel()
        taskSaveWork = nil
        if !taskRepo.save(), let error = taskRepo.lastPersistenceError {
            errorMessage = error
        }
        tasks = taskRepo.tasks
    }

    func scheduleTaskSave() {
        taskSaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.saveTasksNow() }
        }
        taskSaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func ensureRecurringTasks() {
        if !taskRepo.ensureRecurringInstances(at: Date()).isEmpty {
            saveTasksNow()
        }
    }

    func configureShortcuts() {
        var errors: [String] = []
        if let error = hotKeys.set(settings.quickAddShortcut, for: .quickAdd, handler: { [weak self] in
            Task { @MainActor in self?.openWindow?(.quickAdd) }
        }) { errors.append(error) }
        if let error = hotKeys.set(settings.toggleFocusShortcut, for: .toggleFocus, handler: { [weak self] in
            Task { @MainActor in self?.toggleFocus() }
        }) { errors.append(error) }
        if let error = hotKeys.set(settings.openTodayShortcut, for: .openToday, handler: { [weak self] in
            Task { @MainActor in
                self?.taskList = .today
                self?.openWindow?(.tasks)
            }
        }) { errors.append(error) }
        shortcutErrors = errors
    }

    /// Start, pause or resume — whatever "go/stop" means right now.
    func toggleFocus() {
        switch state.phase {
        case .focusing:
            state.isPaused ? resume() : pause()
        case .onBreak:
            state.isPaused ? resume() : pause()
        case .idle, .breakComplete, .breakDue:
            startFocus()
        }
    }

    /// Opens the Tasks window on a specific task.
    func reveal(_ id: UUID) {
        guard let task = self.task(id) else { return }
        if task.status == .completed {
            taskList = .completed
        } else if task.status == .archived {
            taskList = .archived
        } else if !taskRepo.tasks(in: taskList, now: now).contains(where: { $0.id == id }) {
            taskList = taskRepo.tasks(in: .today, now: now).contains(where: { $0.id == id }) ? .today : listKind(for: task.status)
        }
        selectedTaskIDs = [task.parentID ?? id]
        closePopover?()
        openWindow?(.tasks)
    }

    func listKind(for status: TaskStatus) -> TaskListKind {
        switch status {
        case .inbox: return .inbox
        case .today: return .today
        case .next: return .next
        case .someday: return .someday
        case .inProgress: return .inProgress
        case .completed: return .completed
        case .archived: return .archived
        }
    }

    // MARK: - Helpers

    @discardableResult
    func save(_ data: Data, suggestedName: String, type: UTType) -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            errorMessage = "Couldn't save the file: \(error.localizedDescription)"
            return false
        }
    }

    static func stamp(withTime: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = withTime ? "yyyy-MM-dd-HHmmss" : "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    // MARK: - Screenshot support

    func seedTasksForPreview(_ body: (TaskRepository) -> Void) {
        body(taskRepo)
        tasks = taskRepo.tasks
    }
}
