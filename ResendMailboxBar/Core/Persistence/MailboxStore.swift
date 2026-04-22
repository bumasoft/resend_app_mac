import Foundation

struct PersistedMailboxData: Codable {
    var mailboxes: [MailboxProfile]
    var selectedMailboxID: UUID?
    var mailboxStates: [String: MailboxLocalState]
}

final class MailboxStore {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private(set) var persistedData: PersistedMailboxData

    init(
        fileManager: FileManager = .default,
        baseDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        let rootDirectory = baseDirectoryURL ?? MailboxStore.defaultRootDirectory(using: fileManager)
        self.fileURL = rootDirectory.appendingPathComponent("mailboxes.json")

        if let loaded = Self.loadPersistedData(from: fileURL, using: decoder) {
            self.persistedData = loaded
        } else {
            self.persistedData = PersistedMailboxData(
                mailboxes: [],
                selectedMailboxID: nil,
                mailboxStates: [:]
            )
            try? createParentDirectory()
            try? save()
        }
    }

    var mailboxes: [MailboxProfile] {
        persistedData.mailboxes.sorted { $0.createdAt < $1.createdAt }
    }

    var selectedMailboxID: UUID? {
        get { persistedData.selectedMailboxID }
        set {
            persistedData.selectedMailboxID = newValue
            try? save()
        }
    }

    func saveMailbox(_ mailbox: MailboxProfile) throws {
        if let index = persistedData.mailboxes.firstIndex(where: { $0.id == mailbox.id }) {
            persistedData.mailboxes[index] = mailbox
        } else {
            persistedData.mailboxes.append(mailbox)
        }
        if persistedData.selectedMailboxID == nil {
            persistedData.selectedMailboxID = mailbox.id
        }
        try save()
    }

    func removeMailbox(id: UUID) throws {
        persistedData.mailboxes.removeAll { $0.id == id }
        persistedData.mailboxStates.removeValue(forKey: id.uuidString)
        if persistedData.selectedMailboxID == id {
            persistedData.selectedMailboxID = persistedData.mailboxes.first?.id
        }
        try save()
    }

    func state(for mailboxID: UUID) -> MailboxLocalState {
        persistedData.mailboxStates[mailboxID.uuidString] ?? MailboxLocalState()
    }

    func updateState(for mailboxID: UUID, mutate: (inout MailboxLocalState) -> Void) throws {
        var current = state(for: mailboxID)
        mutate(&current)
        persistedData.mailboxStates[mailboxID.uuidString] = current
        try save()
    }

    private func save() throws {
        try createParentDirectory()
        let data = try encoder.encode(persistedData)
        try data.write(to: fileURL, options: .atomic)
    }

    private func createParentDirectory() throws {
        let parent = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
    }

    private static func defaultRootDirectory(using fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport
            .appendingPathComponent("ResendMailboxBar", isDirectory: true)
    }

    private static func loadPersistedData(from url: URL, using decoder: JSONDecoder) -> PersistedMailboxData? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? decoder.decode(PersistedMailboxData.self, from: data)
    }
}
