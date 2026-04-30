import Foundation
import LocalAuthentication
import Security

/// Stores the macOS admin password in the Keychain, protected by a biometric access-control
/// constraint (SecAccessControlCreateWithFlags / .biometryCurrentSet) so that SecItemCopyMatching
/// itself requires Touch ID or Apple Watch — not just the UI layer.
struct BiometricCredentialStore {
    private static let service = "fr.read-write.WiredServer3"
    private static let account = "admin-privilege-password"

    /// True if Touch ID or Apple Watch authentication is enrolled and available.
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    /// True if a credential has been saved. Does not trigger any authentication UI.
    static var hasStoredCredential: Bool {
        // An LAContext with interactionNotAllowed = true causes SecItemCopyMatching to return
        // errSecInteractionNotAllowed rather than blocking/prompting when the item has a biometric ACL.
        let noUIContext = LAContext()
        noUIContext.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseAuthenticationContext as String: noUIContext
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        // errSecInteractionNotAllowed means the item exists but is ACL-gated — that's still "stored".
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    /// Save password to Keychain with a biometric ACL so that reading the item requires
    /// Touch ID / Apple Watch at the Keychain layer, not just at the UI layer.
    static func save(password: String) {
        guard let data = password.data(using: .utf8) else { return }

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        var cfError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            &cfError
        ) else { return }

        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessControl as String: access
        ]
        SecItemAdd(attrs as CFDictionary, nil)
    }

    /// Retrieve the stored password. Shows the Touch ID / Apple Watch sheet first.
    /// The already-evaluated LAContext is passed to SecItemCopyMatching via
    /// kSecUseAuthenticationContext so that the Keychain does not prompt a second time.
    /// Returns nil if the user cancels, authentication fails, or no credential is stored.
    static func load(reason: String) -> String? {
        let context = LAContext()
        var laError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &laError) else { return nil }

        var result: String?
        let semaphore = DispatchSemaphore(value: 0)
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
            defer { semaphore.signal() }
            guard success else { return }
            // Reuse the evaluated context: the Keychain skips its own auth prompt and
            // enforces biometry through the ACL set at save time.
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecUseAuthenticationContext as String: context
            ]
            var item: AnyObject?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data,
                  let password = String(data: data, encoding: .utf8) else { return }
            result = password
        }
        semaphore.wait()
        return result
    }

    /// Remove any stored credential.
    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
