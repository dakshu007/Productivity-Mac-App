import AppKit
import FlowBreakCore
import SwiftUI

/// Content of the menu-bar popover. Every state has one prominent action and
/// a small set of non-overlapping secondary actions.
struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(spacing: Spacing.l) {
                banners
                timerDisplay
                primaryAction
                secondaryActions
                if model.state.phase == .idle {
                    modePicker
                }
            }
            .padding(Spacing.l)
            Divider()
            todaySummary
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.m)
            Divider()
            footer
        }
        .frame(width: 320)
        .background(Palette.canvas.opacity(0.35))
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Spacing.s) {
            BrandMark(size: 22)
            Text("FlowBreak")
                .font(Typography.title)
            Spacer()
            StatusPill(text: status.text, tint: status.tint, systemImage: status.icon)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
    }

    private var status: (text: String, tint: Color, icon: String?) {
        switch model.state.phase {
        case .idle: return ("Ready", Palette.secondaryText, nil)
        case .focusing:
            return model.state.isPaused ? ("Paused", Palette.secondaryText, "pause.fill") : ("Focusing", Palette.success, nil)
        case .breakDue:
            return model.state.breakDue?.snoozedUntil != nil ? ("Snoozed", Palette.warning, "moon.zzz.fill") : ("Break due", Palette.warning, "bell.fill")
        case .onBreak:
            return model.state.isPaused ? ("Break paused", Palette.secondaryText, "pause.fill") : ("On break", Palette.accentText, "leaf.fill")
        case .breakComplete: return ("Break done", Palette.success, "checkmark")
        }
    }

    // MARK: Banners

    @ViewBuilder private var banners: some View {
        if let error = model.errorMessage {
            Banner(tone: .error, message: error, actionTitle: "Dismiss") { model.dismissError() }
        }
        if model.settings.notificationsEnabled {
            switch model.notificationStatus {
            case .denied:
                Banner(
                    tone: .warning,
                    message: "Notifications are off for FlowBreak, so break reminders only appear here and in the menu bar.",
                    actionTitle: "Open Notification Settings"
                ) { model.openNotificationSettings() }
            case .notDetermined where model.settings.hasCompletedOnboarding:
                Banner(
                    tone: .info,
                    message: "Allow notifications to get a reminder when it's time for a break.",
                    actionTitle: "Allow Notifications"
                ) { model.requestNotificationPermission() }
            default:
                EmptyView()
            }
        }
    }

    // MARK: Timer

    private var timerDisplay: some View {
        ZStack {
            ProgressRing(progress: model.progress, tint: ringTint, lineWidth: 7)
            VStack(spacing: 2) {
                Text(countdownText)
                    .font(Typography.countdown)
                    .foregroundStyle(model.state.isPaused ? Palette.secondaryText : Color.primary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: 130)
            }
        }
        .frame(width: 168, height: 168)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTimerLabel)
    }

    private var ringTint: Color {
        switch model.state.phase {
        case .onBreak: return Palette.success
        default: return Palette.accent
        }
    }

    private var countdownText: String {
        switch model.state.phase {
        case .focusing, .onBreak:
            return DurationFormatter.clock(model.remaining)
        case .breakDue:
            return DurationFormatter.clock(model.state.breakDue?.suggestedDuration ?? model.configuration.shortBreakDuration)
        case .idle, .breakComplete:
            return DurationFormatter.clock(model.configuration.focusDuration)
        }
    }

    private var subtitle: String {
        let time = Date.FormatStyle(date: .omitted, time: .shortened)
        switch model.state.phase {
        case .idle:
            return model.settings.timerMode == .pomodoro ? "Pomodoro work session" : "Focus session"
        case .focusing:
            if model.state.isPaused {
                if let paused = model.state.current?.pausedAt { return "Paused at \(paused.formatted(time))" }
                return "Paused"
            }
            if let deadline = model.state.current?.deadline { return "Break at \(deadline.formatted(time))" }
            return "Focusing"
        case .breakDue:
            if let snoozed = model.state.breakDue?.snoozedUntil {
                return "Reminder at \(snoozed.formatted(time))"
            }
            return model.state.breakDue?.suggestedKind == .longBreak ? "Cycle complete — time for a long break" : "Time to reset"
        case .onBreak:
            if model.state.isPaused { return "Break paused" }
            if let deadline = model.state.current?.deadline { return "Back at \(deadline.formatted(time))" }
            return "On break"
        case .breakComplete:
            return "Nice reset. Ready when you are."
        }
    }

    private var accessibilityTimerLabel: String {
        "\(status.text). \(countdownText.replacingOccurrences(of: ":", with: " minutes ")) seconds. \(subtitle)"
    }

    // MARK: Actions

    @ViewBuilder private var primaryAction: some View {
        switch model.state.phase {
        case .idle, .breakComplete:
            Button { model.startFocus() } label: { Label("Start Focus", systemImage: "play.fill") }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        case .focusing:
            if model.state.isPaused {
                Button { model.resume() } label: { Label("Resume", systemImage: "play.fill") }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            } else {
                Button { model.pause() } label: { Label("Pause", systemImage: "pause.fill") }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        case .breakDue:
            let minutes = Int(((model.state.breakDue?.suggestedDuration ?? 300) / 60).rounded())
            Button { model.startBreak() } label: { Label("Start \(minutes)-min Break", systemImage: "leaf.fill") }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        case .onBreak:
            Button {
                model.closePopover?()
                model.openWindow?(.guidedBreak)
            } label: { Label("Guided Break", systemImage: "figure.mind.and.body") }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder private var secondaryActions: some View {
        HStack(spacing: Spacing.s) {
            switch model.state.phase {
            case .idle:
                Button { model.startBreak() } label: { Label("Take a Break", systemImage: "cup.and.saucer") }
            case .focusing:
                if !model.state.isPaused {
                    Button { model.startBreak() } label: { Label("Break Now", systemImage: "leaf") }
                }
                Button(role: .destructive) { model.stop() } label: { Label("Stop", systemImage: "stop.fill") }
            case .breakDue:
                if model.state.breakDue?.snoozedUntil == nil {
                    Button { model.snooze() } label: { Label("Snooze 5 min", systemImage: "moon.zzz") }
                }
                Button { model.skipBreak() } label: { Label("Skip", systemImage: "forward.end") }
            case .onBreak:
                Button { model.extendBreak() } label: { Label("+5 min", systemImage: "plus") }
                if model.state.isPaused {
                    Button { model.resume() } label: { Label("Resume", systemImage: "play") }
                } else {
                    Button { model.pause() } label: { Label("Pause", systemImage: "pause") }
                }
                Button { model.stop() } label: { Label("End", systemImage: "xmark") }
                    .help("End the break and return to ready")
            case .breakComplete:
                Button { model.dismissBreakComplete() } label: { Text("Not Now") }
            }
        }
        .buttonStyle(SecondaryButtonStyle())
        .labelStyle(.titleAndIcon)
    }

    private var modePicker: some View {
        VStack(spacing: Spacing.s) {
            Picker("Mode", selection: Binding(
                get: { model.settings.timerMode },
                set: { mode in model.update { $0.timerMode = mode } }
            )) {
                ForEach(TimerMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if model.settings.timerMode == .focus {
                HStack(spacing: Spacing.xs) {
                    ForEach(AppSettings.focusPresets, id: \.self) { minutes in
                        let selected = model.settings.focusMinutes == minutes
                        Button("\(minutes) min") { model.update { $0.focusMinutes = minutes } }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Palette.ink : Color.primary)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: Radius.small).fill(selected ? Palette.accent : Palette.track))
                            .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            } else {
                PomodoroCycleView(completed: model.state.completedWorkSessionsInCycle, total: model.settings.longBreakEvery)
                Text("\(model.settings.pomodoroWorkMinutes) min work · \(model.settings.pomodoroShortBreakMinutes) min break · \(model.settings.pomodoroLongBreakMinutes) min long break")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.secondaryText)
            }
        }
    }

    // MARK: Summary & footer

    private var todaySummary: some View {
        let today = model.todaySummary
        return HStack(spacing: Spacing.m) {
            MetricView(title: "Focus today", value: DurationFormatter.short(today.focusTime), help: "Un-paused time in focus sessions since midnight.", compact: true)
            MetricView(title: "Sessions", value: "\(today.completed)", help: "Focus sessions that ran to completion today.", compact: true)
            MetricView(title: "Breaks", value: "\(today.breaks)", help: "Breaks you started today.", compact: true)
        }
    }

    private var footer: some View {
        HStack(spacing: Spacing.xs) {
            Button {
                model.closePopover?()
                model.openWindow?(.insights)
            } label: { Label("Insights", systemImage: "chart.bar.xaxis") }
            Button {
                model.closePopover?()
                model.settingsTab = .focus
                model.openWindow?(.settings)
            } label: { Label("Settings", systemImage: "gearshape") }
                .keyboardShortcut(",", modifiers: .command)
            Spacer()
            Text("v\(model.versionString)")
                .font(.system(size: 10))
                .foregroundStyle(Palette.secondaryText.opacity(0.8))
            Button { NSApp.terminate(nil) } label: { Text("Quit") }
                .keyboardShortcut("q", modifiers: .command)
        }
        .buttonStyle(FooterButtonStyle())
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.s - 2)
    }
}

/// Dots showing progress through a Pomodoro cycle.
struct PomodoroCycleView: View {
    var completed: Int
    var total: Int

    var body: some View {
        HStack(spacing: Spacing.s) {
            ForEach(0..<max(1, total), id: \.self) { index in
                Circle()
                    .fill(index < completed ? Palette.accent : Palette.track)
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(min(completed, total)) of \(total) work sessions completed in this cycle")
    }
}
