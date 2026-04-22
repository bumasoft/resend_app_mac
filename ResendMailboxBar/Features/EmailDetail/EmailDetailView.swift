import AppKit
import SwiftUI
import WebKit

struct EmailDetailView: View {
    @Bindable var appState: AppState

    @State private var previewMode: PreviewMode = .html
    @State private var rescheduleDate = Date.now.addingTimeInterval(60 * 60)
    @State private var showDetails = false
    @State private var htmlPreviewHeight: CGFloat = 420

    var body: some View {
        Group {
            if let email = appState.selectedEmailDetails {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        metaBar(email)
                        if showDetails {
                            detailsPanel(email)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        Divider()
                        previewSection(email)
                    }
                    .frame(maxWidth: 920, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .background(Color(nsColor: .windowBackgroundColor))
                .overlay {
                    if appState.isLoadingEmailDetails {
                        ProgressView()
                    }
                }
                .onAppear {
                    rescheduleDate = scheduledDate(from: email.scheduledAt) ?? rescheduleDate
                }
                .onChange(of: email.scheduledAt) { _, newValue in
                    if let date = scheduledDate(from: newValue) {
                        rescheduleDate = date
                    }
                }
                .onChange(of: email.id) { _, _ in
                    showDetails = false
                    htmlPreviewHeight = 420
                }
                .onChange(of: previewMode) { _, _ in
                    htmlPreviewHeight = 420
                }
            } else {
                ContentUnavailableView(
                    "Select an Email",
                    systemImage: "envelope.open",
                    description: Text("Choose a message from the list to preview it here.")
                )
            }
        }
    }

    private func metaBar(_ email: ResendEmailDetails) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(email.displaySubject)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                actionCluster(email)
            }

