import AppKit
import FlowBreakCore
import SwiftUI

/// Update availability / opt-in prompt shown at the top of the popover.
struct UpdateBanner: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        switch model.updateState {
        case let .available(manifest):
            bannerBox(icon: "arrow.down.circle.fill", tint: Palette.accentText) {
                Text("FlowBreak \(manifest.version) (build \(manifest.build)) is available.")
                    .font(.system(size: 11.5, weight: .medium))
                HStack(spacing: 6) {
                    Button("Download & Open") { model.downloadUpdate() }
                    if let notes = manifest.releaseNotesURL {
                        Button("What's new") { NSWorkspace.shared.open(notes) }
                    }
                    Button("Later") { model.dismissUpdate() }
                }
                .buttonStyle(SmallPillButtonStyle())
            }
        case .downloading:
            bannerBox(icon: "arrow.down.circle", tint: Palette.secondaryText) {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Downloading the update…").font(.system(size: 11.5))
                }
            }
        case let .downloaded(file):
            bannerBox(icon: "checkmark.circle.fill", tint: Palette.success) {
                Text("The update was checked and opened. Quit FlowBreak, then drag the new version to Applications.")
                    .font(.system(size: 11.5))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
                    Button("Quit FlowBreak") { NSApp.terminate(nil) }
                    Button("Dismiss") { model.dismissUpdate() }
                }
                .buttonStyle(SmallPillButtonStyle())
            }
        case let .unsupported(manifest):
            bannerBox(icon: "info.circle.fill", tint: Palette.secondaryText) {
                Text("FlowBreak \(manifest.version) needs macOS \(manifest.minimumSystemVersion ?? "a newer version").")
                    .font(.system(size: 11.5))
                Button("Dismiss") { model.dismissUpdate() }.buttonStyle(SmallPillButtonStyle())
            }
        default:
            if model.shouldAskAboutUpdates {
                bannerBox(icon: "arrow.triangle.2.circlepath", tint: Palette.secondaryText) {
                    Text("Check for FlowBreak updates once a day? This contacts GitHub; nothing about you is sent.")
                        .font(.system(size: 11.5))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Button("Turn On") { model.answerUpdatePrompt(enable: true) }
                        Button("Not Now") { model.answerUpdatePrompt(enable: false) }
                    }
                    .buttonStyle(SmallPillButtonStyle())
                }
            }
        }
    }

    private func bannerBox<Content: View>(icon: String, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: icon).foregroundStyle(tint).font(.system(size: 13))
            VStack(alignment: .leading, spacing: 6) { content() }
            Spacer(minLength: 0)
        }
        .padding(Spacing.s + 2)
        .background(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).fill(Palette.track.opacity(0.7)))
    }
}

/// Meeting context under the timer: current meeting, or the next one and whether
/// a session would run into it.
struct MeetingStrip: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let time = Date.FormatStyle(date: .omitted, time: .shortened)
        if let meeting = model.currentMeeting {
            label(
                icon: "person.2.fill",
                text: "In “\(meeting.title)” until \(meeting.interval.end.formatted(time))" + (model.settings.holdRemindersDuringMeetings ? " · reminders held" : ""),
                tint: Palette.secondaryText
            )
        } else if let next = model.nextMeeting, next.interval.start.timeIntervalSince(model.now) < 3 * 3600 {
            let minutesAway = max(1, Int(next.interval.start.timeIntervalSince(model.now) / 60))
            let focusMinutes = Int(model.configuration.focusDuration / 60)
            let conflict = (model.state.phase == .idle || model.state.phase == .breakComplete) && minutesAway < focusMinutes
            VStack(alignment: .leading, spacing: 2) {
                label(icon: "calendar", text: "Next: \(next.title) at \(next.interval.start.formatted(time)) (in \(QuickAddParser.formatMinutes(minutesAway)))", tint: Palette.secondaryText)
                if conflict {
                    label(icon: "exclamationmark.circle", text: "A \(focusMinutes)-min session would run into it — try \(max(5, minutesAway - 5)) min.", tint: Palette.warning)
                }
            }
        }
    }

    private func label(icon: String, text: String, tint: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 11))
            .foregroundStyle(tint)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Puts a task on the calendar as a focus block.
struct ScheduleBlockView: View {
    @EnvironmentObject private var model: AppModel
    var task: TaskItem
    var onDone: () -> Void
    @State private var start: Date
    @State private var minutes: Int
    @State private var calendarID: String?
    @State private var error: String?
    @State private var saving = false

