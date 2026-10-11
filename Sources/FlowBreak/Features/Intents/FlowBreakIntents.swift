import AppIntents
import FlowBreakCore
import Foundation

/// Gives App Intents access to the running app model. If the system launches
/// FlowBreak to run an intent, this waits briefly for the app to finish launching.
@MainActor
enum IntentBridge {
    static weak var model: AppModel?

    static func appModel() async throws -> AppModel {
        for _ in 0..<40 {
            if let model { return model }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw IntentFailure.notReady
    }
}

enum IntentFailure: Error, CustomLocalizedStringResourceConvertible {
    case notReady
    case taskNotFound
    case emptyTitle

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notReady: return "FlowBreak isn't ready yet. Try again in a moment."
        case .taskNotFound: return "That task couldn't be found."
        case .emptyTitle: return "The task needs a title."
        }
    }
}

// MARK: - Task entity

struct TaskEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Task"
    static let defaultQuery = TaskEntityQuery()

    var id: UUID
    var title: String
    var subtitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)")
    }

    init(_ task: TaskItem) {
        id = task.id
        title = task.title
        subtitle = task.status.displayName
    }
}

struct TaskEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [TaskEntity] {
        await MainActor.run {
            guard let model = IntentBridge.model else { return [] }
            return identifiers.compactMap { model.task($0) }.map(TaskEntity.init)
        }
    }

    func entities(matching string: String) async throws -> [TaskEntity] {
        await MainActor.run {
            guard let model = IntentBridge.model else { return [] }
            return model.taskRepo.search(string).filter(\.isOpen).prefix(20).map(TaskEntity.init)
        }
    }

    func suggestedEntities() async throws -> [TaskEntity] {
        let model = try await IntentBridge.appModel()
        return await MainActor.run { model.focusCandidates.map(TaskEntity.init) }
    }
}

enum TaskListChoice: String, AppEnum {
    case inbox
    case today

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "List"
    static let caseDisplayRepresentations: [TaskListChoice: DisplayRepresentation] = [
        .inbox: "Inbox",
        .today: "Today",
    ]
}

// MARK: - Focus intents

struct StartFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Focus"
    static let description = IntentDescription("Starts a FlowBreak focus session, optionally on a task.")

    @Parameter(title: "Task")
    var task: TaskEntity?

    @Parameter(title: "Minutes")
    var minutes: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("Start focus on \(\.$task) for \(\.$minutes) minutes")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = try await IntentBridge.appModel()
        if let task, model.task(task.id) == nil { throw IntentFailure.taskNotFound }
        let taskID = task?.id ?? model.nextTask?.id
        model.startFocus(on: taskID, minutes: minutes.map { min(max($0, 1), 240) }, intent: nil)
        let title = model.task(taskID)?.title
        let length = DurationFormatter.short(model.remaining)
        return .result(dialog: IntentDialog(stringLiteral: title.map { "Focusing on \($0) for \(length)." } ?? "Focus started for \(length)."))
    }
}

struct PauseResumeFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause or Resume Focus"
    static let description = IntentDescription("Pauses a running session or resumes a paused one. Starts focus if nothing is running.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = try await IntentBridge.appModel()
        model.toggleFocus()
        let message: String
        switch model.state.phase {
        case .focusing, .onBreak:
            message = model.state.isPaused ? "Paused with \(DurationFormatter.clock(model.remaining)) left." : "Running — \(DurationFormatter.clock(model.remaining)) left."
        default:
            message = "Ready."
        }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct StopFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Focus"
    static let description = IntentDescription("Stops the current focus session or break.")

    @MainActor
    func perform() async throws -> some IntentResult {
        let model = try await IntentBridge.appModel()
        model.stop()
        return .result()
    }
}

struct TakeBreakIntent: AppIntent {
    static let title: LocalizedStringResource = "Take a Break"
    static let description = IntentDescription("Starts a FlowBreak break.")

    @MainActor
    func perform() async throws -> some IntentResult {
        let model = try await IntentBridge.appModel()
        model.startBreak(openPanel: false)
        return .result()
    }
}