            metaLine(email)
        }
    }

    @ViewBuilder
    private func actionCluster(_ email: ResendEmailDetails) -> some View {
        let isRead = appState.isRead(email.id, mailboxID: appState.selectedMailboxID)

        HStack(spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showDetails.toggle()
                }
            } label: {
                Label(
                    "Details",
                    systemImage: showDetails ? "chevron.up" : "chevron.down"
                )
            }
            .controlSize(.small)

            if let rawURL = email.raw?.downloadURL {
                Button {
                    NSWorkspace.shared.open(rawURL)
                } label: {
                    Label("Raw", systemImage: "doc.richtext")
                }
                .controlSize(.small)
                .help("Open raw email")
            }

            if !email.attachments.orEmpty.isEmpty {
                Menu {
                    ForEach(email.attachments.orEmpty) { attachment in
                        Button(attachment.filename?.nonEmpty ?? "Attachment") {
                            Task {
                                do {
                                    let url = try await appState.resolvedAttachmentURL(for: attachment)
                                    NSWorkspace.shared.open(url)
                                } catch {
                                    appState.errorMessage = error.localizedDescription
                                }
                            }
                        }
                    }
                } label: {
                    Label("\(email.attachments.orEmpty.count)", systemImage: "paperclip")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .controlSize(.small)
                .help("Attachments")
            }

            if appState.selectedFolder == .received {
                Button(isRead ? "Mark as Unread" : "Mark as Read") {
                    appState.toggleRead(emailID: email.id, mailboxID: appState.selectedMailboxID)
                }
                .controlSize(.small)
            }

            if appState.selectedFolder == .sent {
                DatePicker(
                    "Reschedule",
                    selection: $rescheduleDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .controlSize(.small)

                Button("Update") {
                    Task { await appState.updateScheduleForSelectedEmail(to: rescheduleDate) }
                }
                .controlSize(.small)

                Button("Cancel", role: .destructive) {
                    Task { await appState.cancelSelectedEmail() }
                }
                .controlSize(.small)
                .help("Cancel send")
            }
        }
    }

    private func metaLine(_ email: ResendEmailDetails) -> some View {
        Text(metaLineText(email))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
    }

    private func metaLineText(_ email: ResendEmailDetails) -> String {
        let sender = email.from?.nonEmpty
        let recipient = email.to?.compactMap(\.nonEmpty).first
        let timestamp = email.createdAt.map(mailboxTimestampString(from:))
        let scheduled = appState.selectedFolder == .sent ? email.scheduledAt?.nonEmpty : nil

        var parts: [String] = []
        switch (sender, recipient) {
        case let (.some(s), .some(r)): parts.append("\(s) -> \(r)")
        case let (.some(s), _): parts.append(s)
        case let (_, .some(r)): parts.append(r)
        default: break
        }
        if let timestamp { parts.append(timestamp) }
        if let scheduled { parts.append("Scheduled: \(scheduled)") }
        return parts.joined(separator: " · ")
    }

    private func detailsPanel(_ email: ResendEmailDetails) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(email.participantSummary, id: \.0) { label, value in
                HStack(alignment: .top, spacing: 8) {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)
                    Text(value)
                        .font(.caption)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let headers = email.headers, !headers.isEmpty {
                DisclosureGroup("Raw headers") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(headers.keys.sorted(), id: \.self) { key in
                            HStack(alignment: .top) {
                                Text(key)
                                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 160, alignment: .leading)
                                Text(headers[key] ?? "")
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(.top, 6)
                }
                .font(.caption)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private func previewSection(_ email: ResendEmailDetails) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Preview")
                    .font(.headline)

                Spacer()

                Picker("Mode", selection: $previewMode) {
                    if email.html?.nonEmpty != nil {
                        Text("HTML").tag(PreviewMode.html)
                    }
                    if email.text?.nonEmpty != nil {
                        Text("Text").tag(PreviewMode.text)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            Group {
                switch previewMode {
                case .html where email.html?.nonEmpty != nil:
                    HTMLPreviewView(html: email.html ?? "", contentHeight: $htmlPreviewHeight)
                        .frame(height: htmlPreviewHeight)
                case .text where email.text?.nonEmpty != nil:
                    Text(email.text ?? "")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(20)
                default:
                    Text("No preview available.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.quaternary, lineWidth: 1)
            )
        }
    }

    private func scheduledDate(from value: String?) -> Date? {
        guard let value = value?.nonEmpty else { return nil }
        for formatter in ResendDateParser.allFormatters() {
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return ResendDateParser.iso8601WithFractional().date(from: value)
            ?? ResendDateParser.iso8601().date(from: value)
    }
}

private enum PreviewMode: Hashable {
    case html
    case text
}

private struct HTMLPreviewView: NSViewRepresentable {
    let html: String
    @Binding var contentHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(contentHeight: $contentHeight)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        webView.navigationDelegate = context.coordinator

        let scrollView = webView.enclosingScrollView
        scrollView?.hasVerticalScroller = false
        scrollView?.hasHorizontalScroller = false
        scrollView?.verticalScrollElasticity = .none
        scrollView?.horizontalScrollElasticity = .none

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.lastLoadedHTML = html
        let wrappedHTML = """
        <html>
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
              :root {
                color-scheme: light dark;
              }
              html, body {
                margin: 0;
                padding: 0;
                background: transparent;
                font-family: -apple-system, BlinkMacSystemFont, sans-serif;
              }
              body {
                color: #1f2937;
              }
              .mailbox-preview {
                padding: 20px;
                overflow-x: auto;
                overflow-y: hidden;
                box-sizing: border-box;
              }
              .mailbox-preview, .mailbox-preview * {
                max-width: 100%;
                box-sizing: border-box;
              }
              img, video {
                max-width: 100%;
                height: auto;
              }
              table {
                width: 100%;
                max-width: 100%;
                border-collapse: collapse;
                table-layout: auto;
                display: block;
                overflow-x: auto;
              }
              th, td {
                word-break: break-word;
              }
              pre, code {
                white-space: pre-wrap;
                overflow-wrap: anywhere;
              }
              blockquote {
                margin-left: 0;
                padding-left: 12px;
                border-left: 3px solid rgba(128, 128, 128, 0.35);
              }
            </style>
          </head>
          <body>
            <div class="mailbox-preview">\(html)</div>
          </body>
        </html>
        """
        nsView.loadHTMLString(wrappedHTML, baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var contentHeight: CGFloat
        var lastLoadedHTML: String = ""
        private var pollTimer: Timer?

        init(contentHeight: Binding<CGFloat>) {
            self._contentHeight = contentHeight
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            measure(webView)
            pollTimer?.invalidate()
            var ticks = 0
            pollTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self, weak webView] timer in
                guard let self, let webView else { timer.invalidate(); return }
                self.measure(webView)
                ticks += 1
                if ticks >= 20 { timer.invalidate() }
            }
        }

        private func measure(_ webView: WKWebView) {
            webView.evaluateJavaScript("document.documentElement.scrollHeight") { [weak self] value, _ in
                guard let self, let height = value as? CGFloat, height > 0 else { return }
                let clamped = max(120, height)
                if abs(clamped - self.contentHeight) > 1 {
                    DispatchQueue.main.async { self.contentHeight = clamped }
                }
            }
        }
    }
}

private extension Optional where Wrapped == [ResendAttachment] {
    var orEmpty: [ResendAttachment] { self ?? [] }
}
