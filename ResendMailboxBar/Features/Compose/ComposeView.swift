import SwiftUI

private let composeFieldLabelWidth: CGFloat = 64

struct ComposeView: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var showsExpandedHeaders = false
    @State private var showsPlainText = false
    @State private var showsScheduleSheet = false
    @State private var pendingScheduleDate = Date.now.addingTimeInterval(60 * 60)

    var body: some View {
        VStack(spacing: 0) {
            composeHeaders
            Divider()
            bodyEditor
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 620, minHeight: 560)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                sendMenu
            }
        }
        .navigationTitle(windowTitle)
        .sheet(isPresented: $showsScheduleSheet) {
            scheduleSheet
        }
        .animation(.snappy(duration: 0.22), value: showsExpandedHeaders)
        .animation(.snappy(duration: 0.22), value: showsPlainText)
        .onAppear(perform: syncDraftState)
    }

    private var composeHeaders: some View {
        VStack(spacing: 0) {
            ComposeFieldRow(label: "From", text: $appState.composeDraft.from, prompt: "Sender address") {
                if let mailboxName = appState.selectedMailbox?.name, !mailboxName.isEmpty {
                    Text(mailboxName)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Divider()

            ComposeFieldRow(label: "To", text: $appState.composeDraft.to, prompt: "Comma-separated recipients") {
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        showsExpandedHeaders.toggle()
                    }
                } label: {
                    Image(systemName: showsExpandedHeaders ? "chevron.up.circle.fill" : "chevron.down.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(showsExpandedHeaders ? "Hide Cc, Bcc, and Reply-To" : "Show Cc, Bcc, and Reply-To")
            }

            if showsExpandedHeaders {
                Divider()
                ComposeFieldRow(label: "Cc", text: $appState.composeDraft.cc, prompt: "Copy recipients") {
                    EmptyView()
                }

                Divider()
                ComposeFieldRow(label: "Bcc", text: $appState.composeDraft.bcc, prompt: "Blind copy recipients") {
                    EmptyView()
                }

                Divider()
                ComposeFieldRow(label: "Reply-To", text: $appState.composeDraft.replyTo, prompt: "Optional reply-to address") {
                    EmptyView()
                }
            }

            Divider()

            ComposeFieldRow(label: "Subject", text: $appState.composeDraft.subject, prompt: "Subject") {
                EmptyView()
            }

            if appState.composeDraft.scheduledAtEnabled {
                Divider()
                scheduledPill
            }
        }
    }

    private var scheduledPill: some View {
        HStack(spacing: 8) {
            Color.clear
                .frame(width: composeFieldLabelWidth)

            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)

                Text("Scheduled for \(scheduledDateText)")
                    .font(.subheadline)

                Button {
                    appState.composeDraft.scheduledAtEnabled = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear schedule")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.75), in: Capsule())

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var bodyEditor: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $appState.composeDraft.htmlBody)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if appState.composeDraft.htmlBody.isEmpty {
                    Text("Write your message...")
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 18)
                        .padding(.top, 18)
                        .allowsHitTesting(false)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showsPlainText {
                Divider()

                HStack {
                    Text("Plain-Text Alternative")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Remove") {
                        appState.composeDraft.textBody = ""
                        showsPlainText = false
                    }
                    .buttonStyle(.link)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(Color(nsColor: .windowBackgroundColor))

                Divider()

                TextEditor(text: $appState.composeDraft.textBody)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .background(Color(nsColor: .controlBackgroundColor))
            } else if appState.composeDraft.textBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Divider()

                HStack {
                    Button("Add plain-text alternative") {
                        withAnimation(.snappy(duration: 0.22)) {
                            showsPlainText = true
                        }
                    }
                    .buttonStyle(.link)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
    }

    private var sendMenu: some View {
        Menu {
            Button("Send Later...") {
                presentScheduleSheet()
            }

            if appState.composeDraft.scheduledAtEnabled {
                Button("Clear Schedule") {
                    appState.composeDraft.scheduledAtEnabled = false
                }
            }
        } label: {
            if appState.isSending {
                ProgressView()
                    .controlSize(.small)
                    .frame(minWidth: 70)
            } else {
                Label(appState.composeDraft.scheduledAtEnabled ? "Send Later" : "Send", systemImage: "paperplane.fill")
            }
        } primaryAction: {
            sendCurrentDraft()
        }
        .menuStyle(.borderlessButton)
        .keyboardShortcut(.return, modifiers: [.command])
        .disabled(appState.isSending || !appState.hasMailboxes)
    }

    private var scheduleSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Send Later")
                .font(.headline)

            DatePicker("Date", selection: $pendingScheduleDate, displayedComponents: [.date])
                .datePickerStyle(.graphical)

            DatePicker("Time", selection: $pendingScheduleDate, displayedComponents: [.hourAndMinute])

            HStack {
                Spacer()

                Button("Cancel") {
                    showsScheduleSheet = false
                }

                Button("Schedule") {
                    appState.composeDraft.scheduledAt = pendingScheduleDate
                    appState.composeDraft.scheduledAtEnabled = true
                    showsScheduleSheet = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private var windowTitle: String {
        let trimmedSubject = appState.composeDraft.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedSubject.isEmpty ? "New Message" : trimmedSubject
    }

    private var scheduledDateText: String {
        appState.composeDraft.scheduledAt.formatted(
            Date.FormatStyle()
                .weekday(.abbreviated)
                .day()
                .month(.abbreviated)
                .hour(.defaultDigits(amPM: .abbreviated))
                .minute()
        )
    }

    private func syncDraftState() {
        showsExpandedHeaders = hasExpandedHeaderContent
        showsPlainText = !appState.composeDraft.textBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if appState.composeDraft.scheduledAtEnabled {
            pendingScheduleDate = appState.composeDraft.scheduledAt
        }
    }

    private func presentScheduleSheet() {
        pendingScheduleDate = appState.composeDraft.scheduledAtEnabled
            ? appState.composeDraft.scheduledAt
            : Date.now.addingTimeInterval(60 * 60)
        showsScheduleSheet = true
    }

    private func sendCurrentDraft() {
        Task {
            let didSend = await appState.sendCurrentDraft()
            if didSend {
                dismiss()
            }
        }
    }

    private var hasExpandedHeaderContent: Bool {
        !appState.composeDraft.cc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !appState.composeDraft.bcc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !appState.composeDraft.replyTo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct ComposeFieldRow<Trailing: View>: View {
    let label: String
    @Binding var text: String
    let prompt: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: composeFieldLabelWidth, alignment: .trailing)

            TextField("", text: $text, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .font(.system(size: 14))

            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
