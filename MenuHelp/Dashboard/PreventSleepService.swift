import Combine
import Foundation
import IOKit.pwr_mgt

class PreventSleepService: ObservableObject {
    static let shared = PreventSleepService()

    @Published private(set) var isEnabled: Bool = false
    @Published private(set) var errorMessage: String?

    private var systemSleepAssertionID: IOPMAssertionID = 0
    private var displaySleepAssertionID: IOPMAssertionID = 0
    private static let enabledDefaultsKey = "preventSleepEnabled"

    init() {
        if UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey) {
            setEnabled(true)
        }
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            enableAssertions()
        } else {
            disableAssertions()
        }
    }

    private func enableAssertions() {
        guard !isEnabled else { return }

        guard let newSystemSleepAssertionID = createAssertion(
            type: kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            name: "MenuHelp: Prevent System Sleep"
        ) else {
            errorMessage = String(localized: "Não foi possível impedir o repouso do Mac.")
            return
        }

        guard let newDisplaySleepAssertionID = createAssertion(
            type: kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            name: "MenuHelp: Prevent Display Sleep"
        ) else {
            IOPMAssertionRelease(newSystemSleepAssertionID)
            errorMessage = String(localized: "Não foi possível impedir o repouso do Mac.")
            return
        }

        systemSleepAssertionID = newSystemSleepAssertionID
        displaySleepAssertionID = newDisplaySleepAssertionID
        isEnabled = true
        errorMessage = nil
        UserDefaults.standard.set(true, forKey: Self.enabledDefaultsKey)
    }

    private func createAssertion(type: CFString, name: String) -> IOPMAssertionID? {
        var newAssertionID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            type,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            name as CFString,
            &newAssertionID
        )

        return result == kIOReturnSuccess ? newAssertionID : nil
    }

    private func disableAssertions() {
        releaseAssertion(&displaySleepAssertionID)
        releaseAssertion(&systemSleepAssertionID)

        isEnabled = false
        errorMessage = nil
        UserDefaults.standard.set(false, forKey: Self.enabledDefaultsKey)
    }

    private func releaseAssertion(_ assertionID: inout IOPMAssertionID) {
        guard assertionID != 0 else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
    }
}
