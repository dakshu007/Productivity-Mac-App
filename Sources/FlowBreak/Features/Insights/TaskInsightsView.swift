import Charts
import FlowBreakCore
import SwiftUI

/// Task-based insights: what got finished and where focus went.
struct TaskInsightsSection: View {
    @EnvironmentObject private var model: AppModel
    var range: InsightsRange

    var body: some View {
        let interval = range.interval(now: model.now, calendar: model.calendar)
        let summary = TaskInsightsCalculator.summary(
            tasks: model.tasks,
            sessions: model.sessions,
            interval: interval,
            dayCount: range.dayCount,
            now: model.now,
            hidePrivate: model.settings.hidePrivateTasksInInsights,
            calendar: model.calendar
        )
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack {
                    Text("Tasks").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button("Open Tasks") { model.openWindow?(.tasks) }
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                }
                if summary.byTask.isEmpty && summary.completedCount == 0 {
                    EmptyStateView(
                        systemImage: "checklist",
                        title: "No task activity in this period",
                        message: "Start a focus session from a task, or complete one, and it will show up here."
                    )
                } else {
                    HStack(spacing: Spacing.xl) {
                        MetricView(title: "Tasks completed", value: "\(summary.completedCount)", help: "Tasks marked complete in this period.")
                        MetricView(title: "Worked on, still open", value: "\(summary.workedOnButOpen)", help: "Open tasks that had linked focus time in this period.")
                        MetricView(
                            title: "Sessions per finished task",
                            value: summary.averageSessionsPerCompletedTask.map { String(format: "%.1f", $0) } ?? "—",
                            help: "Linked focus sessions (all time) of tasks completed in this period, divided by those tasks."
                        )
                        MetricView(title: "Focus without a task", value: DurationFormatter.short(summary.unlinkedFocusTime), help: "Focus time in this period not linked to any task.")
                    }
                    if range != .today, summary.completedCount > 0 {
                        Chart(summary.completedByDay) { day in
                            BarMark(x: .value("Day", day.day, unit: .day), y: .value("Completed", day.count))
                                .foregroundStyle(Palette.success)
                                .cornerRadius(3)
                                .accessibilityLabel(Text(day.day.formatted(.dateTime.month().day())))
                                .accessibilityValue(Text("\(day.count) tasks completed"))
                        }
                        .chartYAxisLabel("tasks")
                        .frame(height: 110)
                    }
                    if !summary.byTask.isEmpty {
                        Text("Focus by task").font(.system(size: 12, weight: .semibold)).padding(.top, Spacing.xs)
                        ForEach(summary.byTask.prefix(8)) { item in
                            TaskFocusRow(item: item)
                        }
                    }
                    if summary.byProject.count > 1 || (summary.byProject.first.map { $0.name != "No project" } ?? false) {
                        Text("Focus by project").font(.system(size: 12, weight: .semibold)).padding(.top, Spacing.xs)
                        let maxTime = summary.byProject.first?.focusTime ?? 1
                        ForEach(summary.byProject) { project in
                            HStack(spacing: Spacing.m) {
                                Text(project.name).font(.system(size: 12.5)).lineLimit(1).frame(width: 170, alignment: .leading)
                                ProgressBar(progress: project.focusTime / max(1, maxTime), tint: Palette.accent, height: 8)
                                Text(DurationFormatter.short(project.focusTime))
                                    .font(.system(size: 12).monospacedDigit())
                                    .foregroundStyle(Palette.secondaryText)
                                    .frame(width: 64, alignment: .trailing)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }
}

struct TaskFocusRow: View {
    @EnvironmentObject private var model: AppModel
    var item: TaskFocusSummary

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: item.status == .completed ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(item.status == .completed ? Palette.success : Palette.secondaryText)
                .font(.system(size: 12))
            Text(item.title)
                .font(.system(size: 12.5))
                .italic(item.isHidden)
                .lineLimit(1)
            Spacer()
            Text("\(item.sessions) session\(item.sessions == 1 ? "" : "s")")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.secondaryText)
            Text(DurationFormatter.short(item.focusTime))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .frame(width: 60, alignment: .trailing)
            Text(estimateText)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.secondaryText)
                .frame(width: 128, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private var estimateText: String {
        guard let estimate = item.estimatedMinutes else { return "no estimate" }
        return "\(DurationFormatter.short(item.totalFocusTime)) of \(QuickAddParser.formatMinutes(estimate)) est."
    }
}

/// This week at a glance, with an optional two-question reflection.
struct WeeklyReviewCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var helped = ""
    @State private var distracted = ""
    @State private var loaded = false

    var body: some View {
        let review = model.weeklyReview()
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Weekly review").font(.system(size: 13, weight: .semibold))
                        Text(weekCaption(review.week)).font(Typography.caption).foregroundStyle(Palette.secondaryText)
                    }
                    Spacer()
                    Button("Export Summary…") { model.exportWeeklySummary() }
                        .controlSize(.small)
                }
                HStack(spacing: Spacing.xl) {
                    MetricView(title: "Focus", value: DurationFormatter.short(review.focusTime), compact: true)
                    MetricView(title: "Sessions", value: "\(review.sessionsCompleted)", compact: true)
                    MetricView(title: "Breaks", value: "\(review.breaksTaken)", compact: true)
                    MetricView(title: "Tasks done", value: "\(review.tasksCompleted.count)", compact: true)
                    MetricView(title: "Carried over", value: "\(review.carriedOver.count)", help: "Open tasks that were due this week or earlier.", compact: true)
                }
                if !review.tasksCompleted.isEmpty || !review.carriedOver.isEmpty {
                    HStack(alignment: .top, spacing: Spacing.xl) {
                        taskColumn("Finished", review.tasksCompleted, done: true)
                        taskColumn("Still open", review.carriedOver, done: false)
                    }
                }
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("Reflection (optional, stays on this Mac)").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Palette.secondaryText)
                    TextField("What helped me focus this week?", text: $helped, axis: .vertical)
                        .lineLimit(1...3)
                        .textFieldStyle(.roundedBorder)
                    TextField("What distracted me?", text: $distracted, axis: .vertical)
                        .lineLimit(1...3)
                        .textFieldStyle(.roundedBorder)
                }
                .onChange(of: helped) { _ in saveIfLoaded() }
                .onChange(of: distracted) { _ in saveIfLoaded() }
            }
        }
        .onAppear {
            helped = review.reflection?.helped ?? ""
            distracted = review.reflection?.distracted ?? ""
            Task { @MainActor in loaded = true }
        }
    }

    private func saveIfLoaded() {
        guard loaded else { return }
        model.saveReflection(helped: helped, distracted: distracted)
    }

    private func taskColumn(_ title: String, _ tasks: [TaskItem], done: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Palette.secondaryText)
            if tasks.isEmpty {
                Text("—").font(.system(size: 12)).foregroundStyle(Palette.secondaryText)
            }
            ForEach(tasks.prefix(6)) { task in
                Label {
                    Text(model.settings.hidePrivateTasksInInsights && task.isPrivate ? "Private task" : task.title)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(done ? Palette.success : Palette.secondaryText)
                }
                .font(.system(size: 12))
            }
            if tasks.count > 6 {
                Text("+\(tasks.count - 6) more").font(.system(size: 11)).foregroundStyle(Palette.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func weekCaption(_ week: DateInterval) -> String {
        let style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        return "\(week.start.formatted(style)) – \(week.end.addingTimeInterval(-1).formatted(style))"
    }
}
