import AppKit
import FlowBreakCore
import SwiftUI

/// A small floating panel for capturing a task from anywhere. It doesn't activate
/// FlowBreak, so after saving (Return) or cancelling (Escape) you're right back in
/// the app you were using.
final class QuickAddPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class QuickAddController {
    private var panel: QuickAddPanel?
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let frame = screen.visibleFrame
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - frame.height * 0.18))
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
        // Rebuild next time so the field starts empty and focused.
        panel = nil
    }

    private func makePanel() -> QuickAddPanel {
        let panel = QuickAddPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 96),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = QuickAddView(onClose: { [weak self] in self?.close() }).environmentObject(model)
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentViewController = hosting
        return panel
    }
}

struct QuickAddView: View {
    @EnvironmentObject private var model: AppModel
    var onClose: () -> Void
    @State private var text: String
    @State private var parse = true
    @State private var destination: TaskStatus = .inbox
    @State private var confirmation: String?
    @FocusState private var focused: Bool

    init(onClose: @escaping () -> Void, initialText: String = "") {
        self.onClose = onClose
        _text = State(initialValue: initialText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            QuickAddField(text: $text, parse: $parse, list: destination == .today ? .today : .inbox, placeholder: "Capture a task — e.g. Call Sam tomorrow #home 15m", focused: $focused) { task in
                guard let task else { return }
                confirmation = "Added “\(task.title)” to \(task.status.displayName)"
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    onClose()
                }
            }
            HStack(spacing: Spacing.m) {
                Picker("Add to", selection: $destination) {
                    Text("Inbox").tag(TaskStatus.inbox)
                    Text("Today").tag(TaskStatus.today)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                .labelsHidden()
                if let confirmation {
                    Label(confirmation, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Palette.success)
                        .lineLimit(1)
                } else {
                    Text("Return to save · Esc to cancel")
                        .foregroundStyle(Palette.secondaryText)
                }
                Spacer()
            }
            .font(.system(size: 11))
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
        .frame(width: 560)
        .background(Palette.canvas.opacity(0.4))
        .onAppear {
            Task { @MainActor in focused = true }
        }
        .onExitCommand { onClose() }
    }
}
