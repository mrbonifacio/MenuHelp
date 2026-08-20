import AppKit
import SwiftUI

final class ClipboardHistoryWindowController: NSWindowController, NSWindowDelegate {
    init(menuBarController: MenuBarController) {
        let rootView = ClipboardHistoryWindowView(controller: menuBarController)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = String(localized: "Histórico do Clipboard")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 520, height: 600))
        window.minSize = NSSize(width: 400, height: 420)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.center()

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) não é suportado")
    }

    func showHistory() {
        guard let window else { return }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

private struct ClipboardHistoryWindowView: View {
    @ObservedObject var controller: MenuBarController

    var body: some View {
        ClipboardHistoryView(
            selectionRequestID: controller.clipboardSelectionRequestID,
            onConfirm: controller.confirmClipboardItem
        )
        .frame(minWidth: 400, minHeight: 420)
    }
}
