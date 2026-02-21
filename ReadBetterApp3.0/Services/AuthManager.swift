//
//  AuthManager.swift
//  ReadBetterApp3.0
//
//  Firebase Auth manager that supports:
//  - Anonymous auth (for instant per-user bookmarks)
//  - Email/password
//  - Google sign-in
//  - Sign in with Apple
//  - Account linking (anonymous -> real provider) to preserve user data
//  - User profile persistence in Firestore (users/{uid})
//

import Foundation
import SwiftUI
import Combine
import UIKit
import Security
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import GoogleSignIn
import AuthenticationServices
import CryptoKit

@MainActor
final class AuthManager: NSObject, ObservableObject {
    enum AuthError: LocalizedError {
        case missingClientID
        case missingPresentingViewController
        case cancelled
        case missingToken
        
        var errorDescription: String? {
            switch self {
            case .missingClientID: return "Missing Firebase client ID"
            case .missingPresentingViewController: return "Could not find a presenting view controller"
            case .cancelled: return "Sign-in was cancelled"
            case .missingToken: return "Missing identity token"
            }
        }
    }
    
    @Published private(set) var user: FirebaseAuth.User?
    @Published private(set) var profile: UserProfile?
    @Published private(set) var isReady: Bool = false
    @Published var lastErrorMessage: String? = nil
    
    private let db = Firestore.firestore()
    private var authHandle: AuthStateDidChangeListenerHandle?
    private var currentAppleNonce: String?
    
    override init() {
        super.init()
        
        // First, validate any cached session before setting up the listener
        // This ensures deleted users are signed out before the app shows content
        Task { @MainActor in
            await self.validateSession()
            
            // Now set up the auth state listener
            self.authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
                guard let self else { return }
                Task { @MainActor in
                    self.user = user
                    self.isReady = true
                    if user != nil {
                        await self.refreshProfile()
                    } else {
                        self.profile = nil
                    }
                    // Notify other services about auth state change
                    NotificationCenter.default.post(name: .AuthStateDidChangeNotification, object: nil)
                }
            }
        }
        
