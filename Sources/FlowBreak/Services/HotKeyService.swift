import AppKit
import Carbon.HIToolbox
import FlowBreakCore

/// System-wide keyboard shortcuts via Carbon's `RegisterEventHotKey` — a public API
/// that needs no Accessibility permission and never sees other keystrokes.
/// Nothing is registered unless the user picks a shortcut in Settings.
final class HotKeyService {
    enum Action: UInt32, CaseIterable {
        case quickAdd = 1
        case toggleFocus = 2
        case openToday = 3
    }

    private var refs: [Action: EventHotKeyRef] = [:]
    private var handlers: [Action: () -> Void] = [:]
    private var eventHandler: EventHandlerRef?
    private static let signature: OSType = 0x464C_5742 // "FLWB"

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, userData) -> OSStatus in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }
            let service = Unmanaged<HotKeyService>.fromOpaque(userData).takeUnretainedValue()
            service.fire(hotKeyID.id)
            return noErr
        }, 1, &spec, context, &eventHandler)
    }

    deinit {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    /// Registers (or clears) the shortcut for `action`. Returns an error message if
    /// macOS refused it, e.g. because another app already owns that combination.
    func set(_ preset: ShortcutPreset, for action: Action, handler: @escaping () -> Void) -> String? {
        if let ref = refs.removeValue(forKey: action) {
            UnregisterEventHotKey(ref)
        }
        handlers[action] = nil
        guard let keys = Self.keys(for: preset) else { return nil }
        let (keyCode, modifiers) = keys
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: action.rawValue)
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            return "\(preset.displayName) couldn't be registered — another app may already use it. Pick a different shortcut."
        }
        refs[action] = ref
        handlers[action] = handler
        return nil
    }

    private func fire(_ id: UInt32) {
        guard let action = Action(rawValue: id), let handler = handlers[action] else { return }
        handler()
    }

    static func keys(for preset: ShortcutPreset) -> (UInt32, UInt32)? {
        let cmd = UInt32(cmdKey), opt = UInt32(optionKey), ctrl = UInt32(controlKey)
        switch preset {
        case .off: return nil
        case .optionCommandT: return (UInt32(kVK_ANSI_T), opt | cmd)
        case .controlOptionT: return (UInt32(kVK_ANSI_T), ctrl | opt)
        case .controlOptionSpace: return (UInt32(kVK_Space), ctrl | opt)
        case .optionCommandP: return (UInt32(kVK_ANSI_P), opt | cmd)
        case .controlOptionP: return (UInt32(kVK_ANSI_P), ctrl | opt)
        case .optionCommandY: return (UInt32(kVK_ANSI_Y), opt | cmd)
        case .controlOptionY: return (UInt32(kVK_ANSI_Y), ctrl | opt)
        }
    }
}
