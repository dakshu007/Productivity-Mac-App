import AppKit
import FlowBreakCore
import SwiftUI

/// The Tasks window: lists on the left, tasks in the middle, details on the right.
struct TasksView: View {
    @EnvironmentObject private var model: AppModel
    @State private var search = ""
    @State private var quickText = ""
    @State private var parse = true
    @State private var confirmDelete: [UUID] = []
    @FocusState private var quickAddFocused: Bool

    private var activeList: TaskListKind {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? model.taskList : .search(query)
    }

    var body: some View {
        HStack(spacing: 0) {
            TaskSidebar(search: $search)
                .frame(width: 196)
            Divider()
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, Spacing.l)
                    .padding(.top, Spacing.m)
                QuickAddField(text: $quickText, parse: $parse, list: model.taskList, focused: $quickAddFocused) { _ in }
                    .padding(.horizontal, Spacing.l)
                    .padding(.vertical, Spacing.s + 2)
                    .disabled(isReadOnlyList)
                    .opacity(isReadOnlyList ? 0.4 : 1)
                Divider()
                taskList
                if model.selectedTaskIDs.count > 1 {
                    Divider()
                    bulkBar
                }
            }
            .frame(minWidth: 380)
            Divider()
            Group {
                if model.selectedTaskIDs.count == 1, let id = model.selectedTaskIDs.first, model.task(id) != nil {
                    TaskInspector(taskID: id, requestDelete: { confirmDelete = [id] })
                        .id(id)
                } else if model.selectedTaskIDs.count > 1 {
                    EmptyStateView(systemImage: "square.stack", title: "\(model.selectedTaskIDs.count) tasks selected", message: "Use the bar below the list to complete, move or archive them together.")
                } else {
                    EmptyStateView(systemImage: "sidebar.right", title: "No task selected", message: "Select a task to see its details, subtasks, progress notes and focus history.")
                }
            }
            .frame(width: 310)
            .frame(maxHeight: .infinity)
            .background(Palette.canvas.opacity(0.5))
        }
        .frame(minWidth: 900, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                TaskToastView(toast: toast)
                    .frame(maxWidth: 620)
                    .padding(.bottom, Spacing.l)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(item: $model.focusSheetTask) { task in
            StartFocusView(task: task, defaultMinutes: model.settings.timerMode == .pomodoro ? model.settings.pomodoroWorkMinutes : model.settings.focusMinutes) {
                model.focusSheetTask = nil
            }
            .environmentObject(model)
        }
        .sheet(item: $model.proofRequest) { task in
            ProofOfDoneView(task: task).environmentObject(model)
        }
        .confirmationDialog(
            confirmDelete.count == 1 ? "Delete this task permanently?" : "Delete \(confirmDelete.count) tasks permanently?",
            isPresented: Binding(get: { !confirmDelete.isEmpty }, set: { if !$0 { confirmDelete = [] } })
        ) {
            Button("Delete", role: .destructive) {
                model.deletePermanently(confirmDelete)
                confirmDelete = []
            }
            Button("Archive Instead") {
                model.archive(confirmDelete)
                confirmDelete = []
            }
        } message: {
            Text("Subtasks are deleted too. Focus history is kept. You can undo right after, but archiving is the safer choice.")
        }
        .background(shortcuts)
    }

    private var isReadOnlyList: Bool {
        switch activeList {
        case .completed, .archived, .search: return true
        default: return false
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(activeList.title).font(.system(size: 20, weight: .semibold))
                Text("\(model.visibleTasks(activeList).count)")
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(Palette.secondaryText)
                Spacer()
            }
            if activeList == .today {
                workload
            } else if case .search = activeList {
                Text("Searching titles, notes, Done-when, projects and #tags").font(.system(size: 11.5)).foregroundStyle(Palette.secondaryText)
            }
        }
    }

    @ViewBuilder private var workload: some View {
        let w = model.todayWorkload
        if w.planned > 0 || w.unestimated > 0 {
            HStack(spacing: Spacing.s) {
                Image(systemName: "hourglass").font(.system(size: 10.5))
                Text("About \(QuickAddParser.formatMinutes(max(w.planned, 1))) estimated\(w.unestimated > 0 ? " (+\(w.unestimated) without estimate)" : "") · \(QuickAddParser.formatMinutes(max(w.minutesLeft, 0))) left in your workday")
                    .lineLimit(1)
            }
            .font(.system(size: 11.5))
            .foregroundStyle(Palette.secondaryText)
            if w.planned > w.minutesLeft && w.minutesLeft > 0 {
                Text("That's more than the time left today — it's fine to move something to tomorrow.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.warning)
            }
        } else {
            Text(model.now.formatted(date: .complete, time: .omitted))
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.secondaryText)
        }
    }

    // MARK: List

    @ViewBuilder private var taskList: some View {
        let items = model.visibleTasks(activeList)
        if items.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $model.selectedTaskIDs) {
                if activeList == .today {
                    let big = items.filter { $0.isBigThree(on: model.now, calendar: model.calendar) }
                    let rest = items.filter { !$0.isBigThree(on: model.now, calendar: model.calendar) }
                    if !big.isEmpty {
                        Section("Big Three") { rows(big) }
                    }
                    Section(big.isEmpty ? "Today" : "Also today") {
                        rows(rest)
                        if big.isEmpty && !rest.isEmpty {
                            Text("Tip: star up to three tasks that matter most today (right-click › Add to Big Three).")
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.secondaryText)
                        }
                    }
                } else {
                    rows(items)
                }
            }
            .listStyle(.inset)
            .onDeleteCommand { model.archive(Array(model.selectedTaskIDs)) }
        }
    }

    private func rows(_ items: [TaskItem]) -> some View {
        let reorder: ((IndexSet, Int) -> Void)? = canReorder ? { from, to in
            var ids = items.map(\.id)
            ids.move(fromOffsets: from, toOffset: to)
            model.reorder(ids)
        } : nil
        return ForEach(items) { task in
            TaskRowView(task: task, showProject: !isProjectList)
                .tag(task.id)
                .contextMenu { TaskContextMenu(task: task, requestDelete: { confirmDelete = [task.id] }) }
        }
        .onMove(perform: reorder)
    }

    private var isProjectList: Bool {
        if case .project = activeList { return true }
        return false
    }

    private var canReorder: Bool {
        switch activeList {
        case .inbox, .next, .someday, .inProgress, .project: return true
        default: return false
        }
    }

    @ViewBuilder private var emptyState: some View {
        switch activeList {
        case .today:
            EmptyStateView(systemImage: "sun.max", title: "Nothing planned for today", message: "Add one task you'd like to finish today. You can also move tasks here from your Inbox.", actionTitle: "Add a Task") { quickAddFocused = true }
        case .inbox:
            EmptyStateView(systemImage: "tray", title: "Inbox is empty", message: "Capture ideas here quickly, then decide later what to do with them.", actionTitle: "Add a Task") { quickAddFocused = true }
        case .completed:
            EmptyStateView(systemImage: "checkmark.circle", title: "No completed tasks yet", message: "Finished tasks show up here, newest first. You can reopen any of them.")
        case .archived:
            EmptyStateView(systemImage: "archivebox", title: "Archive is empty", message: "Archived tasks are hidden from your lists but keep their history.")
        case .search:
            EmptyStateView(systemImage: "magnifyingglass", title: "No matches", message: "Try fewer words, or search a tag with #tag.")
        default:
            EmptyStateView(systemImage: "list.bullet", title: "No tasks here", message: "Add a task above.", actionTitle: "Add a Task") { quickAddFocused = true }
        }
    }

    // MARK: Bulk actions

    private var bulkBar: some View {
        let ids = Array(model.selectedTaskIDs)
        return HStack(spacing: Spacing.s) {
            Text("\(ids.count) selected").font(.system(size: 12, weight: .medium))
            Spacer()
            Button("Complete") { model.setStatus(ids, .completed) }
            Menu("Move to") {
                ForEach([TaskStatus.today, .next, .inbox, .someday], id: \.self) { status in
                    Button(status.displayName) { model.setStatus(ids, status) }
                }
            }
            .fixedSize()
            Button("Archive") { model.archive(ids) }
            Button("Delete…", role: .destructive) { confirmDelete = ids }
        }
        .controlSize(.small)
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
    }

    // MARK: Keyboard

    /// Invisible buttons that give the window its keyboard shortcuts.
    private var shortcuts: some View {
        ZStack {
            Button("New Task") { quickAddFocused = true }.keyboardShortcut("n", modifiers: .command)
            Button("Find") { model.focusSearch = true }.keyboardShortcut("f", modifiers: .command)
            Button("Complete Selected") {
                for id in model.selectedTaskIDs { model.requestComplete(id) }
            }
            .keyboardShortcut(.return, modifiers: .command)
            Button("Start Focus on Selected") {
                if let id = model.selectedTaskIDs.first, let task = model.task(id), task.isOpen { model.presentStartFocus(task) }
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}

struct TaskSidebar: View {
    @EnvironmentObject private var model: AppModel
    @Binding var search: String
    @FocusState private var searchFocused: Bool

    private let lists: [(TaskListKind, String)] = [
        (.today, "sun.max"), (.inbox, "tray"), (.next, "arrow.right.circle"),
        (.inProgress, "circle.lefthalf.filled"), (.someday, "moon.stars"),
        (.completed, "checkmark.circle"), (.archived, "archivebox"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.secondaryText).font(.system(size: 11))
                TextField("Search", text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .focused($searchFocused)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.secondaryText)
                        .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: Radius.small + 1).fill(Palette.track))
            .padding(.bottom, Spacing.s)
            .onChange(of: model.focusSearch) { requested in
                if requested {
                    searchFocused = true
                    model.focusSearch = false
                }
            }

            ForEach(lists.indices, id: \.self) { index in
                row(lists[index].0, icon: lists[index].1)
            }
            if !model.projects.isEmpty {
                Text("PROJECTS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.secondaryText)
                    .padding(.top, Spacing.m)
                    .padding(.leading, 8)
                ForEach(model.projects, id: \.self) { name in
                    row(.project(name), icon: "folder")
                }
            }
            Spacer()
            Button {
                model.openWindow?(.quickAdd)
            } label: {
                Label("Quick Add", systemImage: "plus")
            }
            .buttonStyle(FooterButtonStyle())
            .help(model.settings.quickAddShortcut == .off ? "Set a global shortcut in Settings › Tasks" : "Global shortcut: \(model.settings.quickAddShortcut.displayName)")
        }
        .padding(Spacing.m)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.canvas.opacity(0.6))
    }

    private func row(_ list: TaskListKind, icon: String) -> some View {
        let selected = model.taskList == list && search.isEmpty
        let count = model.count(for: list)
        return Button {
            search = ""
            model.taskList = list
            model.selectedTaskIDs = []
        } label: {
            HStack(spacing: Spacing.s) {
                Image(systemName: icon)
                    .frame(width: 16)
                    .foregroundStyle(selected ? Palette.accentText : Palette.secondaryText)
                Text(list.title).lineLimit(1)
                Spacer()
                if count > 0 && list != .completed && list != .archived {
                    Text("\(count)").font(.system(size: 11).monospacedDigit()).foregroundStyle(Palette.secondaryText)
                }
            }
            .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: Radius.small + 1).fill(selected ? Palette.track : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(list.title), \(count) tasks")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

struct TaskContextMenu: View {
    @EnvironmentObject private var model: AppModel
    var task: TaskItem
    var requestDelete: () -> Void

    var body: some View {
        if task.isOpen {
            Button("Start Focus…") { model.presentStartFocus(task) }
            Button("Complete") { model.requestComplete(task.id) }
            Divider()
            let big = task.isBigThree(on: model.now, calendar: model.calendar)
            Button(big ? "Remove from Big Three" : "Add to Big Three") { model.setBigThree(task.id, !big) }
            Menu("Move to") {
                ForEach([TaskStatus.today, .next, .inbox, .someday], id: \.self) { status in
                    Button(status.displayName) { model.setStatus([task.id], status) }
                        .disabled(task.status == status)
                }
            }
            Menu("Priority") {
                ForEach(TaskPriority.allCases.reversed(), id: \.self) { priority in
                    Button(priority.displayName) { model.updateTask(task.id) { $0.priority = priority } }
                }
            }
        } else if task.status == .completed {
            Button("Reopen") { model.reopen(task.id) }
        } else {
            Button("Restore") { model.restore([task.id]) }
        }
        Divider()
        Button("Duplicate") { model.duplicate(task.id) }
        Button("Copy as Markdown") { model.copyMarkdown(task.id) }
        if task.link?.isEmpty == false {
            Button("Open Link") { model.openLink(task.id) }
        }
        Divider()
        if task.status != .archived {
            Button("Archive") { model.archive([task.id]) }
        }
        Button("Delete…", role: .destructive) { requestDelete() }
    }
}
