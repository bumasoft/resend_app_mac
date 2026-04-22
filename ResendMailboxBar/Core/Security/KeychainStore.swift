import Foundation
import Security

protocol SecureSecretBacking {
    func data(for account: String) throws -> Data?
    func set(_ data: Data, for account: String) throws
    func deleteValue(for account: String) throws
}

enum KeychainStoreError: LocalizedError {
    case invalidStringData
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidStringData:
            "The stored API key could not be read."
        case let .unexpectedStatus(status):
            "Keychain operation failed with status \(status)."
        }
    }
}

final class KeychainStore {
    private let backing: SecureSecretBacking

    init(backing: SecureSecretBacking = KeychainSecretBacking()) {
        self.backing = backing
    }

    func apiKey(for mailboxID: UUID) throws -> String? {
        guard let data = try backing.data(for: mailboxID.uuidString) else {
            return nil
        }
        guard let value = String(data: data, encoding: .utf8) else {
            throw KeychainStoreError.invalidStringData
        }
        return value
    }

    func setAPIKey(_ apiKey: String, for mailboxID: UUID) throws {
        try backing.set(Data(apiKey.utf8), for: mailboxID.uuidString)
    }

    func removeAPIKey(for mailboxID: UUID) throws {
        try backing.deleteValue(for: mailboxID.uuidString)
    }
}

final class InMemorySecretBacking: SecureSecretBacking {
    private var storage: [String: Data] = [:]

    func seed(_ value: String, account: String) {
        storage[account] = Data(value.utf8)
    }

    func data(for account: String) throws -> Data? {
        storage[account]
    }

    func set(_ data: Data, for account: String) throws {
        storage[account] = data
    }

    func deleteValue(for account: String) throws {
        storage.removeValue(forKey: account)
    }
}

final class KeychainSecretBacking: SecureSecretBacking {
    private let service = "com.marian.resend-mailbox-bar"

    func data(for account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            return item as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }

    func set(_ data: Data, for account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var createQuery = query
            createQuery[kSecValueData as String] = data
            createQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(createQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainStoreError.unexpectedStatus(addStatus)
            }
            return
        }

        guard updateStatus == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(updateStatus)
        }
    }

    func deleteValue(for account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }
}
