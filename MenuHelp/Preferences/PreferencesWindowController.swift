import AppKit
import SwiftUI

final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    init() {
        let hostingController = NSHostingController(rootView: PreferencesView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = String(localized: "Preferências do MenuHelp")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 520, height: 590))
        window.minSize = NSSize(width: 520, height: 500)
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) não é suportado")
    }

    func showPreferences() {
        guard let window else { return }
        NSApp.activate()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}
