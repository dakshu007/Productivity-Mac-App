import AppKit
import FlowBreakCore
import SwiftUI

/// The Flow Finish control: a ring that fills amber and draws a checkmark.
/// With Reduce Motion on, it changes state without animating.
struct CompletionCheckbox: View {
    var isDone: Bool
    var size: CGFloat = 18
    var action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(isDone ? Palette.accent : Palette.secondaryText.opacity(0.7), lineWidth: 1.5)
                Circle()
                    .fill(Palette.accent)
                    .scaleEffect(isDone ? 1 : 0.2)
                    .opacity(isDone ? 1 : 0)
                CheckmarkShape()
                    .trim(from: 0, to: isDone ? 1 : 0)
                    .stroke(Palette.ink, style: StrokeStyle(lineWidth: max(1.6, size / 10), lineCap: .round, lineJoin: .round))
                    .padding(size * 0.27)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.72), value: isDone)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isDone ? "Completed" : "Mark complete")
        .accessibilityAddTraits(.isButton)
        .help(isDone ? "Reopen" : "Complete")
    }
}

struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.1))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.12))
        return path
    }
}

/// Priority shown with an icon *and* text, never colour alone.
struct PriorityLabel: View {
    var priority: TaskPriority

    var body: some View {
        if priority >= .high {
            Label(priority.displayName, systemImage: priority == .critical ? "exclamationmark.2" : "exclamationmark")
                .labelStyle(.titleAndIcon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(priority == .critical ? Palette.warning : Palette.accentText)
        } else if priority == .low {
            Label("Low", systemImage: "arrow.down")
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.secondaryText)
        }
    }
}

/// Compact metadata chip.
struct MetaChip: View {
    var text: String
    var systemImage: String?
    var tint: Color = Palette.secondaryText

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 9.5)) }
            Text(text).lineLimit(1)
        }
        .font(.system(size: 10.5))
        .foregroundStyle(tint)
    }
}

