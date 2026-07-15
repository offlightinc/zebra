import Foundation
import Security

protocol SlackCredentialStoring: Sendable {
    func saveUserToken(_ token: String, workspaceID: String, userID: String) throws
    func userToken(workspaceID: String, userID: String) throws -> String
    func removeUserToken(workspaceID: String, userID: String) throws
}

struct SlackKeychainCredentialStore: SlackCredentialStoring {
    private let service = "com.offlight.zebra.slack.user-token"

    func saveUserToken(_ token: String, workspaceID: String, userID: String) throws {
        let base = query(workspaceID: workspaceID, userID: userID)
        SecItemDelete(base as CFDictionary)
        var insertion = base
        insertion[kSecValueData as String] = Data(token.utf8)
        insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess else { throw SlackCapturedError.missingCredential }
    }

    func userToken(workspaceID: String, userID: String) throws -> String {
        var lookup = query(workspaceID: workspaceID, userID: userID)
        lookup[kSecReturnData as String] = true; lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
            throw SlackCapturedError.missingCredential
        }
        return token
    }

    func removeUserToken(workspaceID: String, userID: String) throws {
        SecItemDelete(query(workspaceID: workspaceID, userID: userID) as CFDictionary)
    }

    private func query(workspaceID: String, userID: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "\(workspaceID):\(userID)"]
    }
}
