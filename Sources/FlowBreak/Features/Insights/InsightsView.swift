import Charts
import FlowBreakCore
import SwiftUI

/// Daily insights. Every number is derived from stored session records.
struct InsightsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var range: InsightsRange
    @State private var showMethodology = false

    init(initialRange: InsightsRange = .today) {
        _range = State(initialValue: initialRange)
    }

    var body: some View {
        let summary = model.summary(for: range)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                header
                metrics(summary)
                chart(summary)
                timeline(summary)
                appUsage
                websiteUsage
                methodology
            }
            .padding(Spacing.xxl)
        }
        .frame(minWidth: 640, minHeight: 520)
        .background(Palette.canvas)
    }

    private var header: some View {
        HStack(spacing: Spacing.m) {
            BrandMark(size: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text("Insights").font(.system(size: 18, weight: .semibold))
                Text(rangeCaption).font(Typography.caption).foregroundStyle(Palette.secondaryText)
            }
            Spacer()
            Picker("Period", selection: $range) {
                ForEach(InsightsRange.allCases) { r in Text(r.displayName).tag(r) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
            Menu {
                Button("Sessions as CSV…") { model.export(.sessionsCSV) }
                Button("App usage as CSV…") { model.export(.usageCSV) }
                    .disabled(model.usage.isEmpty)
                Button("Everything as JSON…") { model.export(.json) }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .fixedSize()
        }
    }

    private var rangeCaption: String {
        let interval = range.interval(now: model.now, calendar: model.calendar)
        let style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        if range == .today { return model.now.formatted(date: .complete, time: .omitted) }
        let lastDay = interval.end.addingTimeInterval(-1)
        return "\(interval.start.formatted(style)) – \(lastDay.formatted(style))"
    }

    // MARK: Metrics

    private func metrics(_ s: InsightsSummary) -> some View {
        Card {
            Grid(alignment: .leading, horizontalSpacing: Spacing.xl, verticalSpacing: Spacing.l) {
                GridRow {
                    MetricView(title: "Focus time", value: DurationFormatter.short(s.focusTime),
                               help: "Un-paused time spent in focus sessions in this period, including sessions you stopped early.")
                    MetricView(title: "Sessions completed", value: "\(s.focusSessionsCompleted)",
                               help: "Focus sessions that ran until their timer ended.")
                    MetricView(title: "Breaks taken", value: "\(s.breaksTaken)",
                               help: "Breaks you started in this period.")
                }
                GridRow {
                    MetricView(title: "Break adherence",
                               value: s.adherence.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                               detail: s.adherenceDenominator > 0 ? "\(s.adherenceNumerator) of \(s.adherenceDenominator) sessions" : "No completed sessions",
                               help: "Completed focus sessions that were followed by a break, divided by all completed focus sessions.")
                    MetricView(title: "Longest focus", value: s.longestFocus.map(DurationFormatter.short) ?? "—",
                               help: "The longest un-paused focus session started in this period.")
                    MetricView(title: "Pomodoro cycles", value: "\(s.pomodoroCycles)",
                               help: "Long breaks taken. Each one closes a full cycle of Pomodoro work sessions.")
                }
            }
        }
    }

    // MARK: Chart

    private struct ChartPoint: Identifiable {
        var label: Date
        var minutes: Double
        var id: Date { label }
    }

    private func chartPoints(_ s: InsightsSummary) -> [ChartPoint] {
        if range == .today {
            let start = model.calendar.startOfDay(for: model.now)
            return (0..<24).compactMap { hour -> ChartPoint? in
                guard let from = model.calendar.date(byAdding: .hour, value: hour, to: start),
                      let to = model.calendar.date(byAdding: .hour, value: 1, to: from) else { return nil }
                let interval = DateInterval(start: from, end: to)
                let seconds = s.timeline
                    .filter { $0.kind.isFocus }
                    .reduce(0) { $0 + StatisticsCalculator.activeTime(of: $1, in: interval, now: model.now) }
                return ChartPoint(label: from, minutes: seconds / 60)
            }
        }
        return s.daily.map { ChartPoint(label: $0.day, minutes: $0.focusTime / 60) }
    }

    private var axisUnit: Calendar.Component { range == .today ? .hour : .day }

    private var axisStride: Int {
        switch range {
        case .today: return 3
        case .last7Days: return 1
        case .last30Days: return 5
        }
    }

    private var axisFormat: Date.FormatStyle {
        switch range {
        case .today: return .dateTime.hour()
        case .last7Days: return .dateTime.weekday(.abbreviated)
        case .last30Days: return .dateTime.month(.abbreviated).day()
        }
    }

    private func chart(_ s: InsightsSummary) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Text(range == .today ? "Focus by hour" : "Focus by day")
                    .font(.system(size: 13, weight: .semibold))
                if s.focusTime <= 0 {
                    EmptyStateView(
                        systemImage: "chart.bar",
                        title: "No focus time yet",
                        message: range == .today
                            ? "Start a focus session from the menu bar and your day will appear here."
                            : "Completed and stopped focus sessions from this period will appear here."
                    )
                    .frame(height: 180)
                } else {
                    let points = chartPoints(s)
                    Chart(points) { point in
                        BarMark(
                            x: .value("Time", point.label, unit: range == .today ? .hour : .day),
                            y: .value("Minutes", point.minutes)
                        )
                        .foregroundStyle(Palette.accent)
                        .cornerRadius(3)
                        .accessibilityLabel(Text(point.label.formatted(axisFormat)))
                        .accessibilityValue(Text("\(Int(point.minutes.rounded())) minutes of focus"))
                    }
                    .chartYAxisLabel("minutes")
                    .chartXAxis {
                        AxisMarks(values: .stride(by: axisUnit, count: axisStride)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: axisFormat)
                        }
                    }
                    .frame(height: 180)
                }
            }
        }
    }

    // MARK: Timeline

    private func timeline(_ s: InsightsSummary) -> some View {
        let limit = range == .today ? 50 : 100
        let shown = Array(s.timeline.prefix(limit))
        return Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Sessions").font(.system(size: 13, weight: .semibold))
                if s.timeline.isEmpty {
                    EmptyStateView(
                        systemImage: "clock",
                        title: "No sessions in this period",
                        message: "Focus sessions and breaks are listed here with their start, end, duration and outcome."
                    )
                } else {
                    ForEach(shown) { session in
                        SessionRow(session: session, now: model.now, showDate: range != .today)
                        if session.id != shown.last?.id {
                            Divider()
                        }
                    }
                    if s.timeline.count > limit {
                        Text("Showing the \(limit) most recent sessions. Export to see all \(s.timeline.count).")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.secondaryText)
                    }
                }
            }
        }
    }

    // MARK: Usage

    @ViewBuilder private var appUsage: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack {
                    Text("App usage").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if model.settings.appTrackingEnabled {
                        Text(model.settings.privateMode ? "Paused" : "Approximate")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.secondaryText)
                    }
                }
                if !model.settings.appTrackingEnabled {
                    EmptyStateView(
                        systemImage: "app.dashed",
                        title: "App usage tracking is off",
                        message: "If you turn it on, FlowBreak records only which app is in front and roughly for how long — on this Mac only.",
                        actionTitle: "Review in Privacy Settings"
                    ) {
                        model.settingsTab = .privacy
                        model.openWindow?(.settings)
                    }
                } else {
                    let aggregates = model.usageAggregates(for: range)
                    if aggregates.isEmpty {
                        EmptyStateView(
                            systemImage: "hourglass",
                            title: "No app usage recorded yet",
                            message: model.settings.privateMode
                                ? "Tracking is paused (private mode)."
                                : "Time appears here after you've used apps for a little while. Idle time over 2 minutes isn't counted."
                        )
                    } else {
                        let top = Array(aggregates.prefix(10))
                        let maxDuration = top.first?.duration ?? 1
                        ForEach(top) { item in
                            HStack(spacing: Spacing.m) {
                                Text(item.appName)
                                    .font(.system(size: 12.5))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(width: 170, alignment: .leading)
                                GeometryReader { geo in
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Palette.accent.opacity(0.85))
                                        .frame(width: max(4, geo.size.width * item.duration / maxDuration))
                                }
                                .frame(height: 10)
                                Text("≈ " + DurationFormatter.short(item.duration))
                                    .font(.system(size: 12).monospacedDigit())
                                    .foregroundStyle(Palette.secondaryText)
                                    .frame(width: 80, alignment: .trailing)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(item.appName), about \(DurationFormatter.short(item.duration))")
                        }
                        Text("Approximate: based on which app was frontmost, sampled with a 15-second idle check. Idle time over 2 minutes is excluded.")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.secondaryText)
                    }
                }
            }
        }
    }

    private var websiteUsage: some View {
        Card {
            HStack(alignment: .top, spacing: Spacing.m) {
                Image(systemName: "globe")
                    .foregroundStyle(Palette.secondaryText)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Website usage").font(.system(size: 13, weight: .semibold))
                    Text("Not available in this version. Measuring time per website needs a browser extension, which FlowBreak doesn't include yet. FlowBreak never guesses websites from the browser's name.")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var methodology: some View {
        DisclosureGroup("How these numbers are calculated", isExpanded: $showMethodology) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("• Days follow your Mac's current calendar and time zone. A session that crosses midnight is split at midnight, so each day gets only its own minutes.")
                Text("• Focus time counts only un-paused time. Sessions you stopped or ended early still count their focused minutes but not as completed sessions.")
                Text("• Break adherence = completed focus sessions followed by a break ÷ completed focus sessions.")
                Text("• Interrupted sessions were left running when FlowBreak quit unexpectedly; they count only up to the last confirmed moment.")
                Text("• Opening this window never changes or resets your data.")
            }
            .font(.system(size: 12))
            .foregroundStyle(Palette.secondaryText)
            .padding(.top, Spacing.s)
        }
        .font(.system(size: 12.5, weight: .medium))
    }
}

struct SessionRow: View {
    var session: FocusSession
    var now: Date
    var showDate: Bool

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: session.kind.isFocus ? "circle.circle" : "leaf")
                .foregroundStyle(session.kind.isFocus ? Palette.accentText : Palette.success)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.kind.displayName)
                    .font(.system(size: 12.5, weight: .medium))
                Text(timeRange)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Palette.secondaryText)
            }
            Spacer()
            Text(DurationFormatter.short(session.actualDuration ?? session.activeDuration(asOf: now)))
                .font(.system(size: 12).monospacedDigit())
            Text(session.status.displayName)
                .font(.system(size: 11))
                .foregroundStyle(statusTint)
                .frame(width: 84, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private var timeRange: String {
        let time = Date.FormatStyle(date: .omitted, time: .shortened)
        let start = showDate
            ? session.startedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
            : session.startedAt.formatted(time)
        if let end = session.endedAt {
            return "\(start) – \(end.formatted(time))"
        }
        return "\(start) – now"
    }

    private var statusTint: Color {
        switch session.status {
        case .completed: return Palette.success
        case .running, .paused: return Palette.accentText
        case .endedEarly, .cancelled, .interrupted: return Palette.secondaryText
        }
    }
}
