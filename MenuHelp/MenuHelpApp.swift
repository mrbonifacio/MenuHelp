//
//  MenuHelpApp.swift
//  MenuHelp
//

import AppKit

@main
enum MenuHelpApp {
    private static let appDelegate = AppDelegate()

    @MainActor
    static func main() {
        let application = NSApplication.shared
        application.delegate = appDelegate
        application.run()
    }
}
