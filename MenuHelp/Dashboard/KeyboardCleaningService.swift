import ApplicationServices
import Combine
import Foundation

class KeyboardCleaningService: ObservableObject {
    static let shared = KeyboardCleaningService()

    @Published private(set) var isEnabled: Bool = false
    @Published private(set) var secondsRemaining: Int = 0
    @Published private(set) var errorMessage: String?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var countdownTimer: Timer?
    private let cleaningDuration = 30
    private static let enabledDefaultsKey = "keyboardCleaningEnabled"

    init() {
        if UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey) {
            setEnabled(true)
        }
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            startCleaning()
        } else {
            stopCleaning()
        }
    }

    func reenableEventTap() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func startCleaning() {
        guard !isEnabled else { return }

        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary

        guard AXIsProcessTrustedWithOptions(options) else {
            errorMessage = String(localized: "Permita o MenuHelp em Privacidade e Segurança → Acessibilidade.")
            return
        }

        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
            // NX_SYSDEFINED (14) inclui as teclas de mídia do teclado.
            | CGEventMask(1 << 14)

        guard let newEventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: keyboardCleaningEventCallback,
            userInfo: nil
        ) else {
            errorMessage = String(localized: "Não foi possível bloquear o teclado. Verifique a permissão de Acessibilidade.")
            return
        }

        let newRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newEventTap, 0)
        eventTap = newEventTap
        runLoopSource = newRunLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), newRunLoopSource, .commonModes)
        CGEvent.tapEnable(tap: newEventTap, enable: true)

        isEnabled = true
        secondsRemaining = cleaningDuration
        errorMessage = nil
        UserDefaults.standard.set(true, forKey: Self.enabledDefaultsKey)
        startCountdown()
    }

    private func startCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }

            secondsRemaining -= 1
            if secondsRemaining <= 0 {
                stopCleaning()
            }
        }

        if let countdownTimer {
            RunLoop.current.add(countdownTimer, forMode: .common)
        }
    }

    private func stopCleaning() {
        countdownTimer?.invalidate()
        countdownTimer = nil

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        isEnabled = false
        secondsRemaining = 0
        UserDefaults.standard.set(false, forKey: Self.enabledDefaultsKey)
    }
}

private func keyboardCleaningEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        Task { @MainActor in
            KeyboardCleaningService.shared.reenableEventTap()
        }
        return Unmanaged.passUnretained(event)
    }

    return nil
}
