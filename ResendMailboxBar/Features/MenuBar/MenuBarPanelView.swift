import AppKit
import SwiftUI

struct MenuBarPanelView: View {
    @Bindable var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                if let selectedMailbox = appState.selectedMailbox {
                    mailboxSummary(selectedMailbox)
                    recentMessages
                } else {
                    ContentUnavailableView(
                        "No Mailboxes",
                        systemImage: "mail.stack",
                        description: Text("Add a Resend API key in settings to start monitoring mail.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }

                actions
            }
        }
        .padding(18)
        .frame(width: 380, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Resend Mailbox")
                        .font(.title2.bold())
                    Text(appState.selectedMailbox?.name ?? "No mailbox selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task { await appState.refreshAllMailboxes(userInitiated: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.body.weight(.semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .background(.background.opacity(0.9), in: Circle())
                .disabled(!appState.hasMailboxes || appState.isRefreshing)
            }

            Picker("Mailbox", selection: mailboxBinding) {
                if appState.mailboxes.isEmpty {
                    Text("No Mailboxes").tag(UUID?.none)
                } else {
                    ForEach(appState.mailboxes) { mailbox in
                        Text(mailbox.name).tag(UUID?.some(mailbox.id))
                    }
                }
            }
            .labelsHidden()
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))
    }

    private func mailboxSummary(_ mailbox: MailboxProfile) -> some View {
        let counts = appState.summaryCounts(for: mailbox.id)
        let unreadCount = appState.unreadReceivedCount(for: mailbox.id)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(mailbox.name, systemImage: mailbox.symbolName)
                    .font(.headline)
                    .foregroundStyle(mailbox.accent.color)
                Spacer()
                if let lastRefreshAt = appState.lastRefreshAt {
                    Text("Updated \(lastRefreshAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                statCard(title: "Received", value: "\(counts.received)", systemImage: "tray.and.arrow.down")
                statCard(title: "Sent", value: "\(counts.sent)", systemImage: "paperplane")
                statCard(title: "Unread", value: "\(unreadCount)", systemImage: "envelope")
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))
    }

    private func statCard(title: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
    }

    private var recentMessages: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent \(appState.selectedFolder.title)")
                    .font(.headline)

                Spacer()

                Picker("Folder", selection: folderBinding) {
                    ForEach(MailboxFolder.allCases) { folder in
                        Text(folder.title).tag(folder)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160)
            }

            if appState.currentRecentEmails.isEmpty {
                Text("No messages loaded yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 20)
            } else {
                ForEach(appState.currentRecentEmails) { email in
                    let isUnread = appState.selectedFolder == .received
                        && appState.isUnreadReceived(email.id, mailboxID: appState.selectedMailboxID)

                    Button {
                        openEmailFromPanel(email)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(isUnread ? Color.accentColor : Color.secondary.opacity(0.18))
                                .frame(width: 8, height: 8)
                                .padding(.top, 5)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(email.displaySubject)
                                    .font(.subheadline.weight(isUnread ? .semibold : .regular))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Text(email.displayParticipants)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.background.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                openMailboxWindowFromPanel()
            } label: {
                Label("Open Mailbox Window", systemImage: "sidebar.left")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            HStack(spacing: 10) {
                Button {
                    appState.prepareNewDraft()
                    openWindow(id: WindowID.compose)
                } label: {
                    Label("Compose", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!appState.hasMailboxes)

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
            }

            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Label("Quit Resend Mailbox", systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))
    }

    private var mailboxBinding: Binding<UUID?> {
        Binding(
            get: { appState.selectedMailboxID },
            set: { newValue in
                guard let newValue else { return }
                appState.selectMailbox(newValue)
            }
        )
    }

    private var folderBinding: Binding<MailboxFolder> {
        Binding(
            get: { appState.selectedFolder },
            set: { newValue in
                appState.selectFolder(newValue)
            }
        )
    }

    private func openEmailFromPanel(_ email: ResendEmailSummary) {
        if let mailboxID = appState.selectedMailboxID {
            appState.selectMailbox(mailboxID)
        }
        dismissMenuBarPanel()
        openWindow(id: WindowID.main)
        NSApp.activate(ignoringOtherApps: true)
        Task { await appState.selectEmail(id: email.id) }
    }

    private func openMailboxWindowFromPanel() {
        dismissMenuBarPanel()
        openWindow(id: WindowID.main)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func dismissMenuBarPanel() {
        // MenuBarExtra in `.window` style presents its content inside a private
        // NSPanel subclass whose type name contains "MenuBarExtraPanel".
        // Closing it is the most reliable way to dismiss the popunder without
        // waiting on system focus changes.
        for window in NSApp.windows {
            let typeName = String(describing: type(of: window))
            if typeName.contains("MenuBarExtraPanel") || typeName.contains("NSStatusBarWindow") {
                window.close()
            }
        }
    }
}
