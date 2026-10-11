import FlowBreakCore
import SwiftUI

struct TaskSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section {
                shortcutPicker("Quick Add a task", keyPath: \.quickAddShortcut, choices: ShortcutPreset.quickAddChoices)
                shortcutPicker("Start / pause focus", keyPath: \.toggleFocusShortcut, choices: ShortcutPreset.focusChoices)
                shortcutPicker("Open Today's tasks", keyPath: \.openTodayShortcut, choices: ShortcutPreset.todayChoices)
                ForEach(model.shortcutErrors, id: \.self) { error in
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(Palette.warning)
                }
            } header: {
                Text("Global shortcuts")
            } footer: {
                Text("Off until you choose one. These work from any app; if another app already uses a combination, FlowBreak tells you here instead of taking it over.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Ask “how did it go?” after a task's focus session", isOn: binding(\.askForOutcome))
                Toggle("Move a task to In Progress when focus starts", isOn: binding(\.moveToInProgressOnFocus))
                Toggle("Haptic feedback when completing (Force Touch trackpads)", isOn: binding(\.completionHaptics))
            } header: {
                Text("Focus & completion")
            } footer: {
                Text("A timer ending never marks a task complete — only you do.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }

            Section {
                DatePicker("My workday ends at", selection: Binding(
                    get: { model.calendar.startOfDay(for: Date()).addingTimeInterval(TimeInterval(model.settings.workdayEndMinute * 60)) },
                    set: { date in
                        let parts = model.calendar.dateComponents([.hour, .minute], from: date)
                        model.update { $0.workdayEndMinute = (parts.hour ?? 18) * 60 + (parts.minute ?? 0) }
                    }
                ), displayedComponents: .hourAndMinute)
                Toggle("Hide private task titles in Insights and summaries", isOn: binding(\.hidePrivateTasksInInsights))
            } header: {
                Text("Planning")
            } footer: {
                Text("Today compares your task estimates with the time left in your workday — a rough guide, not a schedule.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }

            Section {
                Button("Import a Checklist (Text or Markdown)…") { model.importChecklist() }
                HStack {
                    Button("Export Tasks as Markdown…") { model.exportTasks(.markdown) }
                    Button("Export Tasks as CSV…") { model.exportTasks(.csv) }
                }
            } header: {
                Text("Import & export")
            } footer: {
                Text("Import reads lines like “- [ ] Buy milk”; checked items are imported as completed.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { value in model.update { $0[keyPath: keyPath] = value } }
        )
    }

    private func shortcutPicker(_ title: String, keyPath: WritableKeyPath<AppSettings, ShortcutPreset>, choices: [ShortcutPreset]) -> some View {
        Picker(title, selection: binding(keyPath)) {
            ForEach(choices, id: \.self) { Text($0.displayName).tag($0) }
        }
    }
}
