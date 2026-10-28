import Foundation
@testable import PullBullKit

final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var _items: [Int64: StoredCredential] = [:]
    private var _saved: [StoredCredential] = []
    private var _saveError: CredentialStoreError?
    private var _loadError: CredentialStoreError?
    private var _corruptUserIDs: Set<Int64> = []
    private var _probeError: CredentialStoreError?
    private var _deleteError: CredentialStoreError?

    var saveError: CredentialStoreError? {
        get { lock.withLock { _saveError } }
        set { lock.withLock { _saveError = newValue } }
    }
    var loadError: CredentialStoreError? {
        get { lock.withLock { _loadError } }
        set { lock.withLock { _loadError = newValue } }
    }
    /// What `checkAvailable` throws, like the Keychain's write probe (`.unsignedBuild` on an unsigned host).
    var probeError: CredentialStoreError? {
        get { lock.withLock { _probeError } }
        set { lock.withLock { _probeError = newValue } }
    }
    /// What `delete` throws, leaving the item in place.
    var deleteError: CredentialStoreError? {
        get { lock.withLock { _deleteError } }
        set { lock.withLock { _deleteError = newValue } }
    }
    /// Items whose stored JSON no longer decodes: `load` throws a `DecodingError` for them.
    var corruptUserIDs: Set<Int64> {
        get { lock.withLock { _corruptUserIDs } }
        set { lock.withLock { _corruptUserIDs = newValue } }
    }
    /// Every save, in order.
    var saved: [StoredCredential] { lock.withLock { _saved } }
    var items: [Int64: StoredCredential] {
        get { lock.withLock { _items } }
        set { lock.withLock { _items = newValue } }
    }

    func load(userID: Int64) throws -> StoredCredential? {
        try lock.withLock {
            if let _loadError { throw _loadError }
            if _corruptUserIDs.contains(userID) {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "corrupt item"))
            }
            return _items[userID]
        }
    }

    func save(_ credential: StoredCredential) throws {
        try lock.withLock {
            if let _saveError { throw _saveError }
            _saved.append(credential)
            _items[credential.userID] = credential
        }
    }

    func delete(userID: Int64) throws {
        try lock.withLock {
            if let _deleteError { throw _deleteError }
            _items[userID] = nil
        }
    }

    func checkAvailable() throws {
        try lock.withLock {
            if let _probeError { throw _probeError }
        }
    }
}
