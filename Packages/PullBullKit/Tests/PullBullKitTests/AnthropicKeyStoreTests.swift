import Foundation
import Security
import Testing
@testable import PullBullKit

@Suite struct AnthropicKeyStoreTests {
    @Test func keychainQueryShape() {
        let q = AnthropicKeyStore.itemQuery
        #expect(AnthropicKeyStore.service == "io.github.rustycamper.pullbull.anthropic")
        #expect(q[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(q[kSecAttrService as String] as? String == "io.github.rustycamper.pullbull.anthropic")
        #expect(q[kSecAttrAccount as String] as? String == "api-key")
        #expect(q[kSecUseDataProtectionKeychain as String] as? Bool == true)
        #expect(q[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(q[kSecAttrAccessGroup as String] == nil)
    }

    @Test func addAttributesAreDeviceOnly() throws {
        let a = AnthropicKeyStore.addAttributes(key: "sk-ant-SECRET")
        #expect(
            a[kSecAttrAccessible as String] as? String
                == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        #expect(a[kSecValueData as String] as? Data == Data("sk-ant-SECRET".utf8))
        #expect(a[kSecAttrAccount as String] as? String == "api-key")
        #expect(a[kSecUseDataProtectionKeychain as String] as? Bool == true)
        #expect(a[kSecAttrSynchronizable as String] as? Bool == false)
    }
}
