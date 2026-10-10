import SwiftUI

/// Circular progress ring with an optional reduced-motion aware animation.
struct ProgressRing: View {
    var progress: Double
    var tint: Color
    var lineWidth: CGFloat = 8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.0001, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: progress)
        }
        .accessibilityHidden(true)
    }
}

/// Small status capsule ("Focusing", "Break due").
struct StatusPill: View {
    var text: String
    var tint: Color
    var systemImage: String?

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .bold))
            } else {
                Circle().fill(tint).frame(width: 6, height: 6)
            }
            Text(text)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.14)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(text)")
    }
}

/// The single prominent, context-aware action.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .fill(Palette.accent.opacity(configuration.isPressed ? 0.8 : 1))
            )
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Rectangle())
    }
}

/// Quiet secondary actions.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, Spacing.s)
            .background(
                RoundedRectangle(cornerRadius: Radius.small + 1, style: .continuous)
                    .fill(Palette.track.opacity(configuration.isPressed ? 1.6 : 1))
            )
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

/// Borderless icon+label used in footers.
struct FooterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(Palette.secondaryText)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: Radius.small)
                    .fill(configuration.isPressed ? Palette.track : Color.clear)
            )
            .contentShape(Rectangle())
    }
}

/// A labelled number. `help` explains how it is calculated.
struct MetricView: View {
    var title: String
    var value: String
    var detail: String?
    var help: String?
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(Palette.secondaryText)
            Text(value)
                .font(compact ? .system(size: 15, weight: .semibold, design: .rounded).monospacedDigit() : Typography.metricValue)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail {
                Text(detail)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(help ?? "")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)\(detail.map { ", \($0)" } ?? "")")
        .accessibilityHint(help ?? "")
    }
}

/// Card container used in windows.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .fill(Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .strokeBorder(Palette.separator.opacity(0.6), lineWidth: 0.5)
            )
    }
}

/// Inline notice for permission problems and errors.
struct Banner: View {
    enum Tone { case info, warning, error }

    var tone: Tone
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    private var tint: Color {
        switch tone {
        case .info: return Palette.secondaryText
        case .warning: return Palette.warning
        case .error: return Color(nsColor: .systemRed)
        }
    }

    private var icon: String {
        switch tone {
        case .info: return "info.circle.fill"
        case .warning: return "bell.slash.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.system(size: 12))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.link)
                        .font(.system(size: 11.5, weight: .medium))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.s + 2)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(tint.opacity(0.10))
        )
        .accessibilityElement(children: .contain)
    }
}

/// Empty / unavailable state with a single helpful action.
struct EmptyStateView: View {
    var systemImage: String
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Spacing.s) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Palette.secondaryText)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.regular)
                    .padding(.top, Spacing.xs)
            }
        }
        .frame(maxWidth: 360)
        .padding(Spacing.xxl)
        .frame(maxWidth: .infinity)
    }
}
