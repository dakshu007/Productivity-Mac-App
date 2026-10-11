import AppKit
import FlowBreakCore
import SwiftUI

/// Shows a gentle, dismissible "Still on your task?" note when a distracting app
/// comes to the front during a running focus session. Uses only the public
/// "app activated" notification; it never blocks or hides anything on its own.
@MainActor
final class NudgeController {
    private let model: AppModel
    private let tracker = NudgeTracker()
    private var observer: NSObjectProtocol?
    private var panel: NSPanel?
    private var dismissWork: DispatchWorkItem?

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            let name = app?.localizedName
            let pid = app?.processIdentifier
            Task { @MainActor in self?.appActivated(bundleID: bundleID, name: name, pid: pid) }
        }
    }

    func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
        close()
    }

    private func appActivated(bundleID: String?, name: String?, pid: pid_t?) {
        guard let bundleID else { return }
        if bundleID == Bundle.main.bundleIdentifier { return }
        let now = Date()
        guard tracker.shouldNudge(bundleID: bundleID, state: model.state, policy: NudgePolicy(settings: model.settings), now: now) else {
            return
        }
        tracker.recordNudge(bundleID: bundleID, now: now)
        model.recordNudge()
        show(appName: name ?? bundleID, bundleID: bundleID, pid: pid)
    }

    private func show(appName: String, bundleID: String, pid: pid_t?) {
        close()
        let view = NudgeView(
            appName: appName,
            taskTitle: model.currentTask?.title,
            remaining: model.remaining,
            onBack: { [weak self] in
                if let pid, let app = NSRunningApplication(processIdentifier: pid) { app.hide() }
                self?.close()
            },
            onSave: { [weak self] in
                self?.close()
                self?.model.openWindow?(.quickAdd)
            },
            onAllow: { [weak self] in
                self?.tracker.allowForSession(bundleID: bundleID)
                self?.close()
            },
            onBreak: { [weak self] in
                self?.close()
                self?.model.startBreak()
            }
        )
        .environmentObject(model)
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = [.preferredContentSize]
        let panel = QuickAddPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 120),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = hosting
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let frame = screen.visibleFrame
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: frame.maxX - size.width - 16, y: frame.maxY - size.height - 12))
        }
        panel.orderFrontRegardless()
        self.panel = panel

        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.close() }
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
    }

    private func close() {
        dismissWork?.cancel()
        panel?.orderOut(nil)
        panel = nil
    }
}

struct NudgeView: View {
    var appName: String
    var taskTitle: String?
    var remaining: TimeInterval
    var onBack: () -> Void
    var onSave: () -> Void
    var onAllow: () -> Void
    var onBreak: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                BrandMark(size: 20)
                Text(taskTitle.map { "Still on “\($0)”?" } ?? "Still in focus time?")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                Spacer(minLength: 0)
                Button(action: onAllow) { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.secondaryText)
                    .help("Allow \(appName) for this session")
                    .accessibilityLabel("Dismiss and allow \(appName) for this session")
            }
            Text("You switched to \(appName) with \(DurationFormatter.clock(remaining)) of focus left. No pressure — just a nudge.")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Button("Back to focus", action: onBack)
                    .help("Hide \(appName) and return to what you were doing")
                Button("Save a thought", action: onSave)
                    .help("Capture it in your Inbox for later")
                Button("Allow this session", action: onAllow)
                Button("Break", action: onBreak)
            }
            .buttonStyle(SmallPillButtonStyle())
        }
        .padding(Spacing.m + 2)
        .frame(width: 380)
        .background(Palette.canvas.opacity(0.5))
    }
}
