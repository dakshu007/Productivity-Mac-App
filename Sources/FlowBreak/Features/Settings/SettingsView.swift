import AppKit
import FlowBreakCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    private static let tabs: [(tab: SettingsTab, title: String, icon: String)] = [
        (.focus, "Focus", "timer"),
        (.reminders, "Reminders", "bell"),
        (.privacy, "Privacy", "hand.raised"),
        (.general, "General", "gearshape"),
        (.about, "About", "info.circle"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.xs) {
                ForEach(Self.tabs.indices, id: \.self) { index in
                    tabButton(Self.tabs[index])
                }
            }
            .padding(.vertical, Spacing.s)
            .frame(maxWidth: .infinity)
            Divider()
            Group {
                switch model.settingsTab {
                case .focus: FocusSettingsView()
                case .reminders: ReminderSettingsView()
                case .privacy: PrivacySettingsView()
                case .general: GeneralSettingsView()
                case .about: AboutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 520, minHeight: 460)
    }

    private func tabButton(_ item: (tab: SettingsTab, title: String, icon: String)) -> some View {
        let selected = model.settingsTab == item.tab
        return Button {
            model.settingsTab = item.tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: item.icon)
                    .font(.system(size: 17))
                    .frame(height: 20)
                Text(item.title)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
            }
            .foregroundStyle(selected ? Palette.accentText : Palette.secondaryText)
            .frame(width: 78, height: 46)
            .background(
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .fill(selected ? Palette.track : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

/// Binding helper that routes writes through `AppModel.update` (sanitised + persisted).
private extension AppModel {
    func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { value in self.update { $0[keyPath: keyPath] = value } }
        )
    }
}

private struct MinutesStepper: View {
    var title: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step = 1

    var body: some View {
        Stepper(value: $value, in: range, step: step) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value) min").monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .accessibilityValue("\(value) minutes")
    }
}

struct FocusSettingsView: View {
    @EnvironmentObject private var model: AppModel

    private var isCustomFocus: Bool { !AppSettings.focusPresets.contains(model.settings.focusMinutes) }

