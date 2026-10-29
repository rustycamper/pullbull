import Foundation
import Security

/// The Anthropic API key, as one generic-password item in the data protection Keychain.
/// Device-only and never synchronized.
public struct AnthropicKeyStore: Sendable {
    public static let service = "io.github.rustycamper.pullbull.anthropic"
    static let account = "api-key"

    public init() {}

    static var itemQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: false,
        ]
    }

    static func addAttributes(key: String) -> [String: Any] {
        var attributes = itemQuery
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attributes[kSecValueData as String] = Data(key.utf8)
        return attributes
    }

    public func load() throws -> String? {
        var query = Self.itemQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainCredentialStore.error(for: status) }
        guard let data = result as? Data else { throw CredentialStoreError.keychain(errSecDecode) }
        return String(decoding: data, as: UTF8.self)
    }

    /// One update, then an add when the item is new.
    public func save(_ key: String) throws {
        let attributes = Self.addAttributes(key: key)
        let update: [String: Any] = [
            kSecValueData as String: attributes[kSecValueData as String]!,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(Self.itemQuery as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainCredentialStore.error(for: status) }
    }

    public func delete() throws {
        let status = SecItemDelete(Self.itemQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainCredentialStore.error(for: status)
        }
    }
}
