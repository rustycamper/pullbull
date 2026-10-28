import Foundation
import Security

/// One generic-password item per account in the data protection Keychain, holding the JSON of a
/// `StoredCredential`. Device-only and never synchronized.
public struct KeychainCredentialStore: CredentialStore {
    public static let defaultService = "io.github.rustycamper.pullbull.github"

    private let service: String

    public init(service: String = KeychainCredentialStore.defaultService) {
        self.service = service
    }

    static func itemQuery(service: String, userID: Int64) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: String(userID),
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: false,
        ]
    }

    static func addAttributes(service: String, credential: StoredCredential) throws -> [String: Any] {
        var attributes = itemQuery(service: service, userID: credential.userID)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attributes[kSecValueData as String] = try JSONEncoder().encode(credential)
        return attributes
    }

    static func error(for status: OSStatus) -> CredentialStoreError {
        switch status {
        case errSecMissingEntitlement: .unsignedBuild
        case errSecInteractionNotAllowed: .locked
        default: .keychain(status)
        }
    }

    public func load(userID: Int64) throws -> StoredCredential? {
        var query = Self.itemQuery(service: service, userID: userID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Self.error(for: status) }
        guard let data = result as? Data else { throw CredentialStoreError.keychain(errSecDecode) }
        return try JSONDecoder().decode(StoredCredential.self, from: data)
    }

    /// One update, then an add when the item is new, so a rotated pair is never half-saved.
    public func save(_ credential: StoredCredential) throws {
        let attributes = try Self.addAttributes(service: service, credential: credential)
        let update: [String: Any] = [
            kSecValueData as String: attributes[kSecValueData as String]!,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let query = Self.itemQuery(service: service, userID: credential.userID)
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Self.error(for: status) }
    }

    public func delete(userID: Int64) throws {
        let status = SecItemDelete(Self.itemQuery(service: service, userID: userID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Self.error(for: status) }
    }

    /// Adds then deletes a sentinel item: on an unsigned build reads only report errSecItemNotFound,
    /// but a write fails with errSecMissingEntitlement.
    public func checkAvailable() throws {
        try Self.checkAvailable(service: service, add: { SecItemAdd($0, nil) }, delete: { SecItemDelete($0) })
    }

    /// The sentinel lives under its own service with a non-numeric account, so it can never match a
    /// credential item (whose account is a user ID), and holds no data.
    static func probeQuery(service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service + ".availability-probe",
            kSecAttrAccount as String: "availability-probe",
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: false,
        ]
    }

    /// `errSecMissingEntitlement` becomes `.unsignedBuild`; a sentinel left by an earlier probe
    /// (`errSecDuplicateItem`) still proves the Keychain writable. Other failures map as usual.
    static func checkAvailable(
        service: String, add: (CFDictionary) -> OSStatus, delete: (CFDictionary) -> OSStatus
    ) throws {
        var attributes = probeQuery(service: service)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attributes[kSecValueData as String] = Data()
        let status = add(attributes as CFDictionary)
        guard status == errSecSuccess || status == errSecDuplicateItem else { throw error(for: status) }
        _ = delete(probeQuery(service: service) as CFDictionary)
    }
}
