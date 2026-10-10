import AppKit
import FlowBreakCore
import SwiftUI

/// `FlowBreak --render-previews <dir>` renders the real views in every required
/// state, in light and dark appearance, to PNG files. It uses a temporary data
/// directory and an isolated defaults suite, so it never touches the user's data.
/// CI runs it to produce reviewable screenshots of each build.
@MainActor
enum PreviewRenderer {
    static func run(outputDirectory: URL) -> Int32 {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        } catch {
            print("Cannot create \(outputDirectory.path): \(error)")
            return 1
        }
        var count = 0
        var failures = 0
        for (suffix, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            guard let appearance = NSAppearance(named: appearanceName) else { continue }
            for scenario in scenarios() {
                let model = makeModel()
                let view = scenario.build(model)
                let url = outputDirectory.appendingPathComponent("\(scenario.name)-\(suffix).png")
                if render(view, model: model, size: scenario.size, appearance: appearance, to: url) {
                    count += 1
                } else {
                    failures += 1
                    print("Failed to render \(scenario.name)-\(suffix)")
                }
            }
        }
        print("Rendered \(count) previews to \(outputDirectory.path)")
        return failures == 0 ? 0 : 1
    }

    private struct Scenario {
        var name: String
        var size: NSSize?
        var build: (AppModel) -> AnyView
    }

    private static func makeModel() -> AppModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FlowBreakPreview-\(UUID().uuidString)")
        let suite = "FlowBreak.preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        var settings = AppSettings()
        settings.hasCompletedOnboarding = true
        let settingsStore = SettingsStore(defaults: defaults)
        settingsStore.save(settings)
        let model = AppModel(store: JSONFileStore(directory: directory), settingsStore: settingsStore, notifications: NotificationService(enabled: false))
        model.setPreviewState(notificationStatus: .authorized)
        return model
    }

    private static func popover(_ model: AppModel) -> AnyView {
        AnyView(MenuBarView().environmentObject(model))
    }

    private static func scenarios() -> [Scenario] {
        let minute: TimeInterval = 60
        return [
            Scenario(name: "01-popover-idle", size: nil) { model in
                let now = Date()
                model.driveForPreview(now: now) { _ in }
                return popover(model)
            },
            Scenario(name: "02-popover-focusing", size: nil) { model in
                let now = Date()
                model.driveForPreview(now: now) { engine in
                    engine.startFocus(at: now.addingTimeInterval(-12 * minute - 25))
                }
                return popover(model)
            },
            Scenario(name: "03-popover-paused", size: nil) { model in
                let now = Date()
                model.driveForPreview(now: now) { engine in
                    engine.startFocus(at: now.addingTimeInterval(-30 * minute))
                    engine.pause(at: now.addingTimeInterval(-4 * minute))
                }
                return popover(model)
            },
            Scenario(name: "04-popover-break-due", size: nil) { model in
                let now = Date()
                model.driveForPreview(now: now) { engine in
                    engine.startFocus(at: now.addingTimeInterval(-46 * minute))
                    engine.reconcile(at: now)
                }
                return popover(model)
            },
            Scenario(name: "05-popover-on-break", size: nil) { model in
                let now = Date()
                model.driveForPreview(now: now) { engine in
                    engine.startFocus(at: now.addingTimeInterval(-47 * minute))
                    engine.reconcile(at: now.addingTimeInterval(-2 * minute))
                    engine.startBreak(at: now.addingTimeInterval(-1 * minute - 40))
                    engine.reconcile(at: now)
                }
                return popover(model)
            },
            Scenario(name: "06-popover-break-complete", size: nil) { model in
                let now = Date()
                model.driveForPreview(now: now) { engine in
                    engine.startBreak(at: now.addingTimeInterval(-6 * minute))
                    engine.reconcile(at: now)
                }
                return popover(model)
            },
            Scenario(name: "07-popover-notifications-denied", size: nil) { model in
                let now = Date()
                model.driveForPreview(now: now) { engine in
                    engine.startFocus(at: now.addingTimeInterval(-50 * minute))
                    engine.reconcile(at: now)
                    engine.snooze(for: 5 * minute, at: now)
                }
                model.setPreviewState(notificationStatus: .denied)
                return popover(model)
            },
            Scenario(name: "08-popover-pomodoro-error", size: nil) { model in
                model.update { $0.timerMode = .pomodoro }
                let now = Date()
                model.driveForPreview(now: now) { engine in
                    var t = now.addingTimeInterval(-3 * 31 * minute)
                    for _ in 0..<2 {
                        engine.startFocus(at: t)
                        t = t.addingTimeInterval(25 * minute)
                        engine.reconcile(at: t)
                        engine.startBreak(at: t)
                        t = t.addingTimeInterval(5 * minute)
                        engine.reconcile(at: t)
                    }
                    engine.stop(at: t)
                }
                model.setPreviewState(notificationStatus: .authorized, error: "FlowBreak couldn't save sessions.json. (The disk is full.)")
                return popover(model)
            },
            Scenario(name: "10-guided-break-picker", size: NSSize(width: 480, height: 600)) { model in
                let now = Date()
                model.driveForPreview(now: now) { engine in
                    engine.startBreak(at: now.addingTimeInterval(-50))
                }
                return AnyView(GuidedBreakView(onClose: {}).environmentObject(model))
            },
            Scenario(name: "11-guided-break-breathing", size: NSSize(width: 480, height: 600)) { model in
                let now = Date()
                model.driveForPreview(now: now) { engine in
                    engine.startBreak(at: now.addingTimeInterval(-90))
                }
                return AnyView(GuidedBreakView(onClose: {}, initialActivity: .mind, startedAt: now.addingTimeInterval(-22)).environmentObject(model))
            },
            Scenario(name: "12-guided-break-movement", size: NSSize(width: 480, height: 600)) { model in
                let now = Date()
                model.driveForPreview(now: now) { engine in
                    engine.startBreak(at: now.addingTimeInterval(-120))
                }
                return AnyView(GuidedBreakView(onClose: {}, initialActivity: .movement, startedAt: now.addingTimeInterval(-25)).environmentObject(model))
            },
            Scenario(name: "13-guided-break-complete", size: NSSize(width: 480, height: 600)) { model in
                let now = Date()
                model.driveForPreview(now: now) { engine in
                    engine.startBreak(at: now.addingTimeInterval(-6 * minute))
                    engine.reconcile(at: now)
                }
                return AnyView(GuidedBreakView(onClose: {}).environmentObject(model))
            },
            Scenario(name: "20-insights-empty", size: NSSize(width: 760, height: 900)) { model in
                model.driveForPreview(now: Date()) { _ in }
                return AnyView(InsightsView().environmentObject(model))
            },
            Scenario(name: "21-insights-week", size: NSSize(width: 760, height: 1400)) { model in
                seedHistory(model)
                return AnyView(InsightsView(initialRange: .last7Days).environmentObject(model))
            },
            Scenario(name: "22-insights-today", size: NSSize(width: 760, height: 1400)) { model in
                seedHistory(model)
                return AnyView(InsightsView(initialRange: .today).environmentObject(model))
            },
            Scenario(name: "30-settings-focus", size: NSSize(width: 580, height: 720)) { model in
                model.settingsTab = .focus
                return AnyView(SettingsView().environmentObject(model))
            },
            Scenario(name: "31-settings-reminders", size: NSSize(width: 580, height: 640)) { model in
                model.settingsTab = .reminders
                model.update { $0.quietHoursEnabled = true }
                return AnyView(SettingsView().environmentObject(model))
            },
            Scenario(name: "32-settings-privacy", size: NSSize(width: 580, height: 760)) { model in
                model.settingsTab = .privacy
                return AnyView(SettingsView().environmentObject(model))
            },
            Scenario(name: "33-settings-general", size: NSSize(width: 580, height: 600)) { model in
                model.settingsTab = .general
                return AnyView(SettingsView().environmentObject(model))
            },
            Scenario(name: "34-settings-about", size: NSSize(width: 580, height: 600)) { model in
                model.settingsTab = .about
                return AnyView(SettingsView().environmentObject(model))
            },
        ] + OnboardingView.Page.allCases.map { page in
            Scenario(name: "4\(page.rawValue)-onboarding-\(page)", size: NSSize(width: 560, height: 500)) { model in
                model.setPreviewState(notificationStatus: .notDetermined)
                return AnyView(OnboardingView(initialPage: page, onFinish: {}).environmentObject(model))
            }
        } + [
            Scenario(name: "50-notification-concept", size: NSSize(width: 420, height: 230)) { _ in
                AnyView(NotificationConceptView())
            },
            Scenario(name: "51-menu-bar-items", size: NSSize(width: 480, height: 150)) { _ in
                AnyView(MenuBarItemsConceptView())
            },
        ]
    }

    /// A week of plausible history, generated through the real engine so every
    /// record is internally consistent. Preview-only; never written to user data.
    private static func seedHistory(_ model: AppModel) {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let minute: TimeInterval = 60
        model.driveForPreview(now: now) { engine in
            for dayOffset in stride(from: -6, through: 0, by: 1) {
                guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }
                let sessionsToday = [3, 4, 2, 5, 3, 1, 4][(dayOffset + 6) % 7]
                var t = day.addingTimeInterval(9 * 3600 + Double((dayOffset + 6) * 7) * minute)
                for index in 0..<sessionsToday {
                    if t.addingTimeInterval(50 * minute) > now { break }
                    engine.startFocus(at: t)
                    if index == 2 {
                        engine.pause(at: t.addingTimeInterval(20 * minute))
                        t = t.addingTimeInterval(30 * minute)
                        engine.resume(at: t)
                        t = t.addingTimeInterval(25 * minute)
                    } else {
                        t = t.addingTimeInterval(45 * minute)
                    }
                    engine.reconcile(at: t)
                    if index % 3 != 1 {
                        engine.startBreak(at: t.addingTimeInterval(minute))
                        t = t.addingTimeInterval(6 * minute)
                        engine.reconcile(at: t)
                        engine.dismissBreakComplete(at: t)
                    } else {
                        engine.skipBreak(at: t.addingTimeInterval(2 * minute))
                    }
                    t = t.addingTimeInterval(20 * minute)
                }
            }
        }
        model.update { $0.appTrackingEnabled = true }
        let apps: [(String, String, Double)] = [
            ("com.apple.dt.Xcode", "Xcode", 140), ("com.apple.Safari", "Safari", 85),
            ("com.tinyspeck.slackmacgap", "Slack", 40), ("com.apple.mail", "Mail", 25),
            ("com.figma.Desktop", "Figma", 55), ("com.apple.Notes", "Notes", 12),
        ]
        var samples: [UsageSample] = []
        let start = today.addingTimeInterval(9 * 3600)
        var t = start
        for (id, name, minutes) in apps {
            samples.append(UsageSample(bundleID: id, appName: name, start: t, end: t.addingTimeInterval(minutes * minute)))
            t = t.addingTimeInterval(minutes * minute)
        }
        model.setPreviewState(notificationStatus: .authorized, usage: samples.filter { $0.end <= now })
    }

    private static func render(_ view: AnyView, model: AppModel, size: NSSize?, appearance: NSAppearance, to url: URL) -> Bool {
        let root = view
            .background(Color(nsColor: .windowBackgroundColor))
        let hosting = NSHostingView(rootView: root)
        hosting.appearance = appearance
        let targetSize = size ?? hosting.fittingSize
        let window = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: targetSize.width, height: targetSize.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = appearance
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: targetSize)
        window.orderFrontRegardless()
        // Let SwiftUI lay out, resolve fonts and draw.
        for _ in 0..<6 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            hosting.layoutSubtreeIfNeeded()
        }
        defer { window.close() }

        var success = false
        appearance.performAsCurrentDrawingAppearance {
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else { return }
            success = (try? data.write(to: url)) != nil
        }
        return success
    }
}

