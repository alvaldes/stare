import AppKit
import Carbon.HIToolbox
import StareCore

/// Registry behind the single Carbon event handler. It lives at file scope so
/// the C function pointer below captures nothing.
private enum HotkeyRegistry {
    static var actions: [UInt32: () -> Void] = [:]
    static var nextID: UInt32 = 1
    static var installedHandler: EventHandlerRef?
    static let signature: OSType = 0x5354_4152 // 'STAR'
}

/// Registers the global drawing shortcut. `RegisterEventHotKey` is system-wide
/// and needs no Accessibility or Input Monitoring permission, which is what
/// keeps drawing permission-free.
final class GlobalHotkey {
    private var reference: EventHotKeyRef?
    private let id: UInt32

    /// Convenience for the persisted bindings (T9/S6): maps a
    /// `HotkeyBinding`'s physical key and modifier set onto the Carbon
    /// registration below.
    convenience init?(binding: HotkeyBinding, action: @escaping () -> Void) {
        self.init(
            keyCode: binding.key.keyCode,
            carbonModifiers: binding.modifiers.carbonFlags,
            action: action
        )
    }

    init?(
        keyCode: UInt32,
        carbonModifiers: UInt32,
        action: @escaping () -> Void
    ) {
        guard Self.installSharedHandlerIfNeeded() else { return nil }

        let id = HotkeyRegistry.nextID
        HotkeyRegistry.nextID += 1
        self.id = id
        HotkeyRegistry.actions[id] = action

        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: HotkeyRegistry.signature, id: id)
        let status = RegisterEventHotKey(
            keyCode,
            carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )

        guard status == noErr, let reference else {
            HotkeyRegistry.actions[id] = nil
            return nil
        }
        self.reference = reference
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        HotkeyRegistry.actions[id] = nil
    }

    private static func installSharedHandlerIfNeeded() -> Bool {
        if HotkeyRegistry.installedHandler != nil { return true }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                guard let event else { return OSStatus(eventNotHandledErr) }

                var hotKeyID = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard parameterStatus == noErr,
                      let action = HotkeyRegistry.actions[hotKeyID.id] else {
                    return OSStatus(eventNotHandledErr)
                }

                DispatchQueue.main.async(execute: action)
                return noErr
            },
            1,
            &spec,
            nil,
            &HotkeyRegistry.installedHandler
        )
        return status == noErr
    }
}

/// A refused global-hotkey registration (T9/S6), reported to the Settings
/// pane so the refusal is visible instead of silent: the system rejected the
/// binding — usually because another app owns it — and the previous binding
/// stayed registered. Runtime state, never persisted.
struct HotkeyRejection: Equatable {
    let action: HotkeyAction
    /// The binding the system refused.
    let binding: HotkeyBinding
}

/// Registers the four global hotkeys from the live `HotkeyBindings` (T9/S6).
/// The invariant it holds: for every action there is at most one registration
/// live, and a failed re-registration never drops the previous one — the old
/// hotkey stays armed, so a refused shortcut keeps the app's previous
/// binding working instead of leaving the action unreachable.
final class GlobalHotkeyManager {
    private var registered: [HotkeyAction: (hotkey: GlobalHotkey, binding: HotkeyBinding)] = [:]

    /// The bindings actually registered right now, as the system sees them.
    var registeredBindings: [HotkeyAction: HotkeyBinding] {
        registered.mapValues(\.binding)
    }

    /// Registers (or re-registers) `action` with `binding`. A binding that is
    /// already registered is left alone — the handler is not replaced, so a
    /// no-op refresh cannot double-fire. A new binding is registered before
    /// the old one is released, and only a successful registration replaces
    /// it: a failure keeps the previous binding live.
    @discardableResult
    func apply(_ binding: HotkeyBinding, to action: HotkeyAction, handler: @escaping () -> Void) -> Bool {
        if let current = registered[action], current.binding == binding { return true }
        guard binding.isValid, let hotkey = GlobalHotkey(binding: binding, action: handler) else {
            return false
        }
        registered[action] = (hotkey, binding)
        // The previous GlobalHotkey is released here; its deinit unregisters
        // it and removes its handler entry, so nothing leaks or double-fires.
        return true
    }

    /// Applies every action's binding; the per-action outcome is the report
    /// the caller surfaces. Each action is registered independently, so one
    /// refusal leaves the other three working.
    func applyAll(_ bindings: HotkeyBindings, handlers: [HotkeyAction: () -> Void]) -> [HotkeyAction: Bool] {
        var outcomes: [HotkeyAction: Bool] = [:]
        for action in HotkeyAction.allCases {
            outcomes[action] = apply(bindings[action], to: action, handler: handlers[action] ?? {})
        }
        return outcomes
    }
}

/// The system-wide shortcuts: drawing, the pointer highlight, pinning and the
/// whiteboard.
enum HotkeyDefaults {
    static let keyCode = UInt32(kVK_ANSI_A)
    static let carbonModifiers = UInt32(optionKey | shiftKey)
    static let displayName = "⌥⇧A"

    static let pointerKeyCode = UInt32(kVK_ANSI_M)
    static let pointerDisplayName = "⌥⇧M"

    static let pinKeyCode = UInt32(kVK_ANSI_P)
    static let pinDisplayName = "⌥⇧P"

    /// T6: the whiteboard replaces the transparent overlay with an opaque,
    /// permission-free board, so it gets its own global shortcut.
    static let whiteboardKeyCode = UInt32(kVK_ANSI_W)
    static let whiteboardDisplayName = "⌥⇧W"
}
