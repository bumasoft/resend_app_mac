import SwiftUI

struct ComposeView: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                composeHeader

                Form {
                    Section("Envelope") {
                        TextField("From", text: $appState.composeDraft.from)
                        TextField("To", text: $appState.composeDraft.to, prompt: Text("Comma-separated recipients"))
                        TextField("Cc", text: $appState.composeDraft.cc)
                        TextField("Bcc", text: $appState.composeDraft.bcc)
                        TextField("Reply-To", text: $appState.composeDraft.replyTo)
                        TextField("Subject", text: $appState.composeDraft.subject)
                    }

                    Section("Schedule") {
                        Toggle("Send later", isOn: $appState.composeDraft.scheduledAtEnabled)
                        if appState.composeDraft.scheduledAtEnabled {
                            DatePicker(
                                "Scheduled At",
                                selection: $appState.composeDraft.scheduledAt,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                        }
                    }

                    Section("HTML") {
                        TextEditor(text: $appState.composeDraft.htmlBody)
                            .font(.body.monospaced())
                            .frame(minHeight: 220)
                    }

                    Section("Text") {
                        TextEditor(text: $appState.composeDraft.textBody)
                            .font(.body.monospaced())
                            .frame(minHeight: 150)
                    }
                }
                .formStyle(.grouped)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 640, minHeight: 720)
        .toolbar {
            ToolbarItemGroup {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }

                Spacer()

                Button {
                    Task {
                        let didSend = await appState.sendCurrentDraft()
                        if didSend {
                            dismiss()
                        }
                    }
                } label: {
                    if appState.isSending {
                        ProgressView()
                    } else {
                        Label("Send", systemImage: "paperplane.fill")
                    }
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(appState.isSending || !appState.hasMailboxes)
            }
        }
        .navigationTitle("Compose")
    }

    private var composeHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Compose")
                .font(.largeTitle.bold())
            Text(appState.selectedMailbox?.name ?? "No mailbox selected")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Send a quick message, or schedule it for later delivery through the currently selected Resend mailbox.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 20))
    }
}
