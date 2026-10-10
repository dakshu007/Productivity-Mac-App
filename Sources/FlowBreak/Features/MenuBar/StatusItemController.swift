import AppKit
import Combine
import FlowBreakCore
import SwiftUI

/// Owns the menu-bar item and its popover.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []
    private var lastTitle: String?

    init(model: AppModel) {
        self.model = model
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = LogoRenderer.menuBarImage()
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("FlowBreak")
        }

        let hosting = NSHostingController(rootView: MenuBarView().environmentObject(model))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self

        model.closePopover = { [weak self] in self?.closePopover() }

        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateButton() }
            .store(in: &cancellables)
        updateButton()
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    func showPopover() {
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func closePopover() {
        if popover.isShown { popover.performClose(nil) }
    }

    /// Menu-bar label: compact countdown while a session runs (if enabled), and an
    /// always-visible "Break" indicator when a break is due — the in-app fallback
    /// when notifications are off or suppressed by a Focus mode.
    private func updateButton() {
        guard let button = statusItem.button else { return }
        let state = model.state
        var title = ""
        var dimmed = false
        switch state.phase {
        case .focusing, .onBreak:
            if model.settings.showMenuBarCountdown {
                title = DurationFormatter.clock(model.remaining)
                dimmed = state.isPaused
            }
        case .breakDue:
            title = state.breakDue?.snoozedUntil == nil ? "Break" : ""
        case .idle, .breakComplete:
            title = ""
        }
        let key = "\(title)|\(dimmed)"
        guard key != lastTitle else { return }
        lastTitle = key
        if title.isEmpty {
            button.attributedTitle = NSAttributedString(string: "")
            button.imagePosition = .imageOnly
        } else {
            let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .medium)
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .baselineOffset: 0.5]
            if dimmed { attributes[.foregroundColor] = NSColor.secondaryLabelColor }
            button.attributedTitle = NSAttributedString(string: " " + title, attributes: attributes)
            button.imagePosition = .imageLeading
        }
        let accessibility: String
        switch state.phase {
        case .idle: accessibility = "FlowBreak, ready"
        case .focusing: accessibility = state.isPaused ? "FlowBreak, focus paused" : "FlowBreak, focusing, \(DurationFormatter.clock(model.remaining)) left"
        case .breakDue: accessibility = "FlowBreak, break due"
        case .onBreak: accessibility = "FlowBreak, on break, \(DurationFormatter.clock(model.remaining)) left"
        case .breakComplete: accessibility = "FlowBreak, break complete"
        }
        button.setAccessibilityLabel(accessibility)
    }
}
