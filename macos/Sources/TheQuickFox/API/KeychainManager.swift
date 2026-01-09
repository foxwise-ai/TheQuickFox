//
//  KeychainManager.swift
//  TheQuickFox
//
//  Securely stores and retrieves authentication tokens using Keychain
//

import Foundation
import Security

final class KeychainManager {
    static let shared = KeychainManager()

    private let service = "com.foxwiseai.thequickfox"
    private let authTokenKey = "authToken"
    private let userOpenAIKeyKey = "userOpenAIKey"

    private init() {}

    func saveAuthToken(_ token: String) throws {
        let data = token.data(using: .utf8)!

        // Delete any existing token first
        deleteAuthToken()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: authTokenKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unableToSave
        }
    }

    func getAuthToken() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: authTokenKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let token = String(data: data, encoding: .utf8) else {
                throw KeychainError.invalidData
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unableToRetrieve
        }
    }

    func deleteAuthToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: authTokenKey
        ]

        SecItemDelete(query as CFDictionary)
    }
    
    // MARK: - User OpenAI API Key
    
    func saveUserOpenAIKey(_ key: String) throws {
        let data = key.data(using: .utf8)!
        
        // Delete any existing key first
        deleteUserOpenAIKey()
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: userOpenAIKeyKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unableToSave
        }
    }
    
    func getUserOpenAIKey() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: userOpenAIKeyKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let key = String(data: data, encoding: .utf8) else {
                throw KeychainError.invalidData
            }
            return key
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unableToRetrieve
        }
    }
    
    func deleteUserOpenAIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: userOpenAIKeyKey
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}

enum KeychainError: Error {
    case unableToSave
    case unableToRetrieve
    case invalidData
}
