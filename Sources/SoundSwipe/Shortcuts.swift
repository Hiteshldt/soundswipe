import AppKit
import Carbon

@MainActor
final class ShortcutManager: ObservableObject {
    @Published var error: String?
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    var perform: ((ShortcutAction) -> Void)?
    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == 0x53575045, id.id > 0, Int(id.id) <= ShortcutAction.allCases.count else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<ShortcutManager>.fromOpaque(context).takeUnretainedValue()
            let action = ShortcutAction.allCases[Int(id.id) - 1]
            Task { @MainActor in manager.perform?(action) }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func clear() { refs.forEach { UnregisterEventHotKey($0) }; refs = [] }
    func register(_ bindings: [String: ShortcutBinding]) {
        clear(); error = nil
        for (index, action) in ShortcutAction.allCases.enumerated() {
            guard let binding = bindings[action.rawValue] else { continue }
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(binding.keyCode, binding.modifiers, EventHotKeyID(signature: 0x53575045, id: UInt32(index + 1)), GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { refs.append(ref) }
            else { error = "\(action.title): shortcut unavailable. Choose another combination." }
        }
    }
    func shutdown() { clear(); if let handler { RemoveEventHandler(handler) }; handler = nil }
    static func binding(from event: NSEvent) -> ShortcutBinding? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .control, .option]).isEmpty else { return nil }
        var modifiers: UInt32 = 0; var label = ""
        if flags.contains(.control) { modifiers |= UInt32(controlKey); label += "⌃" }
        if flags.contains(.option) { modifiers |= UInt32(optionKey); label += "⌥" }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey); label += "⇧" }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey); label += "⌘" }
        let special: [UInt16: String] = [49: "Space", 36: "↩", 123: "←", 124: "→", 125: "↓", 126: "↑", 51: "⌫", 48: "⇥"]
        guard let name = special[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased(), !name.isEmpty else { return nil }
        return ShortcutBinding(keyCode: UInt32(event.keyCode), modifiers: modifiers, label: label + name)
    }
}
