import Carbon.HIToolbox
import Foundation

@MainActor
final class ShortcutController {
    static let displayName = "⌃⌥⌘I"
    private static let hotKeyID = EventHotKeyID(signature: 0x494E4B4F, id: 1) // INKO

    private var handler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var onPress: (() -> Void)?

    func register(onPress: @escaping () -> Void) -> OSStatus? {
        stop()
        self.onPress = onPress
        var kind = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(), { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var receivedID = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &receivedID
                )
                guard status == noErr else { return OSStatus(eventNotHandledErr) }
                return MainActor.assumeIsolated {
                    guard receivedID.signature == ShortcutController.hotKeyID.signature,
                          receivedID.id == ShortcutController.hotKeyID.id else {
                        return OSStatus(eventNotHandledErr)
                    }
                    let controller = Unmanaged<ShortcutController>.fromOpaque(context).takeUnretainedValue()
                    controller.onPress?()
                    return noErr
                }
            },
            1, &kind, Unmanaged.passUnretained(self).toOpaque(), &handler
        )

        guard handlerStatus == noErr else {
            stop()
            return handlerStatus
        }

        let registrationStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_I), UInt32(controlKey | optionKey | cmdKey),
            Self.hotKeyID, GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &hotKey
        )
        guard registrationStatus == noErr else {
            stop()
            return registrationStatus
        }
        return nil
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
        onPress = nil
    }
}
