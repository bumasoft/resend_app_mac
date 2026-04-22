import AppKit
import SwiftUI
import UserNotifications

enum WindowID {
    static let main = "main-window"
    static let compose = "compose-window"
}

@main
struct ResendMailboxBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()
    private let notificationOpenRouter = NotificationOpenRouter.shared

    var body: some Scene {
        MenuBarExtra("Resend Mailbox", systemImage: appState.menuBarSymbolName) {
            MenuBarPanelView(
                appState: appState,
                notificationOpenRouter: notificationOpenRouter
            )
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Resend Mailbox", id: WindowID.main) {
            InboxView(
                appState: appState,
                notificationOpenRouter: notificationOpenRouter
            )
        }
        .defaultSize(width: 1100, height: 700)
        .windowToolbarStyle(.unified(showsTitle: false))

        WindowGroup("New Message", id: WindowID.compose) {
            ComposeView(appState: appState)
        }
        .defaultSize(width: 720, height: 620)
        .windowToolbarStyle(.unified(showsTitle: false))
        .windowResizability(.contentMinSize)

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

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Route notification presentation through us so banners/sounds still fire
        // when the menu bar panel (or any of our windows) makes the app active.
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        guard let payload = NotificationRoutePayload(userInfo: response.notification.request.content.userInfo) else {
            return
        }

        Task { @MainActor in
            NotificationOpenRouter.shared.enqueue(payload)
        }
    }
}
