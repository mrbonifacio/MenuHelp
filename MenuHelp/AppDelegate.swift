//
//  AppDelegate.swift
//  MenuHelp
//
//  Created on 28/01/2026.
//

import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    let menuBarController = MenuBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Configurar app para não aparecer no Dock (menu bar only)
        NSApp.setActivationPolicy(.accessory)

        // Carregar os serviços persistentes assim que o app abrir.
        _ = ClipboardService.shared
        _ = SystemMonitorService.shared
        _ = PreventSleepService.shared
        _ = KeyboardCleaningService.shared

        // Inicializar menu bar e popover
        menuBarController.setup()

        ShortcutService.shared.onClipboardHistoryShortcut = { [weak menuBarController] in
            menuBarController?.openClipboardHistoryFromShortcut()
        }
    }
}
