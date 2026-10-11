import AppKit
import SwiftUI

/// Creates and reuses the app's windows (settings, insights, onboarding, guided break).
@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var windows: [AppWindow: NSWindow] = [:]
    private lazy var quickAdd = QuickAddController(model: model)

    init(model: AppModel) {
        self.model = model
    }

    func show(_ kind: AppWindow) {
        if kind == .quickAdd {
            quickAdd.show()
            return
        }
        let window = windows[kind] ?? makeWindow(kind)
        windows[kind] = window
        if kind == .settings { model.refreshLaunchAtLogin() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close(_ kind: AppWindow) {
        windows[kind]?.close()
    }

    private func makeWindow(_ kind: AppWindow) -> NSWindow {
        let content: AnyView
        let title: String
        let size: NSSize
        switch kind {
        case .settings:
            content = AnyView(SettingsView())
            title = "FlowBreak Settings"
            size = NSSize(width: 580, height: 560)
        case .insights:
            content = AnyView(InsightsView())
            title = "FlowBreak Insights"
            size = NSSize(width: 760, height: 680)
        case .onboarding:
            content = AnyView(OnboardingView(onFinish: { [weak self] in self?.close(.onboarding) }))
            title = "Welcome to FlowBreak"
            size = NSSize(width: 560, height: 500)
        case .guidedBreak:
            content = AnyView(GuidedBreakView(onClose: { [weak self] in self?.close(.guidedBreak) }))
            title = "Break"
            size = NSSize(width: 480, height: 600)
        case .tasks:
            content = AnyView(TasksView())
            title = "FlowBreak Tasks"
            size = NSSize(width: 1020, height: 680)
        case .quickAdd:
            content = AnyView(EmptyView())
            title = ""
            size = .zero
        }

        let hosting = NSHostingController(rootView: content.environmentObject(model))
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.setContentSize(size)
        window.styleMask = [.titled, .closable, .miniaturizable]
        if kind == .insights || kind == .settings || kind == .tasks {
            window.styleMask.insert(.resizable)
            window.contentMinSize = NSSize(width: size.width - 80, height: size.height - 120)
        }
        if kind == .onboarding || kind == .guidedBreak {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
        }
        if kind == .guidedBreak {
            window.level = .floating
        }
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("FlowBreak.\(kind.rawValue)")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let kind = windows.first(where: { $0.value === window })?.key else { return }
        if kind == .onboarding && !model.settings.hasCompletedOnboarding {
            // Closing onboarding counts as skipping it; everything stays at defaults.
            model.completeOnboarding()
        }
        // Drop the window so its SwiftUI state (e.g. a running activity) resets next time.
        windows[kind] = nil
    }
}