    var body: some View {
        Form {
            Section {
                Picker("Timer mode", selection: model.binding(\.timerMode)) {
                    Text("Focus").tag(TimerMode.focus)
                    Text("Pomodoro").tag(TimerMode.pomodoro)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(model.settings.timerMode == .focus
                     ? "One focus interval followed by a short break."
                     : "Work sessions with short breaks, and a long break after every \(model.settings.longBreakEvery) completed sessions.")
                    .settingsFootnote()
            }

            Section("Focus") {
                Picker("Focus interval", selection: Binding(
                    get: { isCustomFocus ? -1 : model.settings.focusMinutes },
                    set: { value in if value > 0 { model.update { $0.focusMinutes = value } } else if !isCustomFocus { model.update { $0.focusMinutes = 50 } } }
                )) {
                    ForEach(AppSettings.focusPresets, id: \.self) { Text("\($0) minutes").tag($0) }
                    Text("Custom").tag(-1)
                }
                if isCustomFocus {
                    MinutesStepper(title: "Custom interval", value: model.binding(\.focusMinutes), range: 1...240, step: 5)
                }
                MinutesStepper(title: "Break length", value: model.binding(\.shortBreakMinutes), range: 1...60)
            }

            Section("Pomodoro") {
                MinutesStepper(title: "Work session", value: model.binding(\.pomodoroWorkMinutes), range: 1...240)
                MinutesStepper(title: "Short break", value: model.binding(\.pomodoroShortBreakMinutes), range: 1...60)
                MinutesStepper(title: "Long break", value: model.binding(\.pomodoroLongBreakMinutes), range: 1...120)
                Stepper(value: model.binding(\.longBreakEvery), in: 2...12) {
                    HStack {
                        Text("Long break after")
                        Spacer()
                        Text("\(model.settings.longBreakEvery) sessions").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Toggle("Start breaks automatically", isOn: model.binding(\.autoStartBreaks))
                Toggle("Start the next focus session automatically", isOn: model.binding(\.autoStartFocus))
                Toggle("Open guided break activities when a break starts", isOn: model.binding(\.openBreakPanel))
                Toggle("Show countdown in the menu bar", isOn: model.binding(\.showMenuBarCountdown))
            } header: {
                Text("Cycle")
            } footer: {
                Text("Automatic cycles are off by default: FlowBreak offers the next step instead of starting it. Cycles never continue automatically while your Mac is asleep. Changes apply to the next session.")
                    .settingsFootnote()
            }
        }
        .formStyle(.grouped)
    }
}

struct ReminderSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Break reminders", isOn: model.binding(\.notificationsEnabled))
                HStack {
                    Text("macOS permission")
                    Spacer()
                    permissionStatus
                }
            } footer: {
                Text("Notifications follow macOS rules: a Focus mode or Do Not Disturb can hold them back, and FlowBreak can't override that. When a break is due, the menu bar always shows “Break” as a fallback.")
                    .settingsFootnote()
            }

            Section("Repeat") {
                MinutesStepper(title: "Remind again every", value: model.binding(\.repeatIntervalMinutes), range: 1...60)
                Stepper(value: model.binding(\.repeatCount), in: 0...AppSettings.maxRepeatCount) {
                    HStack {
                        Text("Repeat reminders")
                        Spacer()
                        Text(model.settings.repeatCount == 0 ? "Off" : "\(model.settings.repeatCount) times")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                Toggle("Play sound", isOn: model.binding(\.soundEnabled))
                Toggle("Remind me after sleep or relaunch", isOn: model.binding(\.remindAfterWake))
            }

            Section {
                Toggle("Quiet hours", isOn: model.binding(\.quietHoursEnabled))
                if model.settings.quietHoursEnabled {
                    DatePicker("From", selection: minuteBinding(\.startMinute), displayedComponents: .hourAndMinute)
                    DatePicker("Until", selection: minuteBinding(\.endMinute), displayedComponents: .hourAndMinute)
                }
            } footer: {
                Text("Repeats stop when you start a break, skip it, resume focus, or turn reminders off. During quiet hours, no FlowBreak notifications are delivered.")
                    .settingsFootnote()
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var permissionStatus: some View {
        switch model.notificationStatus {
        case .authorized:
            Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(Palette.success)
        case .denied:
            Button("Open Notification Settings…") { model.openNotificationSettings() }
        case .notDetermined, .unknown:
            Button("Allow Notifications…") { model.requestNotificationPermission() }
        case .unavailable:
            Text("Unavailable outside the app bundle").foregroundStyle(.secondary)
        }
    }

    private func minuteBinding(_ keyPath: WritableKeyPath<QuietHours, Int>) -> Binding<Date> {
        Binding(
            get: {
                let start = model.calendar.startOfDay(for: Date())
                return start.addingTimeInterval(TimeInterval(model.settings.quietHours[keyPath: keyPath] * 60))
            },
            set: { date in
                let parts = model.calendar.dateComponents([.hour, .minute], from: date)
                model.update { $0.quietHours[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0) }
            }
        )
    }
}

struct PrivacySettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmDelete = false
    @State private var confirmEnableTracking = false

    var body: some View {
        Form {
            Section {
                Toggle("Record which app is in front", isOn: Binding(
                    get: { model.settings.appTrackingEnabled },
                    set: { enabled in
                        if enabled { confirmEnableTracking = true } else { model.update { $0.appTrackingEnabled = false } }
                    }
                ))
                Toggle("Pause tracking (private mode)", isOn: model.binding(\.privateMode))
                    .disabled(!model.settings.appTrackingEnabled)
            } header: {
                Text("App usage")
            } footer: {
                Text("Off by default. When on, FlowBreak stores only the frontmost app's name and approximate active time, on this Mac. It never captures keystrokes, screenshots, window titles, documents or file names.")
                    .settingsFootnote()
            }

            Section {
                if model.settings.excludedBundleIDs.isEmpty {
                    Text("No excluded apps").foregroundStyle(.secondary)
                }
                ForEach(model.settings.excludedBundleIDs, id: \.self) { id in
                    HStack {
                        Text(model.appName(for: id)).lineLimit(1)
                        Text(id).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Button {
                            model.update { $0.excludedBundleIDs.removeAll { $0 == id } }
                        } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Stop excluding \(model.appName(for: id))")
                    }
                }
                Menu("Exclude an App…") {
                    let candidates = model.runningApplicationsForExclusion().filter { !model.settings.excludedBundleIDs.contains($0.bundleID) }
                    if candidates.isEmpty {
                        Text("No other running apps")
                    }
                    ForEach(candidates) { app in
                        Button(app.name) { model.update { $0.excludedBundleIDs.append(app.bundleID) } }
                    }
                }
                .fixedSize()
            } header: {
                Text("Excluded apps")
            } footer: {
                Text("Time in excluded apps is never recorded.").settingsFootnote()
            }

            Section {
                HStack(alignment: .top) {
                    Image(systemName: "globe").foregroundStyle(.secondary)
                    Text("Website tracking isn't available in this version. It would require a separate browser extension; FlowBreak works fully without it and never infers websites from the browser's name.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } header: {
                Text("Websites")
            }

            Section {
                HStack {
                    Button("Export Sessions (CSV)…") { model.export(.sessionsCSV) }
                    Button("Export All (JSON)…") { model.export(.json) }
                }
                Button("Delete All FlowBreak Data…", role: .destructive) { confirmDelete = true }
            } header: {
                Text("Your data")
            } footer: {
                Text("Everything is stored locally in ~/Library/Application Support/FlowBreak. No account, no cloud, no analytics.")
                    .settingsFootnote()
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Delete all FlowBreak data?", isPresented: $confirmDelete) {
            Button("Delete All Data", role: .destructive) { model.deleteAllData() }
        } message: {
            Text("This permanently removes your session history and app usage records from this Mac. A session in progress keeps running. Settings are kept.")
        }
        .alert("Turn on app usage tracking?", isPresented: $confirmEnableTracking) {
            Button("Turn On") { model.update { $0.appTrackingEnabled = true } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("FlowBreak will record the name of the app in front and roughly how long you use it, only on this Mac. Idle time over 2 minutes isn't counted. You can pause, exclude apps, export or delete this data at any time.")
        }
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Launch FlowBreak at login", isOn: Binding(
                    get: { model.launchAtLoginStatus == .enabled || model.launchAtLoginStatus == .requiresApproval },
                    set: { model.setLaunchAtLogin($0) }
                ))
                .disabled(isLaunchUnavailable)
                switch model.launchAtLoginStatus {
                case .requiresApproval:
                    HStack {
                        Text("Needs your approval in Login Items.").font(.callout).foregroundStyle(Palette.warning)
                        Spacer()
                        Button("Open Login Items…") { model.openLoginItemsSettings() }
                    }
                case let .unavailable(reason):
                    Text(reason).font(.callout).foregroundStyle(.secondary)
                default:
                    EmptyView()
                }
                Toggle("Show FlowBreak in the Dock", isOn: model.binding(\.showInDock))
            } header: {
                Text("Behavior")
            }

            Section {
                LabeledContent("Appearance", value: "Follows your Mac (Light / Dark)")
                LabeledContent("Motion", value: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? "Reduced (system setting)" : "Standard (follows Reduce Motion)")
            } header: {
                Text("Appearance")
            }

            Section {
                LabeledContent("Primary action in the menu", value: "Return")
                LabeledContent("Settings", value: "⌘ ,")
                LabeledContent("Quit", value: "⌘ Q")
            } header: {
                Text("Keyboard")
            }

            Section {
                Button("Show Welcome Tour Again") { model.openWindow?(.onboarding) }
            }
        }
        .formStyle(.grouped)
    }

    private var isLaunchUnavailable: Bool {
        if case .unavailable = model.launchAtLoginStatus { return true }
        return false
    }
}

struct AboutView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.m) {
                BrandMark(size: 64)
                    .padding(.top, Spacing.l)
                Text("FlowBreak").font(.system(size: 20, weight: .semibold))
                Text("Version \(model.versionString)").font(.callout).foregroundStyle(.secondary)
                Text("Focus, pause, return.").font(.callout)
                PrivacySummary()
                    .padding(.top, Spacing.m)
            }
            .frame(maxWidth: .infinity)
            .padding(Spacing.l)
        }
    }
}

/// Plain-language privacy page.
struct PrivacySummary: View {
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Label("Privacy", systemImage: "lock.shield").font(.system(size: 13, weight: .semibold))
                ForEach(Self.points, id: \.self) { point in
                    HStack(alignment: .top, spacing: Spacing.s) {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.success).padding(.top, 3)
                        Text(point).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    static let points = [
        "Everything stays on this Mac. No account, cloud sync, ads or analytics.",
        "Focus and break sessions are stored with their start and end times so statistics stay accurate.",
        "App usage tracking is off unless you turn it on, and records only the frontmost app's name and approximate time.",
        "FlowBreak never records keystrokes, screenshots, window titles, documents or browsing history.",
        "You can export or delete all data at any time in Settings › Privacy.",
    ]
}

private extension Text {
    func settingsFootnote() -> some View {
        self.font(.system(size: 11)).foregroundStyle(.secondary)
    }
}
