import AppKit
import SwiftUI

final class TranscriptionWindowController: NSWindowController {
    init() {
        let hostingController = NSHostingController(rootView: TranscriptionView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = String(localized: "Transcrição de áudio")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 640, height: 560))
        window.contentMinSize = NSSize(width: 520, height: 440)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) não é suportado")
    }

    func showTranscription() {
        guard let window else { return }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
