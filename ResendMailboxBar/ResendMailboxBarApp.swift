import AppKit
import SwiftUI

enum WindowID {
    static let main = "main-window"
    static let compose = "compose-window"
}

@main
struct ResendMailboxBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("Resend Mailbox", systemImage: appState.menuBarSymbolName) {
            MenuBarPanelView(appState: appState)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Mailbox", id: WindowID.main) {
            InboxView(appState: appState)
        }
        .defaultSize(width: 1100, height: 700)

        WindowGroup("Compose", id: WindowID.compose) {
            ComposeView(appState: appState)
        }
        .defaultSize(width: 720, height: 760)

        Settings {
            MailboxSettingsView(appState: appState)
        }
    }

    var commands: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Quit Resend Mailbox") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