struct TaskRowView: View {
    @EnvironmentObject private var model: AppModel
    var task: TaskItem
    var showProject = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isDone: Bool { task.status == .completed }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s + 2) {
            CompletionCheckbox(isDone: isDone) {
                isDone ? model.reopen(task.id) : model.requestComplete(task.id)
            }
            .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 13, weight: task.status == .inProgress ? .semibold : .regular))
                    .strikethrough(isDone, color: Palette.secondaryText)
                    .foregroundStyle(isDone ? Palette.secondaryText : Color.primary)
                    .lineLimit(2)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: isDone)
                meta
            }
            Spacer(minLength: Spacing.s)
            if task.isBigThree(on: model.now, calendar: model.calendar) {
                Image(systemName: "star.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.accent)
                    .accessibilityLabel("Big Three")
            }
            if task.isOpen {
                Button {
                    model.presentStartFocus(task)
                } label: {
                    Image(systemName: model.currentTask?.id == task.id ? "timer" : "play.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(model.currentTask?.id == task.id ? Palette.success : Palette.secondaryText)
                }
                .buttonStyle(.plain)
                .help("Start a focus session on this task")
                .accessibilityLabel("Start focus on \(task.title)")
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .opacity(task.status == .archived ? 0.6 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(task.title), \(task.status.displayName)\(task.priority >= .high ? ", \(task.priority.displayName) priority" : "")")
    }

    @ViewBuilder private var meta: some View {
        let subs = model.subtasks(of: task.id)
        let stats = model.focusStats(for: task.id)
        let hasMeta = task.priority != .normal || task.dueAt != nil || task.estimatedMinutes != nil || (showProject && task.project != nil) || !task.tags.isEmpty || !subs.isEmpty || stats.sessions > 0 || task.recurrence != nil || task.status == .inProgress
        if hasMeta {
            HStack(spacing: Spacing.s) {
                if task.status == .inProgress {
                    MetaChip(text: "In progress", systemImage: "circle.lefthalf.filled", tint: Palette.success)
                }
                PriorityLabel(priority: task.priority)
                if let due = task.dueAt {
                    let overdue = task.isOverdue(now: model.now, calendar: model.calendar)
                    MetaChip(
                        text: (overdue ? "Overdue · " : "") + QuickAddParser.formatDay(due, now: model.now, calendar: model.calendar),
                        systemImage: "calendar"
                    )
                }
                if let estimate = task.estimatedMinutes {
                    MetaChip(text: QuickAddParser.formatMinutes(estimate), systemImage: "hourglass")
                }
                if stats.sessions > 0 {
                    MetaChip(text: DurationFormatter.short(stats.time), systemImage: "timer")
                }
                if !subs.isEmpty {
                    MetaChip(text: "\(subs.filter { $0.status == .completed }.count)/\(subs.count)", systemImage: "checklist")
                }
                if task.recurrence != nil {
                    MetaChip(text: "", systemImage: "repeat")
                }
                if showProject, let project = task.project {
                    MetaChip(text: project, systemImage: "folder")
                }
                if !task.tags.isEmpty {
                    MetaChip(text: task.tags.prefix(3).map { "#\($0)" }.joined(separator: " "))
                }
            }
        }
    }
}

/// "Done. You moved this forward." plus undo and one optional next step.
struct TaskToastView: View {
    @EnvironmentObject private var model: AppModel
    var toast: TaskToast
    var compact = false

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.m) {
            if case .completed = toast.kind {
                ZStack {
                    Circle().fill(Palette.accent)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.ink)
                }
                .frame(width: 22, height: 22)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title).font(.system(size: 12.5, weight: .semibold))
                if let detail = toast.detail {
                    Text(detail).font(.system(size: 11)).foregroundStyle(Palette.secondaryText)
                }
            }
            Spacer(minLength: Spacing.s)
            if case .completed = toast.kind, !compact {
                if let next = toast.nextTask {
                    Button("Next: \(next.title)") {
                        model.dismissToast()
                        model.presentStartFocus(next)
                    }
                    .lineLimit(1)
                    .frame(maxWidth: 170)
                    .help("Start focus on your next task")
                }
                if model.state.phase != .onBreak {
                    Button("Take a reset") {
                        model.dismissToast()
                        model.startBreak()
                    }
                }
            }
            if toast.canUndo {
                Button("Undo") { model.undoToast() }
                    .keyboardShortcut("z", modifiers: .command)
            }
            Button {
                model.dismissToast()
            } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.secondaryText)
            .accessibilityLabel("Dismiss")
        }
        .buttonStyle(SmallPillButtonStyle())
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s + 2)
        .background(
            RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
        )
        .overlay(RoundedRectangle(cornerRadius: Radius.large, style: .continuous).strokeBorder(Palette.separator.opacity(0.6), lineWidth: 0.5))
        .accessibilityElement(children: .contain)
    }
}

struct SmallPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Palette.track.opacity(configuration.isPressed ? 1.8 : 1)))
            .contentShape(Capsule())
    }
}

/// Proof of Done: confirm the outcome defined before work began.
struct ProofOfDoneView: View {
    @EnvironmentObject private var model: AppModel
    var task: TaskItem
    @State private var note = ""
    @FocusState private var noteFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.s) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 18))
                    .foregroundStyle(Palette.accentText)
                Text("Proof of Done").font(.system(size: 15, weight: .semibold))
            }
            Text(task.title).font(.system(size: 13, weight: .medium))
            if let dod = task.definitionOfDone {
                VStack(alignment: .leading, spacing: 3) {
                    Text("DONE WHEN").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.secondaryText)
                    Text(dod).font(.system(size: 13))
                }
                .padding(Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Radius.medium).fill(Palette.accent.opacity(0.12)))
            }
            TextField("Result note (optional) — e.g. “PR #42 opened”", text: $note, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
                .focused($noteFocused)
            Text("FlowBreak records what you confirm; it doesn't check the outcome itself.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.secondaryText)
            HStack {
                Button("Not yet") { model.proofRequest = nil }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Complete without note") { model.completeTask(task.id, note: nil, skipProof: true) }
                Button("It's done") { model.completeTask(task.id, note: note, skipProof: true) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent)
                    .foregroundStyle(Palette.ink)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 420)
        .onAppear { noteFocused = true }
    }
}

