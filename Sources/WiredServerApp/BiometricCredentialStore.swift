import Foundation
import LocalAuthentication
import Security

/// Stores the macOS admin password in the Keychain, protected by explicit Touch ID / Apple Watch
/// authentication at read time. Saving does not require biometric — authentication happens in load().
struct BiometricCredentialStore {
    private static let service = "fr.read-write.WiredServer3"
    private static let account = "admin-privilege-password"

    /// True if Touch ID or Apple Watch authentication is enrolled and available.
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    /// True if a credential has been saved. Does not trigger any authentication UI.
    static var hasStoredCredential: Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    /// Save password to keychain. No biometric ACL on the item — Touch ID is enforced at load time
    /// via LAContext.evaluatePolicy, which works reliably regardless of app signing.
    static func save(password: String) {
        guard let data = password.data(using: .utf8) else { return }

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemAdd(attrs as CFDictionary, nil)
    }

    /// Retrieve the stored password. Shows the Touch ID / Apple Watch sheet first.
    /// Blocks the calling thread until authentication completes.
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
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true
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
