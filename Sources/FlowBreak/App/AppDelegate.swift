import AppKit
import FlowBreakCore
import SwiftUI

@main
@MainActor
enum FlowBreakMain {
    private static var delegate: AppDelegate?

    static func main() {
        if CommandLine.arguments.contains("--smoke-test") {
            exit(SmokeTest.run())
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        self.delegate = delegate
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var statusController: StatusItemController?
    private var windows: WindowCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel()
        self.model = model
        NSApp.setActivationPolicy(model.settings.showInDock ? .regular : .accessory)
        NSApp.mainMenu = MainMenu.build()

        let windows = WindowCoordinator(model: model)
        self.windows = windows
        model.openWindow = { [weak windows] kind in windows?.show(kind) }
        statusController = StatusItemController(model: model)
        model.start()

        if !model.settings.hasCompletedOnboarding {
            windows.show(.onboarding)
        }
        Log.app.info("FlowBreak launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.prepareForTermination()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Clicking the Dock icon (when shown) opens the popover-equivalent: Insights.
        if !flag { windows?.show(.insights) }
        return true
    }

    @objc func showSettings(_ sender: Any?) {
        windows?.show(.settings)
    }

    @objc func showInsights(_ sender: Any?) {
        windows?.show(.insights)
    }

    @objc func showAbout(_ sender: Any?) {
        model?.settingsTab = .about
        windows?.show(.settings)
    }
}

/// A minimal main menu so standard shortcuts (⌘W, ⌘Q, ⌘C/⌘V, ⌘,) work in windows.
enum MainMenu {
    @MainActor
    static func build() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "FlowBreak")
        appMenu.addItem(withTitle: "About FlowBreak", action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(withTitle: "Insights", action: #selector(AppDelegate.showInsights(_:)), keyEquivalent: "i")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide FlowBreak", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit FlowBreak", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        return main
    }
}

/// `FlowBreak --smoke-test`: exercises the core engine against a temporary store
/// and exits. Used by CI to check the packaged binary launches.
enum SmokeTest {
    static func run() -> Int32 {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FlowBreakSmoke-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONFileStore(directory: directory)
        let engine = TimerEngine(store: store, configuration: AppSettings().timerConfiguration)
        let start = Date()
        engine.startFocus(at: start)
        engine.reconcile(at: start.addingTimeInterval(45 * 60))
        guard engine.phase == .breakDue, engine.lastPersistenceError == nil else {
            print("FlowBreak smoke test FAILED: phase=\(engine.phase.rawValue) error=\(engine.lastPersistenceError ?? "none")")
            return 1
        }
        _ = LogoRenderer.menuBarImage()
        print("FlowBreak smoke test passed")
        return 0
    }
}
