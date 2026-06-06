//
//  SignInWithAppleButton.swift
//  Daythread
//

import SwiftUI
import AuthenticationServices

/// Thin SwiftUI wrapper around the system Sign in with Apple button.
/// Reads AppleSignInService from the environment — callers pass an optional
/// onSuccess closure for view-specific reactions (e.g. syncing nameInput).
struct DaythreadSignInWithAppleButton: View {
    @Environment(AppleSignInService.self) private var auth
    @Environment(\.colorScheme) private var colorScheme
    var onSuccess: (() -> Void)? = nil

    var body: some View {
        @Bindable var auth = auth
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.fullName, .email]
            auth.errorMessage = nil
        } onCompletion: { result in
            auth.handleAuthorizationResult(result)
            if case .success = result { onSuccess?() }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