    init(task: TaskItem, suggestedStart: Date, onDone: @escaping () -> Void) {
        self.task = task
        self.onDone = onDone
        _start = State(initialValue: suggestedStart)
        _minutes = State(initialValue: min(max(task.estimatedMinutes ?? 45, 15), 240))
        _calendarID = State(initialValue: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Label("Schedule a focus block", systemImage: "calendar.badge.plus")
                .font(.system(size: 15, weight: .semibold))
            Text(task.title).font(.system(size: 13, weight: .medium))
            DatePicker("Starts", selection: $start, displayedComponents: [.date, .hourAndMinute])
            Stepper(value: $minutes, in: 15...240, step: 15) {
                HStack {
                    Text("Length")
                    Spacer()
                    Text(QuickAddParser.formatMinutes(minutes)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            let writable = model.calendarList.filter(\.allowsWriting)
            if !writable.isEmpty {
                Picker("Calendar", selection: $calendarID) {
                    Text("Default").tag(String?.none)
                    ForEach(writable) { cal in Text("\(cal.title) — \(cal.source)").tag(String?.some(cal.id)) }
                }
            }
            if let conflict = model.settings.calendarAwareness ? CalendarPlanning.firstConflict(model.busyBlocks, start: start, duration: TimeInterval(minutes * 60)) : nil {
                Label("Overlaps “\(conflict.title)”", systemImage: "exclamationmark.circle")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.warning)
            }
            if let error {
                Text(error).font(.system(size: 11.5)).foregroundStyle(Color(nsColor: .systemRed)).fixedSize(horizontal: false, vertical: true)
            }
            Text("Adds “Focus: \(task.title)” to your calendar. FlowBreak needs calendar access for this.")
                .font(.system(size: 11)).foregroundStyle(Palette.secondaryText)
            HStack {
                Button("Cancel") { onDone() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    saving = true
                    Task { @MainActor in
                        error = await model.scheduleFocusBlock(for: task, start: start, minutes: minutes, calendarID: calendarID)
                        saving = false
                        if error == nil { onDone() }
                    }
                } label: {
                    Label(saving ? "Adding…" : "Add to Calendar", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(width: 180)
                .disabled(saving)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 440)
        .onAppear {
            if model.calendarList.isEmpty { model.refreshCalendar() }
            calendarID = model.settings.focusBlockCalendarID
        }
    }
}

// MARK: - Settings

struct CalendarSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Use my calendar to plan around meetings", isOn: Binding(
                    get: { model.settings.calendarAwareness },
                    set: { enabled in
                        if enabled { model.enableCalendarAwareness() } else { model.update { $0.calendarAwareness = false } }
                    }
                ))
                HStack {
                    Text("Calendar access")
                    Spacer()
                    switch model.calendarAccess {
                    case .granted: Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(Palette.success)
                    case .writeOnly: Text("Add-only").foregroundStyle(.secondary)
                    case .denied: Button("Open Privacy Settings…") { model.openCalendarPrivacySettings() }
                    case .notDetermined: Text("Not requested").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Calendar awareness")
            } footer: {
                Text("Off by default. When on, FlowBreak reads the times and titles of today's and tomorrow's events to hold break reminders during meetings, show free time in Today, and warn before a session runs into a meeting. Nothing from your calendar is stored or sent anywhere.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }

            if model.settings.calendarAwareness {
                Section("During meetings") {
                    Toggle("Hold break reminders until the meeting ends", isOn: Binding(
                        get: { model.settings.holdRemindersDuringMeetings },
                        set: { value in model.update { $0.holdRemindersDuringMeetings = value } }
                    ))
                    Text("All-day events, events marked “free”, cancelled events and invitations you declined don't count as meetings.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }

                Section("Calendars to consider") {
                    if model.calendarList.isEmpty {
                        Text("No calendars found.").foregroundStyle(.secondary)
                    }
                    ForEach(model.calendarList) { cal in
                        Toggle(isOn: Binding(
                            get: { model.settings.calendarIDs.isEmpty || model.settings.calendarIDs.contains(cal.id) },
                            set: { on in
                                model.update { settings in
                                    var ids = settings.calendarIDs.isEmpty ? model.calendarList.map(\.id) : settings.calendarIDs
                                    if on { if !ids.contains(cal.id) { ids.append(cal.id) } } else { ids.removeAll { $0 == cal.id } }
                                    settings.calendarIDs = ids.count == model.calendarList.count ? [] : ids
                                }
                            }
                        )) {
                            HStack(spacing: 6) {
                                Circle().fill(Color(cgColor: cal.color ?? NSColor.gray.cgColor)).frame(width: 9, height: 9)
                                Text(cal.title)
                                Text(cal.source).foregroundStyle(.secondary).font(.caption)
                            }
                        }
                    }
                }

                if !model.busyBlocks.isEmpty {
                    Section("Today") {
                        let time = Date.FormatStyle(date: .omitted, time: .shortened)
                        ForEach(Array(model.busyBlocks.filter { model.calendar.isDateInToday($0.interval.start) }.prefix(6).enumerated()), id: \.offset) { _, block in
                            LabeledContent(block.title, value: "\(block.interval.start.formatted(time)) – \(block.interval.end.formatted(time))")
                        }
                        if let free = model.freeMinutesToday {
                            LabeledContent("Free until end of workday", value: QuickAddParser.formatMinutes(free))
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { model.refreshCalendar() }
    }
}

struct NudgeSettingsSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Section {
            Toggle("Nudge me when I switch to a distracting app during focus", isOn: Binding(
                get: { model.settings.nudgesEnabled },
                set: { value in model.update { $0.nudgesEnabled = value } }
            ))
            if model.settings.nudgesEnabled {
                if model.settings.distractingBundleIDs.isEmpty {
                    Text("Choose at least one app below.").foregroundStyle(Palette.warning).font(.callout)
                }
                ForEach(model.settings.distractingBundleIDs, id: \.self) { id in
                    HStack {
                        Text(model.appName(for: id))
                        Spacer()
                        Button { model.update { $0.distractingBundleIDs.removeAll { $0 == id } } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove \(model.appName(for: id))")
                    }
                }
                Menu("Add an App…") {
                    ForEach(model.runningApplicationsForExclusion().filter { !model.settings.distractingBundleIDs.contains($0.bundleID) }) { app in
                        Button(app.name) { model.update { $0.distractingBundleIDs.append(app.bundleID) } }
                    }
                }
                .fixedSize()
                Stepper(value: Binding(
                    get: { model.settings.nudgeCooldownMinutes },
                    set: { value in model.update { $0.nudgeCooldownMinutes = value } }
                ), in: 1...60) {
                    HStack {
                        Text("At most once per app every")
                        Spacer()
                        Text("\(model.settings.nudgeCooldownMinutes) min").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Distraction nudges")
        } footer: {
            Text("Off by default. FlowBreak only notices which app comes to the front — not what you do in it — and shows a small note you can dismiss or allow for the session. It never blocks apps. Browsers can't be split by website.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

struct ShortcutsInfoSection: View {
    private static let actions: [(icon: String, text: String)] = [
        ("play.circle", "Start Focus — optionally on a task, for a number of minutes"),
        ("playpause", "Pause or Resume Focus · Stop Focus · Take a Break"),
        ("plus.circle", "Add Task — with smart parsing, to Inbox or Today"),
        ("checkmark.circle", "Complete Task"),
        ("star", "Get Today's Big Three · Get Focus Status"),
    ]

    var body: some View {
        Section {
            ForEach(Self.actions.indices, id: \.self) { index in
                Label(Self.actions[index].text, systemImage: Self.actions[index].icon).font(.callout)
            }
            Button("Open the Shortcuts App") {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
                    NSWorkspace.shared.open(url)
                }
            }
        } header: {
            Text("Shortcuts, Spotlight & Siri")
        } footer: {
            Text("Try “Start focus in FlowBreak” or “What's my Big Three in FlowBreak”. Actions appear in the Shortcuts app after FlowBreak has been opened once from Applications.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

struct UpdatesSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Section {
            Toggle("Check for updates automatically (once a day)", isOn: Binding(
                get: { model.settings.checkForUpdatesAutomatically },
                set: { value in model.answerUpdatePrompt(enable: value) }
            ))
            HStack {
                Button("Check Now") { model.checkForUpdates(userInitiated: true) }
                Spacer()
                Text(statusText).font(.callout).foregroundStyle(.secondary)
            }
        } header: {
            Text("Updates")
        } footer: {
            Text("Checks read a small file from this project's GitHub releases. No personal data is sent. Downloads are verified against their published checksum before opening.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        switch model.updateState {
        case .checking: return "Checking…"
        case let .upToDate(date): return "Up to date · \(date.formatted(date: .omitted, time: .shortened))"
        case let .available(m): return "\(m.version) (\(m.build)) available"
        case let .unsupported(m): return "\(m.version) needs a newer macOS"
        case .downloading: return "Downloading…"
        case .downloaded: return "Downloaded"
        case let .failed(message): return message
        case .idle:
            return model.settings.lastUpdateCheck.map { "Last checked \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Never checked"
        }
    }
}

struct SupportSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Section {
            HStack {
                Button("Copy Diagnostics") { model.copyDiagnostics() }
                Button("Report a Problem…") { model.reportProblem() }
            }
        } header: {
            Text("Help us fix things")
        } footer: {
            Text("Diagnostics include versions, settings and record counts — never task titles, notes, app names or calendar details. “Report a Problem” opens a pre-filled GitHub issue in your browser; nothing is sent until you submit it.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}
