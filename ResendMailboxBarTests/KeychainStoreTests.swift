import Foundation
import Testing
@testable import ResendMailboxBar

struct KeychainStoreTests {
    @Test
    func savesReadsAndDeletesAPIKeys() throws {
        let backing = InMemorySecretBacking()
        let store = KeychainStore(backing: backing)
        let mailboxID = UUID()

        try store.setAPIKey("re_secret", for: mailboxID)
        #expect(try store.apiKey(for: mailboxID) == "re_secret")

        try store.removeAPIKey(for: mailboxID)
        #expect(try store.apiKey(for: mailboxID) == nil)
    }
}
