import FlowBreakCore
import SwiftUI

/// Short, skippable first-run tour. Permissions are requested only after
/// their value has been explained.
struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    var onFinish: () -> Void

    private enum Page: Int, CaseIterable {
        case welcome, rhythm, interval, tracking, notifications, ready
    }

    @State private var page: Page = .welcome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if page != .ready {
                    Button("Skip") { finish(startFocus: false) }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.secondaryText)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .frame(height: 24)
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.m)

            Group {
                switch page {
                case .welcome: welcome
                case .rhythm: rhythm
                case .interval: interval
                case .tracking: tracking
                case .notifications: notifications
                case .ready: ready
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 48)
            .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            .id(page)

            footer
        }
        .frame(width: 560, height: 500)
        .background(Palette.canvas)
    }

    // MARK: Pages

    private var welcome: some View {
        VStack(spacing: Spacing.l) {
            BrandMark(size: 88)
            Text("Make room for better focus.")
                .font(.system(size: 24, weight: .semibold))
                .multilineTextAlignment(.center)
            Text("FlowBreak lives quietly in your menu bar and reminds you to pause, rest your eyes, and move — then helps you get back into flow.")
                .font(.system(size: 14))
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    private var rhythm: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            title("Focus, then a short break")
            row("timer", "Focus sessions", "Start a session from the menu bar. The countdown keeps time correctly even if your Mac sleeps.")
            row("leaf", "Breaks", "When a session ends, FlowBreak suggests a short break with optional eye, movement, water or breathing activities.")
            row("chart.bar.xaxis", "Insights", "See your focus time and breaks for today, the last week, or the last month.")
        }
    }

    private var interval: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            title("How long do you like to focus?")
            Text("You can change this any time.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.secondaryText)
            VStack(spacing: Spacing.s) {
                ForEach(AppSettings.focusPresets, id: \.self) { minutes in
                    choice(
                        title: "\(minutes) minutes",
                        detail: minutes == 45 ? "Recommended starting point" : (minutes == 25 ? "Short, frequent sessions" : "Longer deep-work blocks"),
                        selected: model.settings.timerMode == .focus && model.settings.focusMinutes == minutes
                    ) {
                        model.update {
                            $0.timerMode = .focus
                            $0.focusMinutes = minutes
                        }
                    }
                }
                choice(
                    title: "Pomodoro",
                    detail: "25 min work, 5 min breaks, a 15 min break every 4 sessions",
                    selected: model.settings.timerMode == .pomodoro
                ) {
                    model.update { $0.timerMode = .pomodoro }
                }
            }
        }
    }

    private var tracking: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            title("Optional: app usage")
            Text("FlowBreak can show which apps you spent time in. It's off unless you turn it on.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.secondaryText)
            row("checkmark.shield", "Only the basics", "Just the frontmost app's name and approximate time. Never keystrokes, screenshots, window titles or documents.")
            row("internaldrive", "Stays on this Mac", "No account and no cloud. Export or delete it any time.")
            Toggle("Record app usage", isOn: Binding(
                get: { model.settings.appTrackingEnabled },
                set: { value in model.update { $0.appTrackingEnabled = value } }
            ))
            .toggleStyle(.switch)
        }
    }

    private var notifications: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            title("Get a nudge when it's time")
            Text("FlowBreak uses macOS notifications to tell you when a focus session ends, with Take a break and Snooze 5 min buttons. If you don't respond, it reminds you up to 3 more times, 5 minutes apart.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("A Focus mode or Do Not Disturb may hold notifications back — the menu bar shows “Break” either way.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                switch model.notificationStatus {
                case .authorized:
                    Label("Notifications allowed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Palette.success)
                case .denied:
                    Label("Notifications are turned off", systemImage: "bell.slash")
                        .foregroundStyle(Palette.warning)
                    Button("Open Settings…") { model.openNotificationSettings() }
                case .unavailable:
                    Label("Notifications need the installed app", systemImage: "info.circle")
                        .foregroundStyle(Palette.secondaryText)
                case .notDetermined, .unknown:
                    Button {
                        model.requestNotificationPermission()
                    } label: {
                        Label("Allow Notifications", systemImage: "bell.badge")
                    }
                    .controlSize(.large)
                }
            }
        }
    }

    private var ready: some View {
        VStack(spacing: Spacing.l) {
            BrandMark(size: 64)
            Text("You're all set")
                .font(.system(size: 22, weight: .semibold))
            Text("Look for the leaf in your menu bar. Click it any time to start, pause, or take a break.")
                .font(.system(size: 14))
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)
            Button {
                finish(startFocus: true)
            } label: {
                Label("Start First Focus Session", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .frame(width: 260)
            .keyboardShortcut(.defaultAction)
            Button("Not now") { finish(startFocus: false) }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.secondaryText)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("Back") { go(-1) }
                .opacity(page == .welcome ? 0 : 1)
                .disabled(page == .welcome)
            Spacer()
            HStack(spacing: 6) {
                ForEach(Page.allCases, id: \.rawValue) { p in
                    Circle()
                        .fill(p == page ? Palette.accent : Palette.track)
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(page.rawValue + 1) of \(Page.allCases.count)")
            Spacer()
            Button(page == .notifications ? "Continue" : "Next") { go(1) }
                .opacity(page == .ready ? 0 : 1)
                .disabled(page == .ready)
                .keyboardShortcut(page == .ready ? nil : .defaultAction)
        }
        .padding(.horizontal, Spacing.xxl)
        .padding(.bottom, Spacing.xl)
    }

    // MARK: Helpers

    private func go(_ delta: Int) {
        guard let next = Page(rawValue: page.rawValue + delta) else { return }
        if reduceMotion {
            page = next
        } else {
            withAnimation(.easeOut(duration: 0.25)) { page = next }
        }
    }

    private func finish(startFocus: Bool) {
        model.completeOnboarding()
        if startFocus { model.startFocus() }
        onFinish()
    }

    private func title(_ text: String) -> some View {
        Text(text).font(.system(size: 20, weight: .semibold))
    }

    private func row(_ icon: String, _ heading: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Palette.accentText)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(heading).font(.system(size: 13, weight: .semibold))
                Text(body).font(.system(size: 13)).foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func choice(title: String, detail: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(detail).font(.system(size: 12)).foregroundStyle(Palette.secondaryText)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Palette.accentText : Palette.secondaryText)
            }
            .padding(Spacing.m)
            .background(
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .fill(selected ? Palette.accent.opacity(0.14) : Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .strokeBorder(selected ? Palette.accent : Palette.separator.opacity(0.6), lineWidth: selected ? 1.5 : 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