        // Don't auto-create anonymous users - let guests browse without account
        // Account only created when they sign in or try to purchase
    }
    
    /// Validates that the current cached user still exists on Firebase backend.
    /// If the user was deleted server-side, this will sign them out locally.
    func validateSession() async {
        guard let currentUser = Auth.auth().currentUser else {
            // No user cached, nothing to validate
            return
        }
        
        do {
            // Force reload user from Firebase backend
            try await currentUser.reload()
            // User still exists, update our reference
            user = Auth.auth().currentUser
            print("✅ Session validated: user still exists on Firebase")
        } catch {
            let nsError = error as NSError
            
            // Check if the error indicates the user was deleted
            // Error codes: userNotFound (17011), userTokenExpired (17021), invalidUserToken (17017)
            let isUserDeleted = nsError.domain == AuthErrors.domain && (
                AuthErrorCode(rawValue: nsError.code) == .userNotFound ||
                AuthErrorCode(rawValue: nsError.code) == .userTokenExpired ||
                AuthErrorCode(rawValue: nsError.code) == .invalidUserToken ||
                AuthErrorCode(rawValue: nsError.code) == .userDisabled
            )
            
            if isUserDeleted {
                print("⚠️ User was deleted from Firebase - signing out locally")
                // User was deleted server-side, sign out locally
                do {
                    try Auth.auth().signOut()
                    user = nil
                    profile = nil
                } catch {
                    print("❌ Failed to sign out deleted user: \(error.localizedDescription)")
                }
            } else {
                // Some other error (network issue, etc.) - don't sign out
                print("⚠️ Session validation failed (non-fatal): \(error.localizedDescription)")
            }
        }
    }
    
    deinit {
        if let authHandle {
            Auth.auth().removeStateDidChangeListener(authHandle)
        }
    }
    
    var uid: String? { user?.uid }
    var isAnonymous: Bool { user?.isAnonymous ?? true } // No user = treat as guest
    var isSignedIn: Bool { user != nil && !(user?.isAnonymous ?? true) } // True only for real accounts
    
    var displayName: String {
        if let p = profile?.displayName,
           !p.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
            return p
        }
        if let name = user?.displayName,
           !name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
            return name
        }
        return UserProfile.defaultDisplayName(isAnonymous: isAnonymous)
    }
    
    var email: String? {
        profile?.email ?? user?.email
    }
    
    // MARK: - Session
    
    func signInAnonymouslyIfNeeded() async {
        if Auth.auth().currentUser != nil { return }
        do {
            let result = try await Auth.auth().signInAnonymously()
            user = result.user
            await refreshProfile()
        } catch {
            lastErrorMessage = "Anonymous sign-in failed: \(error.localizedDescription)"
        }
    }
    
    /// Logs out the current user completely (returns to guest state with no account)
    func signOut() async {
        do {
            // Sign out from Google Sign-In SDK (clears cached Google account)
            GIDSignIn.sharedInstance.signOut()
            
            // Sign out from Firebase Auth
            try Auth.auth().signOut()
            user = nil
            profile = nil
        } catch {
            lastErrorMessage = "Sign out failed: \(error.localizedDescription)"
        }
        // Don't create new anonymous user - user becomes a true guest
    }
    
    /// Legacy method name for compatibility
    func signOutToAnonymous() async {
        await signOut()
    }
    
    // MARK: - Email / Password
    
    func signInEmail(email: String, password: String) async throws {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        user = result.user
        await refreshProfile()
    }
    
    /// Create account or link current anonymous user to Email/Password so all bookmarks remain.
    func signUpOrLinkAnonymous(email: String, password: String, displayName: String) async throws {
        let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let current = Auth.auth().currentUser, current.isAnonymous {
            let credential = EmailAuthProvider.credential(withEmail: email, password: password)
            let result = try await current.link(with: credential)
            user = result.user
        } else {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            user = result.user
        }
        
        // Set FirebaseAuth displayName so it propagates consistently.
        if !cleanName.isEmpty {
            try await updateAuthDisplayName(cleanName)
        }
        
        await refreshProfile(preferredDisplayName: cleanName.isEmpty ? nil : cleanName)
    }
    
    // MARK: - Google
    
    func signInWithGoogle() async throws {
        guard let presentingVC = UIApplication.shared.rb_topMostViewController() else {
            throw AuthError.missingPresentingViewController
        }
        try await signInWithGoogle(presenting: presentingVC)
    }
    
    func signInWithGoogle(presenting viewController: UIViewController) async throws {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AuthError.missingClientID
        }
        
        // GoogleSignIn-iOS v9+: set configuration on the shared instance.
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        
        let signInResult = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GIDSignInResult, Error>) in
            GIDSignIn.sharedInstance.signIn(withPresenting: viewController) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let result else {
                    continuation.resume(throwing: AuthError.cancelled)
                    return
                }
                continuation.resume(returning: result)
            }
        }
        
        guard let idToken = signInResult.user.idToken?.tokenString else {
            throw AuthError.missingToken
        }
        
        let accessToken = signInResult.user.accessToken.tokenString
        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
        
        if let current = Auth.auth().currentUser, current.isAnonymous {
            // Prefer linking to preserve guest data, but fall back to sign-in if this Google
            // credential/email is already associated with another Firebase account.
            do {
                let linked = try await current.link(with: credential)
                user = linked.user
            } catch {
                let nsError = error as NSError
                let code = AuthErrorCode(rawValue: nsError.code)
                let isRecoverableConflict =
                    nsError.domain == AuthErrors.domain &&
                    (code == .credentialAlreadyInUse ||
                     code == .accountExistsWithDifferentCredential ||
                     code == .emailAlreadyInUse)
                
                if isRecoverableConflict {
                    let updatedCredential =
                        (nsError.userInfo[AuthErrors.userInfoUpdatedCredentialKey] as? AuthCredential) ?? credential
                    let signedIn = try await Auth.auth().signIn(with: updatedCredential)
                    user = signedIn.user
                } else {
                    throw error
                }
            }
        } else {
            let signedIn = try await Auth.auth().signIn(with: credential)
            user = signedIn.user
        }

        // Prefer Google's profile name over the existing anonymous placeholder ("Guest")
        let googleName = signInResult.user.profile?.name
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        if let googleName, !googleName.isEmpty {
            // If FirebaseAuth doesn't already have a display name, set it too (best UX across the app).
            let currentAuthName = (Auth.auth().currentUser?.displayName ?? "")
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if currentAuthName.isEmpty {
                try? await updateAuthDisplayName(googleName)
            }

            await refreshProfile(preferredDisplayName: googleName)
        } else {
            await refreshProfile()
        }
    }
    
    // MARK: - Apple
    
    func startSignInWithApple() {
        let nonce = Self.randomNonceString()
        currentAppleNonce = nonce
        
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
        
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }
    
    // MARK: - Profile (Firestore)
    
    func refreshProfile(preferredDisplayName: String? = nil) async {
        guard let u = Auth.auth().currentUser else {
            profile = nil
            return
        }
        
        do {
            let docRef = db.collection("users").document(u.uid)
            let snapshot = try await docRef.getDocument()
            
            if let data = snapshot.data() {
                var merged = UserProfile(uid: u.uid, data: data)
                
                // Merge in any missing fields from FirebaseAuth (email/photo).
                merged.email = merged.email ?? u.email
                merged.photoURL = merged.photoURL ?? u.photoURL?.absoluteString
                merged.isAnonymous = u.isAnonymous
                merged.providers = u.providerData.map { $0.providerID }
                
                // If we have a preferred name (from email signup or first-time Apple), use it.
                if let preferred = preferredDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !preferred.isEmpty,
                   preferred != merged.displayName {
                    merged.displayName = preferred
                } else {
                    // Otherwise, if merged name is empty and FirebaseAuth has one, adopt it.
                    let authName = (u.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if merged.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !authName.isEmpty {
                        merged.displayName = authName
                    }
                }
                
                profile = merged
                try await docRef.setData(merged.asFirestoreData(creating: false), merge: true)
                return
            }
            
            // Create profile if missing
            let authName = (u.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let name = (preferredDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? authName)
            let finalName = name.isEmpty ? UserProfile.defaultDisplayName(isAnonymous: u.isAnonymous) : name
            
            let newProfile = UserProfile(
                uid: u.uid,
                displayName: finalName,
                email: u.email,
                photoURL: u.photoURL?.absoluteString,
                isAnonymous: u.isAnonymous,
                providers: u.providerData.map { $0.providerID }
            )
            
            profile = newProfile
            try await docRef.setData(newProfile.asFirestoreData(creating: true), merge: true)
        } catch {
            // Non-fatal: app can still operate using FirebaseAuth user fields.
            lastErrorMessage = "Profile sync failed: \(error.localizedDescription)"
        }
    }
    
    func updateDisplayName(_ newName: String) async throws {
        let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        
        try await updateAuthDisplayName(clean)
        
        guard let u = Auth.auth().currentUser else { return }
        let docRef = db.collection("users").document(u.uid)
        var data: [String: Any] = [
            "displayName": clean,
            "isAnonymous": u.isAnonymous,
            "providers": u.providerData.map { $0.providerID },
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let email = u.email { data["email"] = email }
        if let photo = u.photoURL?.absoluteString { data["photoURL"] = photo }
        try await docRef.setData(data, merge: true)
        
        await refreshProfile(preferredDisplayName: clean)
    }
    
    private func updateAuthDisplayName(_ name: String) async throws {
        guard let current = Auth.auth().currentUser else { return }
        let request = current.createProfileChangeRequest()
        request.displayName = name
        try await request.commitChanges()
        try await current.reload()
        user = Auth.auth().currentUser
    }
    
    // MARK: - Nonce helpers
    
    static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
    
    static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if status != errSecSuccess {
                fatalError("Unable to generate nonce.")
            }
            
            randoms.forEach { random in
                if remaining == 0 { return }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }
        
        return result
    }
}

// MARK: - Apple Authorization Delegates

extension AuthManager: ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.rb_keyWindow ?? ASPresentationAnchor()
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
        guard let nonce = currentAppleNonce else { return }
        guard let tokenData = appleCredential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            lastErrorMessage = AuthError.missingToken.localizedDescription
            return
        }
        
        let credential = OAuthProvider.credential(providerID: .apple, idToken: idToken, rawNonce: nonce)
        
        let fullName: String? = {
            guard let name = appleCredential.fullName else { return nil }
            let given = name.givenName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let family = name.familyName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let combined = "\(given) \(family)".trimmingCharacters(in: .whitespacesAndNewlines)
            return combined.isEmpty ? nil : combined
        }()
        
        Task { @MainActor in
            do {
                if let current = Auth.auth().currentUser, current.isAnonymous {
                    // Prefer linking to preserve any guest data (bookmarks).
                    // But if this Apple credential already belongs to another account,
                    // fall back to signing in with it (treat it as "log in").
                    do {
                        let linked = try await current.link(with: credential)
                        user = linked.user
                    } catch {
                        let nsError = error as NSError
                        let isCredentialInUse =
                            nsError.domain == AuthErrors.domain &&
                            AuthErrorCode(rawValue: nsError.code) == .credentialAlreadyInUse
                        
                        if isCredentialInUse {
                            let updatedCredential =
                                (nsError.userInfo[AuthErrors.userInfoUpdatedCredentialKey] as? AuthCredential) ?? credential
                            let signedIn = try await Auth.auth().signIn(with: updatedCredential)
                            user = signedIn.user
                        } else {
                            throw error
                        }
                    }
                } else {
                    // Non-anonymous: treat as sign-in / switch account.
                    let signedIn = try await Auth.auth().signIn(with: credential)
                    user = signedIn.user
                }
                
                if let name = fullName {
                    try await updateAuthDisplayName(name)
                    await refreshProfile(preferredDisplayName: name)
                } else {
                    await refreshProfile()
                }
            } catch {
                lastErrorMessage = "Apple sign-in failed: \(error.localizedDescription)"
            }
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        lastErrorMessage = "Apple sign-in failed: \(error.localizedDescription)"
    }
}

// MARK: - UIKit helpers for SwiftUI presentation

private extension UIApplication {
    var rb_keyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
    
    func rb_topMostViewController() -> UIViewController? {
        guard let root = rb_keyWindow?.rootViewController else { return nil }
        return rb_topMost(from: root)
    }
    
    func rb_topMost(from vc: UIViewController) -> UIViewController {
        if let presented = vc.presentedViewController {
            return rb_topMost(from: presented)
        }
        if let nav = vc as? UINavigationController, let visible = nav.visibleViewController {
            return rb_topMost(from: visible)
        }
        if let tab = vc as? UITabBarController, let selected = tab.selectedViewController {
            return rb_topMost(from: selected)
        }
        return vc
    }
}


