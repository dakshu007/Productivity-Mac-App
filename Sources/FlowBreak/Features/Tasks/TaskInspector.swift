import AppKit
import FlowBreakCore
import SwiftUI

/// Details of one task. Edits save automatically shortly after typing stops.
struct TaskInspector: View {
    @EnvironmentObject private var model: AppModel
    var taskID: UUID
    var requestDelete: () -> Void

    @State private var title = ""
    @State private var tagsText = ""
    @State private var newSubtask = ""
    @State private var newNote = ""

    private var task: TaskItem? { model.task(taskID) }

    var body: some View {
        if let task {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    titleSection(task)
                    actions(task)
                    Divider()
                    planning(task)
                    Divider()
                    outcome(task)
                    subtasks(task)
                    progress(task)
                    focusHistory(task)
                    Divider()
                    more(task)
                    metadata(task)
                }
                .padding(Spacing.l)
            }
            .onAppear {
                title = task.title
                tagsText = task.tags.map { "#\($0)" }.joined(separator: " ")
            }
        }
    }

    // MARK: Sections

    private func titleSection(_ task: TaskItem) -> some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            CompletionCheckbox(isDone: task.status == .completed, size: 20) {
                task.status == .completed ? model.reopen(task.id) : model.requestComplete(task.id)
            }
            .padding(.top, 3)
            TextField("Title", text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1...4)
                .onChange(of: title) { value in
                    if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        model.updateTask(task.id) { $0.title = value }
                    }
                }
                .onSubmit { title = model.task(task.id)?.title ?? title }
                .accessibilityLabel("Task title")
        }
    }

    private func actions(_ task: TaskItem) -> some View {
        HStack(spacing: Spacing.s) {
            if task.isOpen {
                Button {
                    model.presentStartFocus(task)
                } label: {
                    Label(model.currentTask?.id == task.id ? "Focusing" : "Start Focus", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.currentTask?.id == task.id)
                Button {
                    model.requestComplete(task.id)
                } label: {
                    Label("Complete", systemImage: "checkmark")
                }
                .buttonStyle(SecondaryButtonStyle())
            } else if task.status == .completed {
                Button { model.reopen(task.id) } label: { Label("Reopen", systemImage: "arrow.uturn.backward") }
                    .buttonStyle(SecondaryButtonStyle())
            } else {
                Button { model.restore([task.id]) } label: { Label("Restore", systemImage: "tray.and.arrow.up") }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private func planning(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            field("List") {
                Picker("List", selection: Binding(
                    get: { task.status },
                    set: { model.setStatus([task.id], $0) }
                )) {
                    ForEach([TaskStatus.inbox, .today, .next, .inProgress, .someday], id: \.self) { Text($0.displayName).tag($0) }
                    if !task.isOpen { Text(task.status.displayName).tag(task.status) }
                }
                .labelsHidden()
                .disabled(!task.isOpen)
            }
            field("Priority") {
                Picker("Priority", selection: Binding(
                    get: { task.priority },
                    set: { value in model.updateTask(task.id) { $0.priority = value } }
                )) {
                    ForEach(TaskPriority.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
            }
            field("Due") {
                HStack {
                    if let due = task.dueAt {
                        DatePicker("Due", selection: Binding(
                            get: { due },
                            set: { value in model.updateTask(task.id) { $0.dueAt = model.calendar.startOfDay(for: value) } }
                        ), displayedComponents: .date)
                        .labelsHidden()
                        Button { model.updateTask(task.id) { $0.dueAt = nil } } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .foregroundStyle(Palette.secondaryText)
                            .accessibilityLabel("Clear due date")
                        if task.isOverdue(now: model.now, calendar: model.calendar) {
                            Text("Overdue").font(.system(size: 11)).foregroundStyle(Palette.secondaryText)
                        }
                    } else {
                        Button("Today") { model.updateTask(task.id) { $0.dueAt = model.calendar.startOfDay(for: Date()) } }
                        Button("Tomorrow") {
                            let tomorrow = model.calendar.date(byAdding: .day, value: 1, to: model.calendar.startOfDay(for: Date()))
                            model.updateTask(task.id) { $0.dueAt = tomorrow }
                        }
                    }
                }
                .controlSize(.small)
            }
            field("Estimate") {
                Stepper(value: Binding(
                    get: { task.estimatedMinutes ?? 0 },
                    set: { value in model.updateTask(task.id) { $0.estimatedMinutes = value > 0 ? value : nil } }
                ), in: 0...600, step: 15) {
                    Text(task.estimatedMinutes.map { QuickAddParser.formatMinutes($0) } ?? "None")
                        .monospacedDigit()
                }
            }
            field("Repeat") {
                Picker("Repeat", selection: Binding(
                    get: { task.recurrence },
                    set: { value in model.updateTask(task.id) { $0.recurrence = value } }
                )) {
                    Text("Never").tag(RecurrenceRule?.none)
                    ForEach(RecurrenceRule.allCases, id: \.self) { Text($0.displayName).tag(RecurrenceRule?.some($0)) }
                }
                .labelsHidden()
            }
            field("Project") {
                TextField("None", text: Binding(
                    get: { task.project ?? "" },
                    set: { value in model.updateTask(task.id) { $0.project = value.isEmpty ? nil : value } }
                ))
                .textFieldStyle(.roundedBorder)
            }
            field("Tags") {
                TextField("#tag #another", text: $tagsText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: tagsText) { value in
                        let tags = value.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
                        model.updateTask(task.id) { $0.tags = tags }
                    }
            }
            Toggle(isOn: Binding(
                get: { task.isBigThree(on: model.now, calendar: model.calendar) },
                set: { model.setBigThree(task.id, $0) }
            )) {
                Label("One of today's Big Three", systemImage: "star")
            }
            .disabled(!task.isOpen)
        }
        .font(.system(size: 12.5))
    }

    private func outcome(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            sectionTitle("Proof of Done", icon: "checkmark.seal")
            TextField("Done when… (e.g. “Email sent to Priya”)", text: Binding(
                get: { task.definitionOfDone ?? "" },
                set: { value in model.updateTask(task.id) { $0.definitionOfDone = value.isEmpty ? nil : value } }
            ), axis: .vertical)
            .lineLimit(1...3)
            .textFieldStyle(.roundedBorder)
            if let note = task.completionNote, task.status == .completed {
                Label("Result: \(note)", systemImage: "text.quote")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondaryText)
            }
            sectionTitle("Notes", icon: "note.text")
            TextEditor(text: Binding(
                get: { task.notes ?? "" },
                set: { value in model.updateTask(task.id) { $0.notes = value.isEmpty ? nil : value } }
            ))
            .font(.system(size: 12.5))
            .frame(minHeight: 70, maxHeight: 140)
            .scrollContentBackground(.hidden)
            .padding(4)
            .background(RoundedRectangle(cornerRadius: Radius.small).fill(Palette.track.opacity(0.6)))
            .accessibilityLabel("Notes")
        }
    }

    @ViewBuilder private func subtasks(_ task: TaskItem) -> some View {
        let subs = model.subtasks(of: task.id)
        VStack(alignment: .leading, spacing: Spacing.s) {
            sectionTitle(subs.isEmpty ? "Subtasks" : "Subtasks · \(subs.filter { $0.status == .completed }.count)/\(subs.count)", icon: "checklist")
            ForEach(subs) { sub in
                HStack(spacing: Spacing.s) {
                    CompletionCheckbox(isDone: sub.status == .completed, size: 15) {
                        sub.status == .completed ? model.reopen(sub.id) : model.requestComplete(sub.id)
                    }
                    Text(sub.title)
                        .font(.system(size: 12.5))
                        .strikethrough(sub.status == .completed)
                        .foregroundStyle(sub.status == .completed ? Palette.secondaryText : Color.primary)
                    Spacer()
                    Button { model.deletePermanently([sub.id]) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.secondaryText)
                        .accessibilityLabel("Delete subtask \(sub.title)")
                }
            }
            if task.isOpen {
                TextField("Add a subtask", text: $newSubtask)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        model.addSubtask(to: task.id, title: newSubtask)
                        newSubtask = ""
                    }
            }
        }
    }

    @ViewBuilder private func progress(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            sectionTitle("Progress notes", icon: "text.badge.plus")
            ForEach(task.progressNotes.reversed()) { note in
                VStack(alignment: .leading, spacing: 1) {
                    Text(note.text).font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true)
                    Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.secondaryText)
                }
            }
            TextField("What moved forward?", text: $newNote)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    model.addProgressNote(task.id, text: newNote)
                    newNote = ""
                }
        }
    }

    @ViewBuilder private func focusHistory(_ task: TaskItem) -> some View {
        let linked = model.linkedSessions(for: task.id)
        let stats = model.focusStats(for: task.id)
        VStack(alignment: .leading, spacing: Spacing.s) {
            sectionTitle("Focus", icon: "timer")
            if linked.isEmpty {
                Text(task.estimatedMinutes.map { "Estimated \(QuickAddParser.formatMinutes($0)). No focus sessions recorded yet." } ?? "No focus sessions recorded yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondaryText)
            } else {
                HStack(spacing: Spacing.l) {
                    MetricView(title: "Focused", value: DurationFormatter.short(stats.time), help: "Un-paused time in focus sessions linked to this task. Breaks never count.", compact: true)
                    MetricView(title: "Sessions", value: "\(stats.sessions)", compact: true)
                    MetricView(title: "Estimate", value: task.estimatedMinutes.map { QuickAddParser.formatMinutes($0) } ?? "—", compact: true)
                }
                ForEach(linked.prefix(6)) { session in
                    HStack {
                        Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                        Spacer()
                        Text(DurationFormatter.short(session.actualDuration ?? session.activeDuration(asOf: model.now))).monospacedDigit()
                        Text(session.outcome?.displayName ?? session.status.displayName)
                            .foregroundStyle(Palette.secondaryText)
                            .frame(width: 92, alignment: .trailing)
                    }
                    .font(.system(size: 11.5))
                    .help(session.progressNote ?? session.intent ?? "")
                }
            }
        }
    }

    private func more(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            field("Link") {
                HStack {
                    TextField("URL or file path", text: Binding(
                        get: { task.link ?? "" },
                        set: { value in model.updateTask(task.id) { $0.link = value.isEmpty ? nil : value } }
                    ))
                    .textFieldStyle(.roundedBorder)
                    if task.link?.isEmpty == false {
                        Button("Open") { model.openLink(task.id) }.controlSize(.small)
                    }
                }
            }
            Toggle(isOn: Binding(get: { task.isPrivate }, set: { value in model.updateTask(task.id) { $0.isPrivate = value } })) {
                Label("Private — hide the title in Insights and summaries", systemImage: "eye.slash")
            }
            HStack(spacing: Spacing.s) {
                Button("Duplicate") { model.duplicate(task.id) }
                Button("Copy Markdown") { model.copyMarkdown(task.id) }
                Spacer()
                if task.status != .archived {
                    Button("Archive") { model.archive([task.id]) }
                }
                Button("Delete…", role: .destructive) { requestDelete() }
            }
            .controlSize(.small)
        }
        .font(.system(size: 12.5))
    }

    private func metadata(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Created \(task.createdAt.formatted(date: .abbreviated, time: .shortened))")
            if task.updatedAt != task.createdAt { Text("Updated \(task.updatedAt.formatted(date: .abbreviated, time: .shortened))") }
            if let completed = task.completedAt { Text("Completed \(completed.formatted(date: .abbreviated, time: .shortened))") }
            if let archived = task.archivedAt { Text("Archived \(archived.formatted(date: .abbreviated, time: .shortened))") }
        }
        .font(.system(size: 10.5))
        .foregroundStyle(Palette.secondaryText)
    }

    // MARK: Helpers

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Text(label)
                .foregroundStyle(Palette.secondaryText)
                .frame(width: 62, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func sectionTitle(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Palette.secondaryText)
    }
}
