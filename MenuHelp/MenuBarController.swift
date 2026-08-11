//
//  MenuBarController.swift
//  MenuHelp
//
//  Created on 28/01/2026.
//

import AppKit
import ApplicationServices
import Carbon
import Combine
import SwiftUI

class MenuBarController: ObservableObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var clipboardHistoryWindowController: ClipboardHistoryWindowController?
    private let preferencesWindowController = PreferencesWindowController()
    private var pasteTargetApplication: NSRunningApplication?

    @Published private(set) var clipboardSelectionRequestID: UUID?

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else { return }

        let symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: 13,
            weight: .medium
        )
        if let image = NSImage(
            systemSymbolName: "switch.2",
            accessibilityDescription: "MenuHelp"
        )?.withSymbolConfiguration(symbolConfiguration) {
            let templateImage = image.copy() as? NSImage
            templateImage?.isTemplate = true
            button.image = templateImage
        }

        button.imageScaling = .scaleProportionallyDown
        button.imagePosition = .imageOnly
        button.action = #selector(togglePopover)
        button.target = self
        button.toolTip = "MenuHelp"

        popover = NSPopover()
        popover?.contentSize = NSSize(width: 390, height: 560)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(
            rootView: MainPopoverView(controller: self)
        )

        clipboardHistoryWindowController = ClipboardHistoryWindowController(
            menuBarController: self
        )
    }

    @objc func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            pasteTargetApplication = nil
            clipboardSelectionRequestID = nil
            showPopover(relativeTo: button)
        }
    }

    func openClipboardHistoryNormally() {
        openClipboardHistory(targetApplication: eligibleFrontmostApplication())
    }

    func openClipboardHistoryFromShortcut() {
        openClipboardHistory(targetApplication: eligibleFrontmostApplication())
    }

    func confirmClipboardItem(_ item: ClipboardItem) {
        guard ClipboardService.shared.copyToClipboard(item) else { return }

        DispatchQueue.main.async { [weak self] in
            self?.finishClipboardSelection()
        }
    }

    private func finishClipboardSelection() {
        guard let targetApplication = pasteTargetApplication else { return }
        pasteTargetApplication = nil
        clipboardSelectionRequestID = nil
        clipboardHistoryWindowController?.close()

        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        let canPasteAutomatically = AXIsProcessTrustedWithOptions(options)

        targetApplication.activate()

        guard canPasteAutomatically else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Self.postPasteCommand()
        }
    }

    func showPreferences() {
        popover?.performClose(nil)
        preferencesWindowController.showPreferences()
    }

    private func openClipboardHistory(targetApplication: NSRunningApplication?) {
        pasteTargetApplication = targetApplication
        clipboardSelectionRequestID = UUID()
        popover?.performClose(nil)
        clipboardHistoryWindowController?.showHistory()
    }

    private func eligibleFrontmostApplication() -> NSRunningApplication? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }

        return application
    }

    private func showPopover(relativeTo button: NSStatusBarButton) {
        guard let popover else { return }

        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        configureTransparentPopoverWindow()
        DispatchQueue.main.async { [weak self] in
            self?.configureTransparentPopoverWindow()
        }
        popover.contentViewController?.view.window?.makeKey()
    }

    private func configureTransparentPopoverWindow() {
        guard let window = popover?.contentViewController?.view.window else { return }

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    }

    private static func postPasteCommand() {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: false
              ) else {
            return
        }

        keyDown.flags = CGEventFlags.maskCommand
        keyUp.flags = CGEventFlags.maskCommand
        keyDown.post(tap: CGEventTapLocation.cghidEventTap)
        keyUp.post(tap: CGEventTapLocation.cghidEventTap)
    }
}

struct MainPopoverView: View {
    @ObservedObject var controller: MenuBarController

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear

            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    Label("MenuHelp", systemImage: "switch.2")
                        .font(.headline)

                    Spacer()

                    Button {
                        controller.showPreferences()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 34, height: 34)
                            .background(Color.primary.opacity(0.055))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Preferências")
                }
                .padding(14)
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                .padding(.horizontal, 14)
                .padding(.top, 14)

                DashboardView {
                    controller.openClipboardHistoryNormally()
                }
            }
        }
        .frame(width: 390, height: 560, alignment: .top)
        .background(Color.clear)
    }
}