struct FocusStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Focus Status"
    static let description = IntentDescription("Tells you what FlowBreak is doing and how much time is left.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let model = try await IntentBridge.appModel()
        let status: String
        switch model.state.phase {
        case .idle: status = "Ready to focus."
        case .focusing:
            let task = model.currentTask.map { " on \($0.title)" } ?? ""
            status = model.state.isPaused ? "Focus\(task) is paused with \(DurationFormatter.clock(model.remaining)) left." : "Focusing\(task), \(DurationFormatter.clock(model.remaining)) left."
        case .breakDue: status = "A break is due."
        case .onBreak: status = "On a break, \(DurationFormatter.clock(model.remaining)) left."
        case .breakComplete: status = "Break finished — ready when you are."
        }
        return .result(value: status, dialog: IntentDialog(stringLiteral: status))
    }
}

// MARK: - Task intents

struct AddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Task"
    static let description = IntentDescription("Adds a task to FlowBreak. Smart parsing understands dates, #tags, !priority, estimates like 30m and +project.")

    @Parameter(title: "Task")
    var text: String

    @Parameter(title: "List", default: .inbox)
    var list: TaskListChoice

    @Parameter(title: "Smart Parsing", default: true)
    var parse: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$text) to \(\.$list)") {
            \.$parse
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<TaskEntity> & ProvidesDialog {
        let model = try await IntentBridge.appModel()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw IntentFailure.emptyTitle }
        guard let task = model.addTask(text: text, parse: parse, in: list == .today ? .today : .inbox) else {
            throw IntentFailure.emptyTitle
        }
        return .result(value: TaskEntity(task), dialog: IntentDialog(stringLiteral: "Added “\(task.title)” to \(task.status.displayName)."))
    }
}

struct CompleteTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Task"
    static let description = IntentDescription("Marks a FlowBreak task as complete.")

    @Parameter(title: "Task")
    var task: TaskEntity

    @Parameter(title: "Result Note")
    var note: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = try await IntentBridge.appModel()
        guard let item = model.task(task.id) else { throw IntentFailure.taskNotFound }
        guard item.isOpen else { return .result(dialog: IntentDialog(stringLiteral: "“\(item.title)” is already complete.")) }
        model.completeTask(item.id, note: note, skipProof: true)
        return .result(dialog: IntentDialog(stringLiteral: "Done. “\(item.title)” is complete."))
    }
}

struct BigThreeIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Today's Big Three"
    static let description = IntentDescription("Lists the tasks you starred as today's Big Three (or your top Today tasks if none are starred).")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[TaskEntity]> & ProvidesDialog {
        let model = try await IntentBridge.appModel()
        var tasks = model.bigThreeToday.filter(\.isOpen)
        let starred = !tasks.isEmpty
        if tasks.isEmpty { tasks = Array(model.focusCandidates.prefix(3)) }
        let message: String
        if tasks.isEmpty {
            message = "Nothing is planned for today yet."
        } else {
            let list = tasks.enumerated().map { "\($0.offset + 1). \($0.element.title)" }.joined(separator: "\n")
            message = (starred ? "Today's Big Three:\n" : "Top tasks for today:\n") + list
        }
        return .result(value: tasks.map(TaskEntity.init), dialog: IntentDialog(stringLiteral: message))
    }
}

struct OpenTasksIntent: AppIntent {
    static let title: LocalizedStringResource = "Open FlowBreak Tasks"
    static let description = IntentDescription("Opens the FlowBreak Tasks window on Today.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let model = try await IntentBridge.appModel()
        model.taskList = .today
        model.openWindow?(.tasks)
        return .result()
    }
}

// MARK: - Shortcuts app & Siri phrases

struct FlowBreakShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartFocusIntent(),
            phrases: ["Start focus in \(.applicationName)", "Start a \(.applicationName) session"]
        )
        AppShortcut(
            intent: PauseResumeFocusIntent(),
            phrases: ["Pause \(.applicationName)", "Resume \(.applicationName)"]
        )
        AppShortcut(
            intent: TakeBreakIntent(),
            phrases: ["Take a break with \(.applicationName)"]
        )
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: ["Add a task to \(.applicationName)", "Add a \(.applicationName) task"]
        )
        AppShortcut(
            intent: BigThreeIntent(),
            phrases: ["What's my Big Three in \(.applicationName)", "Show \(.applicationName) priorities"]
        )
        AppShortcut(
            intent: FocusStatusIntent(),
            phrases: ["How much focus is left in \(.applicationName)"]
        )
    }
}
