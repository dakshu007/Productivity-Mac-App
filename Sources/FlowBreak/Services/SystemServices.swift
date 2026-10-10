import AppKit
import CoreGraphics
import FlowBreakCore
import ServiceManagement

/// Launch at login via SMAppService (macOS 13+). The user may need to approve it
/// in System Settings › General › Login Items.
@MainActor
final class LaunchAtLoginService {
    enum Status: Equatable {
        case enabled
        case disabled
        case requiresApproval
        case unavailable(String)
    }

    var status: Status {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return .unavailable("Available when FlowBreak runs from an app bundle.")
        }
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .disabled
        case .notFound: return .unavailable("macOS couldn't find FlowBreak. Move it to Applications and try again.")
        @unknown default: return .disabled
        }
    }

    /// Returns an error message on failure.
    func setEnabled(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// Feeds foreground-application changes into `UsageRecorder`. Uses only public
/// NSWorkspace notifications and the system idle timer. It never reads window
/// titles, documents, URLs, keystrokes or screen contents, and needs no special
/// permissions.
@MainActor
final class AppUsageTracker {
    /// After this much inactivity the user is considered away and time stops counting.
    static let idleThreshold: TimeInterval = 120
    private static let pollInterval: TimeInterval = 15
    private static let checkpointInterval: TimeInterval = 300

    private let recorder: UsageRecorder
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var isIdle = false
    private var lastCheckpoint = Date()

    init(policy: UsagePolicy, onSample: @escaping (UsageSample) -> Void) {
        recorder = UsageRecorder(policy: policy, emit: onSample)
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            let name = app?.localizedName
            Task { @MainActor in self?.activated(bundleID: bundleID, name: name) }
        })
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.suspend(at: Date()) }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.resumeWithFrontmost() }
            })
        }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        resumeWithFrontmost()
    }

    func stop() {
        recorder.suspend(at: Date())
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        timer?.invalidate()
        timer = nil
    }

    func update(policy: UsagePolicy) {
        let wasRecording = recorder.policy.isRecording
        recorder.update(policy: policy, at: Date())
        if policy.isRecording && !wasRecording {
            resumeWithFrontmost()
        }
    }

    /// Closes the open sample (e.g. before export or quit).
    func flush() {
        recorder.checkpoint(at: Date())
    }

    private func activated(bundleID: String?, name: String?) {
        guard !isIdle, let bundleID else { return }
        recorder.appActivated(bundleID: bundleID, appName: name ?? bundleID, at: Date())
    }

    private func suspend(at date: Date) {
        recorder.suspend(at: date)
    }

    private func resumeWithFrontmost() {
        isIdle = false
        guard let app = NSWorkspace.shared.frontmostApplication, let bundleID = app.bundleIdentifier else { return }
        recorder.appActivated(bundleID: bundleID, appName: app.localizedName ?? bundleID, at: Date())
    }

    private func poll() {
        guard recorder.policy.isRecording else { return }
        let now = Date()
        let idle = Self.secondsSinceLastInput()
        if idle >= Self.idleThreshold {
            if !isIdle {
                isIdle = true
                recorder.suspend(at: now.addingTimeInterval(-idle))
            }
            return
        }
        if isIdle {
            resumeWithFrontmost()
        }
        if now.timeIntervalSince(lastCheckpoint) >= Self.checkpointInterval {
            lastCheckpoint = now
            recorder.checkpoint(at: now)
        }
    }

    /// System-wide time since the last keyboard/mouse event. Reads only the idle
    /// duration, never the events themselves.
    private static func secondsSinceLastInput() -> TimeInterval {
        guard let anyInput = CGEventType(rawValue: UInt32.max) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }
}
