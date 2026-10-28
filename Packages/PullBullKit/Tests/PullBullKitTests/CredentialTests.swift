import Foundation
import Security
import Testing
@testable import PullBullKit

private let expiry = Date(timeIntervalSince1970: 1_800_000_000)

private func grant(
    access: String = "ghu_SECRET", refresh: String? = "ghr_SECRET", expires: Date? = expiry
) -> TokenGrant {
    TokenGrant(
        accessToken: access, accessExpiresAt: expires, refreshToken: refresh,
        refreshExpiresAt: expires?.addingTimeInterval(86_400))
}

private func credential() -> StoredCredential {
    StoredCredential(userID: 42, login: "octocat", grant: grant())
}

@Suite struct CredentialTests {
    @Test func credentialIsRedacted() {
        let c = credential()
        var dumped = ""
        dump(c, to: &dumped)
        let mirror = Mirror(reflecting: c).children.map { "\($0.label ?? "")=\($0.value)" }.joined()
        for text in [
            String(describing: c), String(reflecting: c), "\(c)", dumped, mirror,
        ] {
            #expect(!text.contains("_SECRET"))
        }
        #expect(c.description.contains("octocat"))
        #expect(c.description == "<credential login=octocat expires=2027-01-15T08:00:00Z>")
    }

    @Test func credentialRoundTripsJSON() throws {
        let c = credential()
        let data = try JSONEncoder().encode(c)
        #expect(try JSONDecoder().decode(StoredCredential.self, from: data) == c)
    }

    @Test func refreshedKeepsIdentity() {
        let next = credential().refreshed(
            with: grant(access: "ghu_NEW", refresh: "ghr_NEW", expires: expiry.addingTimeInterval(3600)))
        #expect(next.userID == 42)
        #expect(next.login == "octocat")
        #expect(next.accessToken == "ghu_NEW")
        #expect(next.refreshToken == "ghr_NEW")
        #expect(next.accessExpiresAt == expiry.addingTimeInterval(3600))
    }

    @Test func itemQueryUsesDataProtectionKeychain() {
        let q = KeychainCredentialStore.itemQuery(service: "s", userID: 42)
        #expect(q[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(q[kSecAttrService as String] as? String == "s")
        #expect(q[kSecAttrAccount as String] as? String == "42")
        #expect(q[kSecUseDataProtectionKeychain as String] as? Bool == true)
        #expect(q[kSecAttrSynchronizable as String] as? Bool == false)
    }

    @Test func addAttributesAreDeviceOnly() throws {
        let c = credential()
        let a = try KeychainCredentialStore.addAttributes(service: "s", credential: c)
        #expect(
            a[kSecAttrAccessible as String] as? String
                == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        let data = try #require(a[kSecValueData as String] as? Data)
        #expect(try JSONDecoder().decode(StoredCredential.self, from: data) == c)
        #expect(a[kSecAttrAccessGroup as String] == nil)
        #expect(a[kSecAttrService as String] as? String == "s")
        #expect(a[kSecAttrAccount as String] as? String == "42")
    }

    @Test func statusMapping() {
        #expect(KeychainCredentialStore.error(for: -34018) == .unsignedBuild)
        #expect(KeychainCredentialStore.error(for: -25300) == .keychain(-25300))
    }

    @Test func interactionNotAllowedMapsToLocked() {
        #expect(KeychainCredentialStore.error(for: errSecInteractionNotAllowed) == .locked)
    }

    /// Runs the probe against scripted `SecItemAdd` statuses; records every query it sends.
    private func probe(addStatus: OSStatus) -> (error: CredentialStoreError?, added: [[String: Any]], deleted: [[String: Any]]) {
        var added: [[String: Any]] = []
        var deleted: [[String: Any]] = []
        do {
            try KeychainCredentialStore.checkAvailable(
                service: "s",
                add: { added.append($0 as! [String: Any]); return addStatus },
                delete: { deleted.append($0 as! [String: Any]); return errSecSuccess })
            return (nil, added, deleted)
        } catch {
            return (error as? CredentialStoreError, added, deleted)
        }
    }

    @Test func probeMissingEntitlementIsUnsigned() {
        let result = probe(addStatus: errSecMissingEntitlement)
        #expect(result.error == .unsignedBuild)
        #expect(result.added.count == 1)
        #expect(result.deleted.isEmpty)
    }

    @Test func probeSuccessDeletesTheSentinel() {
        let result = probe(addStatus: errSecSuccess)
        #expect(result.error == nil)
        #expect(result.deleted.count == 1)
    }

    @Test func probeDuplicateIsAvailableAndDeletesTheSentinel() {
        let result = probe(addStatus: errSecDuplicateItem)
        #expect(result.error == nil)
        #expect(result.deleted.count == 1)
    }

    @Test func probeOtherFailuresKeepTheirErrors() {
        #expect(probe(addStatus: errSecInteractionNotAllowed).error == .locked)
        #expect(probe(addStatus: -1).error == .keychain(-1))
        #expect(probe(addStatus: errSecItemNotFound).error == .keychain(errSecItemNotFound))
    }

    @Test func probeSentinelNeverMatchesACredential() throws {
        let result = probe(addStatus: errSecSuccess)
        let item = KeychainCredentialStore.itemQuery(service: "s", userID: 42)
        for query in result.added + result.deleted {
            #expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
            #expect(query[kSecAttrSynchronizable as String] as? Bool == false)
            #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
            #expect(query[kSecAttrAccessGroup as String] == nil)
            #expect(query[kSecAttrService as String] as? String != item[kSecAttrService as String] as? String)
            let account = query[kSecAttrAccount as String] as? String
            #expect(account != nil)
            #expect(account.flatMap(Int64.init) == nil)
        }
        let added = try #require(result.added.first)
        #expect((added[kSecValueData as String] as? Data)?.isEmpty == true)
        #expect(
            added[kSecAttrAccessible as String] as? String
                == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["PULLBULL_KEYCHAIN_TESTS"] == "1"))
    func keychainProbe() throws {
        try KeychainCredentialStore(service: "io.github.rustycamper.pullbull.github.tests").checkAvailable()
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["PULLBULL_KEYCHAIN_TESTS"] == "1"))
    func keychainRoundTrip() throws {
        let store = KeychainCredentialStore(service: "io.github.rustycamper.pullbull.github.tests")
        let c = credential()
        try? store.delete(userID: c.userID)
        try store.save(c)
        #expect(try store.load(userID: c.userID) == c)
        let next = c.refreshed(with: grant(access: "ghu_NEW", refresh: "ghr_NEW"))
        try store.save(next)
        #expect(try store.load(userID: c.userID) == next)
        try store.delete(userID: c.userID)
        #expect(try store.load(userID: c.userID) == nil)
        try store.delete(userID: c.userID)
    }

    @Test func snapshotHoldsNoTokenFields() throws {
        let snapshot = Snapshot(
            fetchedAt: expiry,
            org: OrgContext(org: "acme", viewer: "octocat", members: [], myTeams: [], repos: []),
            reviewCandidates: [], mine: [], team: [], recentlyClosed: [], boardIssues: [])
        let json = try String(decoding: JSONEncoder().encode(snapshot), as: UTF8.self).lowercased()
        #expect(!json.contains("token"))
    }
}
