import FlowBreakCore
import SwiftUI

/// Optional, short break activities. No medical claims, no guilt.
struct BreakActivity: Identifiable, Equatable {
    enum Kind: String, CaseIterable {
        case eyes, movement, hydration, mind
    }

    let kind: Kind
    let title: String
    let systemImage: String
    let duration: TimeInterval
    let summary: String
    /// Shown in sequence across the activity's duration.
    let steps: [String]
    let note: String?

    var id: Kind { kind }

    static let all: [BreakActivity] = [
        BreakActivity(
            kind: .eyes,
            title: "Eye rest",
            systemImage: "eye",
            duration: 20,
            summary: "20 seconds, 20 feet away",
            steps: ["Look at something about 20 feet (6 m) away. Let your eyes relax."],
            note: "Based on the common 20-20-20 practice."
        ),
        BreakActivity(
            kind: .movement,
            title: "Movement",
            systemImage: "figure.walk",
            duration: 60,
            summary: "A minute of gentle movement",
            steps: [
                "Roll your shoulders slowly, forwards then backwards.",
                "Gently tilt your head toward each shoulder.",
                "Stand up, reach overhead, and stretch.",
                "Take a few steps — or a short walk if you can.",
            ],
            note: "Move comfortably; skip anything that causes pain."
        ),
        BreakActivity(
            kind: .hydration,
            title: "Hydration",
            systemImage: "drop",
            duration: 30,
            summary: "A glass of water",
            steps: ["If you'd like, grab a glass of water and take a few sips."],
            note: nil
        ),
        BreakActivity(
            kind: .mind,
            title: "Mind reset",
            systemImage: "wind",
            duration: 60,
            summary: "Slow breathing for a minute",
            steps: ["Follow the circle: breathe in as it grows, out as it shrinks."],
            note: "Breathe at whatever pace feels natural."
        ),
    ]
}

/// Deadline-based countdown for a single activity.
struct ActivityRun: Equatable {
    var activity: BreakActivity
    var startedAt: Date?
    var deadline: Date?
    var pausedRemaining: TimeInterval?

    init(activity: BreakActivity) {
        self.activity = activity
    }

    var hasStarted: Bool { startedAt != nil }
    var isPaused: Bool { pausedRemaining != nil }

    func remaining(at now: Date) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        guard let deadline else { return activity.duration }
        return max(0, deadline.timeIntervalSince(now))
    }

    func isFinished(at now: Date) -> Bool { hasStarted && !isPaused && remaining(at: now) <= 0 }

    func elapsed(at now: Date) -> TimeInterval { activity.duration - remaining(at: now) }

    mutating func start(at now: Date) {
        startedAt = now
        deadline = now.addingTimeInterval(activity.duration)
        pausedRemaining = nil
    }

    mutating func pause(at now: Date) {
        pausedRemaining = remaining(at: now)
        deadline = nil
    }

    mutating func resume(at now: Date) {
        deadline = now.addingTimeInterval(pausedRemaining ?? activity.duration)
        pausedRemaining = nil
    }
}

struct GuidedBreakView: View {
    @EnvironmentObject private var model: AppModel
    var onClose: () -> Void

    @State private var run: ActivityRun?
    @State private var finished: Set<BreakActivity.Kind> = []

    var body: some View {
        VStack(spacing: 0) {
            switch model.state.phase {
            case .onBreak:
                breakHeader
                Divider()
                Group {
                    if let run {
                        ActivityRunnerView(
                            run: Binding(get: { run }, set: { self.run = $0 }),
                            onFinish: {
                                finished.insert(run.activity.kind)
                                self.run = nil
                            },
                            onSkip: { self.run = nil }
                        )
                    } else {
                        activityPicker
                    }
                }
                .frame(maxHeight: .infinity)
            case .breakComplete:
                completeState
            case .breakDue:
                EmptyStateView(
                    systemImage: "leaf",
                    title: "Your break is ready",
                    message: "Start it whenever you like. You can pick an activity once it's running.",
                    actionTitle: "Start Break"
                ) { model.startBreak(openPanel: false) }
                .frame(maxHeight: .infinity)
            case .idle, .focusing:
                EmptyStateView(
                    systemImage: "leaf",
                    title: "No break running",
                    message: "Take a short break any time — FlowBreak will pause your focus session.",
                    actionTitle: "Take a Break"
                ) { model.startBreak(openPanel: false) }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(minWidth: 440, minHeight: 540)
        .background(Palette.canvas)
    }

    // MARK: Header

    private var breakHeader: some View {
        VStack(spacing: Spacing.m) {
            HStack {
                BrandMark(size: 24)
                Text(model.state.current?.kind == .longBreak ? "Long break" : "Break")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                if model.state.isPaused {
                    StatusPill(text: "Paused", tint: Palette.secondaryText, systemImage: "pause.fill")
                }
            }
            Text(DurationFormatter.clock(model.remaining))
                .font(Typography.largeCountdown)
                .foregroundStyle(model.state.isPaused ? Palette.secondaryText : Color.primary)
                .accessibilityLabel("\(DurationFormatter.clock(model.remaining)) of break left")
            ProgressView(value: model.progress)
                .tint(Palette.success)
                .accessibilityLabel("Break progress")
            HStack(spacing: Spacing.s) {
                Button { model.extendBreak() } label: { Label("+5 min", systemImage: "plus") }
                if model.state.isPaused {
                    Button { model.resume() } label: { Label("Resume", systemImage: "play") }
                } else {
                    Button { model.pause() } label: { Label("Pause", systemImage: "pause") }
                }
                Button {
                    model.startFocus()
                    onClose()
                } label: { Label("Back to Focus", systemImage: "arrow.uturn.backward") }
                    .help("End the break early and start a focus session")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(Spacing.xl)
    }

    // MARK: Activities

    private var activityPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Optional — pick an activity, or simply step away from the screen.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondaryText)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.m), GridItem(.flexible(), spacing: Spacing.m)], spacing: Spacing.m) {
                ForEach(BreakActivity.all) { activity in
                    Button {
                        var newRun = ActivityRun(activity: activity)
                        newRun.start(at: Date())
                        run = newRun
                    } label: {
                        ActivityCard(activity: activity, done: finished.contains(activity.kind))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(activity.title), \(Int(activity.duration)) seconds. \(activity.summary)\(finished.contains(activity.kind) ? ", done" : "")")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.xl)
    }

    private var completeState: some View {
        VStack(spacing: Spacing.l) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Palette.success)
            Text("Break complete")
                .font(.system(size: 20, weight: .semibold))
            Text("Nice reset. Start your next focus session when you're ready.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)
            HStack(spacing: Spacing.s) {
                Button("Not Now") {
                    model.dismissBreakComplete()
                    onClose()
                }
                .buttonStyle(SecondaryButtonStyle())
                .frame(width: 140)
                Button {
                    model.startFocus()
                    onClose()
                } label: { Label("Start Focus", systemImage: "play.fill") }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(width: 180)
                    .keyboardShortcut(.defaultAction)
            }
            Spacer()
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ActivityCard: View {
    var activity: BreakActivity
    var done: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                Image(systemName: activity.systemImage)
                    .font(.system(size: 18))
                    .foregroundStyle(Palette.accentText)
                Spacer()
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Palette.success)
                }
            }
            Text(activity.title)
                .font(.system(size: 14, weight: .semibold))
            Text(activity.summary)
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondaryText)
                .lineLimit(2)
            Text(DurationFormatter.clock(activity.duration))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(Palette.secondaryText)
        }
        .padding(Spacing.m + 2)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Radius.large, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.large, style: .continuous).strokeBorder(Palette.separator.opacity(0.6), lineWidth: 0.5))
        .contentShape(Rectangle())
    }
}

