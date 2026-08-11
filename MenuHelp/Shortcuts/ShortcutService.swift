import Carbon
import Combine
import Foundation

class ShortcutService: ObservableObject {
    static let shared = ShortcutService()

    @Published private(set) var areAllShortcutsEnabled: Bool
    @Published private(set) var isClipboardHistoryShortcutEnabled: Bool
    @Published private(set) var registrationError: String?

    var onClipboardHistoryShortcut: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    private static let allShortcutsDefaultsKey = "allShortcutsEnabled"
    private static let clipboardShortcutDefaultsKey = "clipboardHistoryShortcutEnabled"
    private static let hotKeyID = EventHotKeyID(
        signature: OSType(0x4D_48_53_43), // MHSC
        id: 1
    )

    private init() {
        areAllShortcutsEnabled = Self.defaultEnabledValue(forKey: Self.allShortcutsDefaultsKey)
        isClipboardHistoryShortcutEnabled = Self.defaultEnabledValue(
            forKey: Self.clipboardShortcutDefaultsKey
        )

        installEventHandler()
        updateRegistration()
    }

    deinit {
        unregisterClipboardHistoryShortcut()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func setAllShortcutsEnabled(_ enabled: Bool) {
        guard enabled != areAllShortcutsEnabled else { return }
        areAllShortcutsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.allShortcutsDefaultsKey)
        updateRegistration()
    }

    func setClipboardHistoryShortcutEnabled(_ enabled: Bool) {
        guard enabled != isClipboardHistoryShortcutEnabled else { return }
        isClipboardHistoryShortcutEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.clipboardShortcutDefaultsKey)
        updateRegistration()
    }

    func handleRegisteredHotKey() {
        guard areAllShortcutsEnabled,
              isClipboardHistoryShortcutEnabled else {
            return
        }

        onClipboardHistoryShortcut?()
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            menuHelpHotKeyEventHandler,
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )

        if status != noErr {
            registrationError = "Não foi possível inicializar os atalhos do teclado."
        }
    }

    private func updateRegistration() {
        unregisterClipboardHistoryShortcut()

        guard eventHandlerRef != nil else {
            if registrationError == nil {
                registrationError = "Não foi possível inicializar os atalhos do teclado."
            }
            return
        }

        registrationError = nil

        guard areAllShortcutsEnabled,
              isClipboardHistoryShortcutEnabled else {
            return
        }

        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            UInt32(cmdKey | shiftKey),
            Self.hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            hotKeyRef = nil
            registrationError = status == eventHotKeyExistsErr
                ? "⇧⌘V já está sendo usado por outro aplicativo."
                : "Não foi possível ativar o atalho ⇧⌘V."
            return
        }
    }

    private func unregisterClipboardHistoryShortcut() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private static func defaultEnabledValue(forKey key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil
            ? true
            : UserDefaults.standard.bool(forKey: key)
    }
}

private func menuHelpHotKeyEventHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }

    let service = Unmanaged<ShortcutService>
        .fromOpaque(userData)
        .takeUnretainedValue()

    Task { @MainActor in
        service.handleRegisteredHotKey()
    }

    return noErr
}
