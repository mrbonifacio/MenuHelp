import Combine
import Foundation
import IOKit.pwr_mgt

class PreventSleepService: ObservableObject {
    static let shared = PreventSleepService()

    @Published private(set) var isEnabled: Bool = false
    @Published private(set) var errorMessage: String?

    private var assertionID: IOPMAssertionID = 0
    private static let enabledDefaultsKey = "preventSleepEnabled"

    init() {
        if UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey) {
            setEnabled(true)
        }
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            enableAssertion()
        } else {
            disableAssertion()
        }
    }

    private func enableAssertion() {
        guard !isEnabled else { return }

        var newAssertionID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "MenuHelp: Prevent Sleep" as CFString,
            &newAssertionID
        )

        guard result == kIOReturnSuccess else {
            errorMessage = "Não foi possível impedir o repouso do Mac."
            return
        }

        assertionID = newAssertionID
        isEnabled = true
        errorMessage = nil
        UserDefaults.standard.set(true, forKey: Self.enabledDefaultsKey)
    }

    private func disableAssertion() {
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }

        isEnabled = false
        errorMessage = nil
        UserDefaults.standard.set(false, forKey: Self.enabledDefaultsKey)
    }
}
