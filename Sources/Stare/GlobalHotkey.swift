import AppKit
import Carbon.HIToolbox

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

/// The two system-wide shortcuts: drawing and the pointer highlight.
enum HotkeyDefaults {
    static let keyCode = UInt32(kVK_ANSI_A)
    static let carbonModifiers = UInt32(optionKey | shiftKey)
    static let displayName = "⌥⇧A"

    static let pointerKeyCode = UInt32(kVK_ANSI_M)
    static let pointerDisplayName = "⌥⇧M"
}
