import AppKit
import ApplicationServices
import Carbon.HIToolbox
import mPIECore

/// Raccourcis globaux par l'API Carbon : aucune autorisation n'est nécessaire. Appui ET relâchement sont remontés
/// (le menu se valide au relâchement de la touche).
@MainActor
final class HotkeyCenter {
    static let shared = HotkeyCenter()
    var onPress: ((HotkeyAction) -> Void)?
    var onRelease: ((HotkeyAction) -> Void)?
    private var registered: [EventHotKeyRef] = []
    private var targets: [UInt32: HotkeyAction] = [:]
    private var handlerInstalled = false
    private static let signature: OSType = 0x6D504945 // « mPIE »

    /// Enregistre les raccourcis ; rend les actions dont le raccourci est déjà pris ailleurs.
    @discardableResult
    func register(_ hotkeys: [(HotkeyAction, Hotkey)]) -> Set<HotkeyAction> {
        unregisterAll()
        installHandler()
        var failures = Set<HotkeyAction>()
        for (index, (action, hotkey)) in hotkeys.enumerated() {
            let number = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(hotkey.keyCode), Self.carbonModifiers(hotkey.modifiers),
                                             EventHotKeyID(signature: Self.signature, id: number),
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { registered.append(ref); targets[number] = action } else { failures.insert(action) }
        }
        return failures
    }

    func unregisterAll() {
        registered.forEach { UnregisterEventHotKey($0) }
        registered = []; targets = [:]
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let number = hotKeyID.id
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            DispatchQueue.main.async { MainActor.assumeIsolated { HotkeyCenter.shared.fire(number, pressed: pressed) } }
            return noErr
        }, 2, &specs, nil, nil)
    }

    private func fire(_ number: UInt32, pressed: Bool) {
        guard let action = targets[number] else { return }
        if pressed { onPress?(action) } else { onRelease?(action) }
    }

    private static func carbonModifiers(_ mask: UInt) -> UInt32 {
        var out = 0
        if mask & Hotkey.command != 0 { out |= cmdKey }
        if mask & Hotkey.option != 0 { out |= optionKey }
        if mask & Hotkey.control != 0 { out |= controlKey }
        if mask & Hotkey.shift != 0 { out |= shiftKey }
        return UInt32(out)
    }
}

/// Souris : appui et relâchement d'un bouton supplémentaire (milieu, 4, 5), dans toute appli. Aucune autorisation requise.
@MainActor
final class MouseTrigger {
    var onDown: ((Int, UInt) -> Void)?
    var onUp: ((Int) -> Void)?
    private var monitors: [Any] = []

    func start() {
        let mask: NSEvent.EventTypeMask = [.otherMouseDown, .otherMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in self?.handle(event) }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in self?.handle(event); return event }) { monitors.append(local) }
    }

    private func handle(_ event: NSEvent) {
        let button = event.buttonNumber, flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
        let down = event.type == .otherMouseDown
        MainActor.assumeIsolated { if down { onDown?(button, flags) } else { onUp?(button) } }
    }
}

/// Code de touche d'un caractère dans la disposition de clavier active (AZERTY compris).
enum KeyMap {
    private static let named: [String: Int] = [
        "delete": kVK_Delete, "return": kVK_Return, "space": kVK_Space, "tab": kVK_Tab, "escape": kVK_Escape,
        "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow, "f12": kVK_F12,
    ]

    static func code(for token: String) -> Int {
        if let code = named[token] { return code }
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return ansi(token) }
        let layout = unsafeBitCast(raw, to: CFData.self) as Data
        for code in 0..<128 {
            var dead: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = layout.withUnsafeBytes { bytes in
                UCKeyTranslate(bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
                               UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, chars.count, &length, &chars)
            }
            if status == noErr, length > 0, String(utf16CodeUnits: chars, count: length).lowercased() == token { return code }
        }
        return ansi(token)
    }

    /// Repli : disposition américaine.
    private static func ansi(_ token: String) -> Int {
        let table: [String: Int] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
            "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29, "o": 31, "u": 32,
            "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46, ",": 43,
        ]
        return table[token] ?? 0
    }
}

/// Envoi d'un raccourci à l'appli au premier plan (autorisation « Accessibilité » requise).
enum KeySender {
    static var trusted: Bool { AXIsProcessTrusted() }

    /// Demande l'autorisation (fenêtre du système) ; rend l'état actuel.
    @discardableResult
    static func requestTrust() -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    @discardableResult
    static func send(_ hotkey: Hotkey) -> Bool {
        guard trusted else { requestTrust(); return false }
        let source = CGEventSource(stateID: .privateState)
        var flags = CGEventFlags()
        if hotkey.modifiers & Hotkey.command != 0 { flags.insert(.maskCommand) }
        if hotkey.modifiers & Hotkey.option != 0 { flags.insert(.maskAlternate) }
        if hotkey.modifiers & Hotkey.control != 0 { flags.insert(.maskControl) }
        if hotkey.modifiers & Hotkey.shift != 0 { flags.insert(.maskShift) }
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(hotkey.keyCode), keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
        return true
    }
}

/// Écriture d'un raccourci selon la disposition de clavier active.
enum KeyName {
    private static let special: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "␣", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    static func isFunctionKey(_ keyCode: Int) -> Bool { special[keyCode]?.hasPrefix("F") == true }

    static func label(_ hotkey: Hotkey) -> String {
        var out = ""
        if hotkey.modifiers & Hotkey.control != 0 { out += "⌃" }
        if hotkey.modifiers & Hotkey.option != 0 { out += "⌥" }
        if hotkey.modifiers & Hotkey.shift != 0 { out += "⇧" }
        if hotkey.modifiers & Hotkey.command != 0 { out += "⌘" }
        return out + key(hotkey.keyCode)
    }

    private static func key(_ keyCode: Int) -> String {
        if let name = special[keyCode] { return name }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "#\(keyCode)" }
        let layout = unsafeBitCast(raw, to: CFData.self) as Data
        var dead: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layout.withUnsafeBytes { bytes in
            UCKeyTranslate(bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                           UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "#\(keyCode)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}
