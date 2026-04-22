import AppKit
import SwiftUI

struct MailboxSettingsView: View {
    @Bindable var appState: AppState

    @State private var selectedMailboxID: UUID?
    @State private var draft = MailboxEditorDraft()
    @State private var feedbackMessage: String?
    @State private var isTesting = false
    @State private var isSaving = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedMailboxID) {
                ForEach(appState.mailboxes) { mailbox in
                    Label(mailbox.name, systemImage: mailbox.symbolName)
                        .tag(mailbox.id)
                }
            }
            .overlay {
                if appState.mailboxes.isEmpty {
                    ContentUnavailableView(
                        "No Mailboxes Yet",
                        systemImage: "mail.stack",
                        description: Text("Create a mailbox profile and store its Resend API key securely in Keychain.")
                    )
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240)
            .toolbar {
                Button {
                    startNewMailbox()
                } label: {
                    Label("Add Mailbox", systemImage: "plus")
                }
            }
        } detail: {
            Form {
                Section("Mailbox") {
                    TextField("Display name", text: $draft.name)
                    TextField("Symbol", text: $draft.symbolName)

                    Picker("Accent", selection: $draft.accent) {
                        ForEach(MailboxAccent.allCases) { accent in
                            Text(accent.rawValue.capitalized).tag(accent)
                        }
                    }
                }

                Section("API Key") {
                    SecureField("re_xxxxxxxxx", text: $draft.apiKey)
                    Text("Stored securely in Keychain and never written to plain-text settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    HStack {
                        Button {
                            Task { await runConnectionTest() }
                        } label: {
                            if isTesting {
                                ProgressView()
                            } else {
                                Label("Test Connection", systemImage: "bolt.horizontal.circle")
                            }
                        }
                        .disabled(isTesting || draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button {
                            Task { await saveDraft() }
                        } label: {
                            if isSaving {
                                ProgressView()
                            } else {
                                Label("Save Mailbox", systemImage: "checkmark.circle.fill")
                            }
                        }
                        .disabled(isSaving || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if draft.id != nil {
                            Button("Remove Mailbox", role: .destructive) {
                                removeSelectedMailbox()
                            }
                        }
                    }
                }

            }
            .formStyle(.grouped)
            .navigationTitle("Mailboxes")
            .safeAreaInset(edge: .bottom) {
                HStack {
                    if let feedbackMessage {
                        Label(feedbackMessage, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("API keys stay in Keychain and mailbox metadata stays local to this Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(role: .destructive) {
                        NSApp.terminate(nil)
                    } label: {
                        Label("Quit Resend Mailbox", systemImage: "power")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear {
            if let first = appState.mailboxes.first {
                selectedMailboxID = first.id
                loadDraft(from: first)
            } else {
                startNewMailbox()
            }
        }
        .onChange(of: selectedMailboxID) { _, newValue in
            guard let newValue, let mailbox = appState.mailboxes.first(where: { $0.id == newValue }) else { return }
            loadDraft(from: mailbox)
        }
    }

    private func startNewMailbox() {
        selectedMailboxID = nil
        feedbackMessage = nil
        draft = MailboxEditorDraft()
    }

    private func loadDraft(from mailbox: MailboxProfile) {
        let apiKey = (try? appState.keychainValue(for: mailbox.id)) ?? ""
        draft = MailboxEditorDraft(
            id: mailbox.id,
            name: mailbox.name,
            symbolName: mailbox.symbolName,
            accent: mailbox.accent,
            apiKey: apiKey
        )
        feedbackMessage = nil
    }

    private func runConnectionTest() async {
        isTesting = true
        defer { isTesting = false }

        do {
            try await appState.testConnection(apiKey: draft.apiKey)
            feedbackMessage = "Connection successful."
        } catch {
            feedbackMessage = error.localizedDescription
        }
    }

    private func saveDraft() async {
        isSaving = true
        defer { isSaving = false }

        do {
            let savedID = try appState.saveMailbox(
                id: draft.id,
                name: draft.name,
                symbolName: draft.symbolName,
                accent: draft.accent,
                apiKey: draft.apiKey
            )
            draft.id = savedID
            selectedMailboxID = savedID
            appState.selectMailbox(savedID)
            await appState.refreshMailbox(mailboxID: savedID, notifyOnNewReceived: false)
            feedbackMessage = "Mailbox saved."
        } catch {
            feedbackMessage = error.localizedDescription
        }
    }

    private func removeSelectedMailbox() {
        guard let mailboxID = draft.id else { return }

        do {
            try appState.deleteMailbox(id: mailboxID)
            if let first = appState.mailboxes.first {
                selectedMailboxID = first.id
                loadDraft(from: first)
            } else {
                startNewMailbox()
            }
            feedbackMessage = "Mailbox removed."
        } catch {
            feedbackMessage = error.localizedDescription
        }
    }
}

private struct MailboxEditorDraft {
    var id: UUID?
    var name = ""
    var symbolName = "tray.full"
    var accent: MailboxAccent = .blue
    var apiKey = ""
}