/// Design concept of the break notification as macOS presents it (used only in
/// the rendered design sheet; the real notification is drawn by macOS).
struct NotificationConceptView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Spacing.m) {
                BrandMark(size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("FlowBreak").font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text("now").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Text("Time to reset").font(.system(size: 13, weight: .semibold))
                    Text("Take a 5-minute break.").font(.system(size: 13))
                }
            }
            .padding(Spacing.m)
            Divider()
            HStack(spacing: 0) {
                ForEach(["Take a break", "Snooze 5 min", "Dismiss"], id: \.self) { title in
                    Text(title)
                        .font(.system(size: 12, weight: title == "Take a break" ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.s)
                    if title != "Dismiss" { Divider().frame(height: 28) }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
        .frame(width: 360)
        .padding(Spacing.xxl)
    }
}

/// How the status item reads in each state (the real item is drawn by macOS
/// from the same template image and title).
struct MenuBarItemsConceptView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            item(nil, "Ready")
            item("32:35", "Focusing (countdown can be turned off)")
            item("Break", "Break due — fallback when notifications are off")
            item("03:20", "On break")
        }
        .padding(Spacing.l)
    }

    private func item(_ title: String?, _ caption: String) -> some View {
        HStack(spacing: Spacing.l) {
            HStack(spacing: 4) {
                Image(nsImage: LogoRenderer.menuBarImage())
                    .renderingMode(.template)
                if let title {
                    Text(title).font(.system(size: 13, weight: .medium).monospacedDigit())
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.06)))
            .frame(width: 110, alignment: .leading)
            Text(caption).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}