struct ActivityRunnerView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var run: ActivityRun
    var onFinish: () -> Void
    var onSkip: () -> Void

    var body: some View {
        let now = model.now
        let remaining = run.remaining(at: now)
        let isDone = run.isFinished(at: now)
        VStack(spacing: Spacing.l) {
            HStack {
                Label(run.activity.title, systemImage: run.activity.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            ZStack {
                if run.activity.kind == .mind && !isDone {
                    BreathingView(isRunning: run.hasStarted && !run.isPaused)
                } else {
                    ProgressRing(progress: 1 - remaining / run.activity.duration, tint: Palette.accent, lineWidth: 6)
                }
                VStack(spacing: 2) {
                    if isDone {
                        Image(systemName: "checkmark")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Palette.success)
                        Text("Done").font(.system(size: 13)).foregroundStyle(Palette.secondaryText)
                    } else {
                        Text(DurationFormatter.clock(remaining))
                            .font(Typography.countdown)
                    }
                }
            }
            .frame(width: 170, height: 170)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isDone ? "\(run.activity.title) done" : "\(Int(remaining.rounded(.up))) seconds left")

            Text(currentStep(at: now))
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360)
                .animation(nil, value: now)
            if let note = run.activity.note {
                Text(note)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.secondaryText)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
            HStack(spacing: Spacing.s) {
                if isDone {
                    Button { onFinish() } label: { Label("Finish", systemImage: "checkmark") }
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                } else {
                    if !run.hasStarted {
                        Button { run.start(at: Date()) } label: { Label("Start", systemImage: "play.fill") }
                    } else if run.isPaused {
                        Button { run.resume(at: Date()) } label: { Label("Resume", systemImage: "play.fill") }
                    } else {
                        Button { run.pause(at: Date()) } label: { Label("Pause", systemImage: "pause.fill") }
                    }
                    Button { onFinish() } label: { Label("Finish", systemImage: "checkmark") }
                    Button { onSkip() } label: { Label("Skip", systemImage: "forward.end") }
                }
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(Spacing.xl)
    }

    private func currentStep(at now: Date) -> String {
        let steps = run.activity.steps
        guard steps.count > 1 else { return steps.first ?? "" }
        let slice = run.activity.duration / Double(steps.count)
        let index = min(steps.count - 1, max(0, Int(run.elapsed(at: now) / slice)))
        return steps[index]
    }
}

/// A slow breathing guide: 4 s in, 6 s out. With Reduce Motion on, the circle
/// stays still and the text cue changes instead.
struct BreathingView: View {
    var isRunning: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var origin = Date()

    private let inhale: TimeInterval = 4
    private let exhale: TimeInterval = 6

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 0.5 : 1.0 / 30, paused: !isRunning)) { context in
            let t = context.date.timeIntervalSince(origin).truncatingRemainder(dividingBy: inhale + exhale)
            let inhaling = t < inhale
            let fraction = inhaling ? t / inhale : 1 - (t - inhale) / exhale
            let eased = 0.5 - cos(fraction * .pi) / 2
            let scale = reduceMotion ? 0.8 : 0.55 + 0.45 * eased
            ZStack {
                Circle()
                    .fill(Palette.success.opacity(0.18))
                    .scaleEffect(scale)
                Circle()
                    .stroke(Palette.success.opacity(0.6), lineWidth: 2)
                    .scaleEffect(scale)
                if isRunning {
                    Text(inhaling ? "Breathe in" : "Breathe out")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.secondaryText)
                        .offset(y: 46)
                }
            }
        }
        .onAppear { origin = Date() }
    }
}