/// Start focus on a task: title, definition of done, duration, optional intention.
struct StartFocusView: View {
    @EnvironmentObject private var model: AppModel
    var task: TaskItem
    var onDone: () -> Void
    @State private var minutes: Int
    @State private var intent = ""

    init(task: TaskItem, defaultMinutes: Int, onDone: @escaping () -> Void) {
        self.task = task
        self.onDone = onDone
        _minutes = State(initialValue: defaultMinutes)
    }

    private var choices: [Int] {
        var values = Set(AppSettings.focusPresets)
        values.insert(minutes)
        if let estimate = task.estimatedMinutes, estimate <= 120 { values.insert(estimate) }
        return values.sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.s) {
                BrandMark(size: 22)
                Text("Start focus").font(.system(size: 15, weight: .semibold))
            }
            Text(task.title).font(.system(size: 14, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            if let dod = task.definitionOfDone {
                Label("Done when: \(dod)", systemImage: "checkmark.seal")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondaryText)
            }
            if model.state.phase == .focusing {
                Banner(tone: .info, message: "A focus session is already running. Starting here links that session to this task instead of starting a new one.")
            } else {
                Picker("Duration", selection: $minutes) {
                    ForEach(choices, id: \.self) { Text("\($0) min").tag($0) }
                }
                .pickerStyle(.segmented)
            }
            TextField("Intention for this session (optional)", text: $intent)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel") { onDone() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    if model.state.phase == .focusing {
                        model.relinkCurrentSession(to: task.id)
                    } else {
                        model.startFocus(on: task.id, minutes: minutes, intent: intent)
                    }
                    onDone()
                } label: {
                    Label(model.state.phase == .focusing ? "Link Session" : "Start Focus", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(width: 160)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 420)
    }
}

/// Text field + live preview of what Quick Add will interpret.
struct QuickAddField: View {
    @EnvironmentObject private var model: AppModel
    @Binding var text: String
    @Binding var parse: Bool
    var list: TaskListKind
    var placeholder = "Add a task — e.g. Draft report tomorrow #work !high 45m"
    var focused: FocusState<Bool>.Binding
    var onSubmit: (TaskItem?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Spacing.s) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Palette.accent)
                    .font(.system(size: 15))
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused(focused)
                    .onSubmit(submit)
                    .accessibilityLabel("New task")
                Toggle(isOn: $parse) {
                    Image(systemName: "wand.and.stars")
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .help(parse ? "Smart parsing is on: dates, #tags, !priority, estimates and +project are recognised" : "Smart parsing is off: everything becomes the title")
                .accessibilityLabel("Smart parsing")
            }
            if parse && !text.trimmingCharacters(in: .whitespaces).isEmpty {
                let result = QuickAddParser(calendar: model.calendar).parse(text, now: model.now)
                if !result.tokens.isEmpty {
                    TokenPreview(result: result)
                }
            }
        }
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let task = model.addTask(text: trimmed, parse: parse, in: list)
        if task != nil { text = "" }
        onSubmit(task)
    }
}

struct TokenPreview: View {
    var result: QuickAddParser.Result

    var body: some View {
        HStack(spacing: 5) {
            Text("“\(result.title)”")
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            ForEach(Array(result.tokens.enumerated()), id: \.offset) { _, token in
                Text(token.display)
                    .font(.system(size: 10.5, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Palette.accent.opacity(0.18)))
                    .foregroundStyle(Palette.accentText)
                    .help("From “\(token.source)”")
            }
        }
        .padding(.leading, 23)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Will be saved as \(result.title), " + result.tokens.map(\.display).joined(separator: ", "))
    }
}
