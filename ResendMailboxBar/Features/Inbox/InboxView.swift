import AppKit
import SwiftUI

struct InboxView: View {
    @Bindable var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 12) {
                sidebarHeader
                emailList
            }
            .padding(16)
            .navigationTitle(mailboxWindowTitle)
            .navigationSplitViewColumnWidth(min: 310, ideal: 360, max: 430)
        } detail: {
            EmailDetailView(appState: appState)
                .navigationSplitViewColumnWidth(min: 640, ideal: 860)
        }
        .navigationSplitViewStyle(.balanced)
        .background(WindowTitleUpdater(title: mailboxWindowTitle))
        .frame(minWidth: 1120, minHeight: 720)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(mailboxWindowTitle)
                    .font(.headline)
                    .lineLimit(1)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    appState.prepareNewDraft()
                    openWindow(id: WindowID.compose)
                } label: {
                    Label("Compose", systemImage: "square.and.pencil")
                }
                .disabled(!appState.hasMailboxes)

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                appState.errorMessage = nil
            }
        } message: {
            Text(appState.errorMessage ?? "Unknown error")
        }
        .task {
            if appState.hasMailboxes, appState.emailSummaries.isEmpty {
                await appState.refreshAllMailboxes(userInitiated: false)
            }
        }
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(mailboxWindowTitle)
                        .font(.title3.weight(.semibold))
                    Text(mailboxHeaderSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task { await appState.refreshAllMailboxes(userInitiated: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.body.weight(.semibold))
                        .padding(8)
                }
                .buttonStyle(.plain)
                .background(.quaternary.opacity(0.75), in: Circle())
                .help("Refresh mailbox")
                .disabled(!appState.hasMailboxes || appState.isRefreshing)
            }

            mailboxPicker

            Picker("Folder", selection: folderBinding) {
                ForEach(MailboxFolder.allCases) { folder in
                    Text(folder.title).tag(folder)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if let mailbox = appState.selectedMailbox {
                let counts = appState.summaryCounts(for: mailbox.id)
                HStack(spacing: 10) {
                    sidebarStat(title: "Received", value: counts.received, systemImage: "tray.and.arrow.down")
                    sidebarStat(title: "Sent", value: counts.sent, systemImage: "paperplane")
                }
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 18))
    }

    private var mailboxPicker: some View {
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
        .frame(maxWidth: .infinity)
    }

    private var emailList: some View {
        List(selection: selectedEmailBinding) {
            if appState.emailSummaries.isEmpty {
                ContentUnavailableView(
                    appState.hasMailboxes ? "No Emails Yet" : "No Mailboxes Configured",
                    systemImage: appState.hasMailboxes ? "tray" : "mail.stack",
                    description: Text(
                        appState.hasMailboxes
                            ? "Refresh the selected mailbox or switch folders."
                            : "Open settings to add a Resend mailbox."
                    )
                )
                .listRowSeparator(.hidden)
            } else {
                ForEach(appState.emailSummaries) { email in
                    EmailRowView(
                        email: email,
                        isUnread: appState.selectedFolder == .received
                            && appState.isUnreadReceived(email.id, mailboxID: appState.selectedMailboxID)
                    )
                    .tag(email.id)
                    .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                    .contextMenu {
                        if appState.selectedFolder == .received {
                            let isRead = appState.isRead(email.id, mailboxID: appState.selectedMailboxID)
                            Button(isRead ? "Mark as Unread" : "Mark as Read") {
                                appState.toggleRead(emailID: email.id, mailboxID: appState.selectedMailboxID)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(.clear)
        .overlay(alignment: .topTrailing) {
            if appState.isRefreshing {
                ProgressView()
                    .padding(12)
            }
        }
    }

    private func sidebarStat(title: String, value: Int, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.headline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 14))
    }

    private var mailboxWindowTitle: String {
        appState.selectedMailbox?.name ?? "Resend Mailbox"
    }

    private var mailboxHeaderSubtitle: String {
        if appState.selectedMailbox == nil {
            return "Choose a mailbox"
        }
        return appState.selectedFolder.title
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

    private var selectedEmailBinding: Binding<String?> {
        Binding(
            get: { appState.selectedEmailID },
            set: { newValue in
                Task { await appState.selectEmail(id: newValue) }
            }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { appState.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    appState.errorMessage = nil
                }
            }
        )
    }
}

private struct WindowTitleUpdater: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        updateWindowTitle(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        updateWindowTitle(for: nsView)
    }

    private func updateWindowTitle(for view: NSView) {
        DispatchQueue.main.async {
            view.window?.title = title
        }
    }
}

private struct EmailRowView: View {
    let email: ResendEmailSummary
    let isUnread: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(isUnread ? Color.accentColor : Color.secondary.opacity(0.15))
                .frame(width: 9, height: 9)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    Text(email.displaySubject)
                        .font(.headline.weight(isUnread ? .semibold : .regular))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 8)

                    Text(email.displayTimestamp)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                }

                Text(email.displayParticipants)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let event = email.lastEvent?.nonEmpty {
                    Text(event.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary.opacity(0.8), in: Capsule())
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(isUnread ? 0.5 : 0.35), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.quaternary.opacity(isUnread ? 0.6 : 0.45), lineWidth: 1)
        )
    }
}
