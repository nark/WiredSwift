import Foundation
import LocalAuthentication
import Security

/// Stores the macOS admin password in the Keychain protected by biometric authentication.
/// Reading the item triggers a Touch ID / Apple Watch sheet automatically.
struct BiometricCredentialStore {
    private static let service = "fr.read-write.WiredServer3"
    private static let account = "admin-privilege-password"

    /// True if Touch ID or Apple Watch authentication is enrolled and available.
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    /// True if a credential has been saved, without triggering any authentication UI.
    static var hasStoredCredential: Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseAuthenticationContext as String: context
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        // errSecInteractionNotAllowed → item exists but needs biometric; errSecSuccess → readable without
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    /// Save password. Access to the stored item requires biometric auth.
    /// Invalidated automatically when enrolled fingerprints change (.biometryCurrentSet).
    static func save(password: String) {
        guard let data = password.data(using: .utf8) else { return }
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
        SecItemDelete(attrs as CFDictionary)
        SecItemAdd(attrs as CFDictionary, nil)
    }

    /// Retrieve the stored password. Triggers the Touch ID / Apple Watch UI.
    /// Returns nil if the user cancels or no credential is stored.
    static func load(reason: String) -> String? {
        let context = LAContext()
        context.localizedReason = reason
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else { return nil }
        return password
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
