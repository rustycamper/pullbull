import Foundation

public enum CredentialStoreError: Error, Equatable, Sendable {
    /// errSecMissingEntitlement (-34018): the data protection Keychain needs a team-signed build.
    case unsignedBuild
    /// errSecInteractionNotAllowed (-25308): the Keychain is locked.
    case locked
    case keychain(Int32)
}

public protocol CredentialStore: Sendable {
    func load(userID: Int64) throws -> StoredCredential?
    func save(_ credential: StoredCredential) throws
    /// A missing item is not an error.
    func delete(userID: Int64) throws
    /// Throws `.unsignedBuild` on an unsigned build. Never reads or changes a credential item.
    func checkAvailable() throws
}
