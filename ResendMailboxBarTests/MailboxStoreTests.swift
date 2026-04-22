import Foundation
import Testing
@testable import ResendMailboxBar

struct MailboxStoreTests {
    @Test
    func persistsMailboxProfilesAndSelection() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let store = MailboxStore(baseDirectoryURL: directory)
        let mailbox = MailboxProfile(name: "Primary", symbolName: "tray.full", accent: .purple)

        try store.saveMailbox(mailbox)
        store.selectedMailboxID = mailbox.id

        let reloaded = MailboxStore(baseDirectoryURL: directory)

        #expect(reloaded.mailboxes.count == 1)
        #expect(reloaded.mailboxes.first?.name == "Primary")
        #expect(reloaded.selectedMailboxID == mailbox.id)
    }

    @Test
    func updatesPerMailboxState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let store = MailboxStore(baseDirectoryURL: directory)
        let mailbox = MailboxProfile(name: "Stateful")
        try store.saveMailbox(mailbox)

        try store.updateState(for: mailbox.id) { state in
            state.cachedReceivedCount = 12
            state.cachedSentCount = 4
            state.lastViewedFolder = .sent
            state.lastSeenReceivedIDs = ["a", "b"]
            state.readReceivedIDs = ["a"]
            state.notifiedReceivedIDs = ["b"]
        }

        let state = store.state(for: mailbox.id)
        #expect(state.cachedReceivedCount == 12)
        #expect(state.cachedSentCount == 4)
        #expect(state.lastViewedFolder == .sent)
        #expect(state.lastSeenReceivedIDs == ["a", "b"])
        #expect(state.readReceivedIDs == ["a"])
        #expect(state.notifiedReceivedIDs == ["b"])

        let reloaded = MailboxStore(baseDirectoryURL: directory)
        let reloadedState = reloaded.state(for: mailbox.id)
        #expect(reloadedState.readReceivedIDs == ["a"])
        #expect(reloadedState.notifiedReceivedIDs == ["b"])
    }
}
