//
//  AppleSignInService.swift
//  Daythread
//

import AuthenticationServices
import Observation
import Foundation

enum AppleIDCredentialState: Equatable {
    case unknown    // not yet checked on this launch
    case signedIn   // Apple confirmed the credential is valid
    case signedOut  // user explicitly signed out in-app
    case notFound   // no credential stored (fresh install or never signed in)
}

@Observable
@MainActor
final class AppleSignInService {

    var credentialState: AppleIDCredentialState = .unknown
    var errorMessage: String?

    var isLinked: Bool { credentialState == .signedIn }

    var linkedEmail: String? {
        guard credentialState == .signedIn else { return nil }
        return readFromKeychain(key: .email)
    }

    // MARK: — Launch credential check

    /// Must be called once per cold launch. Clears stale Keychain on fresh
    /// installs (Keychain persists across app deletion — Gemini gotcha #2),
    /// then re-validates the stored Apple ID with Apple's servers.
    func checkCredentialState() async {
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: "daythread.hasLaunchedBefore")
        if !hasLaunchedBefore {
            deleteFromKeychain(key: .userID)
            deleteFromKeychain(key: .email)
            UserDefaults.standard.set(true, forKey: "daythread.hasLaunchedBefore")
        }

        guard let storedUserID = readFromKeychain(key: .userID) else {
            credentialState = .notFound
            return
        }

        do {
            let state = try await ASAuthorizationAppleIDProvider()
                .credentialState(forUserID: storedUserID)
            switch state {
            case .authorized:
                credentialState = .signedIn
            case .revoked, .notFound, .transferred:
                clearKeychain()
                credentialState = .signedOut
            @unknown default:
                credentialState = .signedOut
            }
        } catch {
            // Network error — treat the stored credential as still valid rather
            // than locking the user out or leaving the UI in a permanent spinner.
            credentialState = .signedIn
        }
    }

    // MARK: — Sign-in result handling

    /// Called from the SignInWithAppleButton onCompletion closure.
    func handleAuthorizationResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential
            else { return }

            saveToKeychain(key: .userID, value: credential.user)

            // Apple only sends email and fullName on the very first sign-in.
            // Never overwrite Keychain/AppStorage with nil on subsequent sign-ins
            // (Gemini gotcha #1).
            if let email = credential.email, !email.isEmpty {
                saveToKeychain(key: .email, value: email)
            }

            if let components = credential.fullName {
                let formatted = PersonNameComponentsFormatter().string(from: components)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !formatted.isEmpty {
                    UserDefaults.standard.set(formatted, forKey: "daythread.userDisplayName")
                    NSUbiquitousKeyValueStore.default.set(formatted, forKey: "daythread.userDisplayName")
                    NSUbiquitousKeyValueStore.default.synchronize()
                }
            }

            credentialState = .signedIn

        case .failure(let error):
            let authError = error as? ASAuthorizationError
            if authError?.code != .canceled {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: — Sign-out

    func signOut() {
        clearKeychain()
        credentialState = .signedOut
    }

    // MARK: — Keychain

    private enum KeychainKey: String {
        case userID = "daythread.siwa.userID"
        case email  = "daythread.siwa.email"
    }

    private let keychainService = "com.delonsampaio.daythread"

    private func saveToKeychain(key: KeychainKey, value: String) {
        let data = Data(value.utf8)
        let deleteQuery: [CFString: Any] = [
            kSecClass:              kSecClassGenericPassword,
            kSecAttrService:        keychainService,
            kSecAttrAccount:        key.rawValue,
            kSecAttrSynchronizable: kSecAttrSynchronizableAny
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        let addItem: [CFString: Any] = [
            kSecClass:              kSecClassGenericPassword,
            kSecAttrService:        keychainService,
            kSecAttrAccount:        key.rawValue,
            kSecValueData:          data,
            kSecAttrAccessible:     kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrSynchronizable: true
        ]
        SecItemAdd(addItem as CFDictionary, nil)
    }

    private func readFromKeychain(key: KeychainKey) -> String? {
        let query: [CFString: Any] = [
            kSecClass:              kSecClassGenericPassword,
            kSecAttrService:        keychainService,
            kSecAttrAccount:        key.rawValue,
            kSecReturnData:         true,
            kSecMatchLimit:         kSecMatchLimitOne,
            kSecAttrSynchronizable: kSecAttrSynchronizableAny
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteFromKeychain(key: KeychainKey) {
        let query: [CFString: Any] = [
            kSecClass:              kSecClassGenericPassword,
            kSecAttrService:        keychainService,
            kSecAttrAccount:        key.rawValue,
            kSecAttrSynchronizable: kSecAttrSynchronizableAny
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func clearKeychain() {
        deleteFromKeychain(key: .userID)
        deleteFromKeychain(key: .email)
    }
}
