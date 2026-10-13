import SwiftUI
import AuthenticationServices
import CryptoKit

/// Rork Auth state holder: Apple sign-in via web OAuth (ASWebAuthenticationSession),
/// tokens in the Keychain, automatic refresh on launch.
@Observable
final class AuthManager {
    var user: User?
    var isLoading = true
    var isSigningIn = false
    var showError = false
    var errorMessage = ""

    private let authURL = Config.EXPO_PUBLIC_RORK_AUTH_URL
    private let appKey = Config.EXPO_PUBLIC_RORK_APP_KEY
    private let projectID = Config.EXPO_PUBLIC_PROJECT_ID
    private var codeVerifier: String?
    private var webAuthSession: ASWebAuthenticationSession?

    // Injected by Rork into UserDefaults at install time on the iOS Simulator
    // only. Tells the backend which developer's browser tab should receive the
    // OAuth popup. Absent on real devices — the flow then always resolves to
    // ASWebAuthenticationSession in-app. Computed (not cached) so a tap before
    // the simctl write lands still picks the value up.
    private var developerHint: String? {
        UserDefaults.standard.string(forKey: "RORK_DEVELOPER_HINT")
    }

    struct User: Codable {
        let id: String
        let email: String
        let name: String?
        let picture: String?
    }

    init() {
        Task { await checkAuth() }
    }

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private var authEnv: String {
        #if targetEnvironment(simulator)
        return "simulator"
        #else
        return "native"
        #endif
    }

    /// Decode the JWT payload to extract user info and check expiration.
    /// We trust the token we stored locally — signature was verified by Rork when issued.
    private func userFromToken(_ token: String) -> User? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }

        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }

        guard let data = Data(base64Encoded: base64) else { return nil }

        struct JWTPayload: Codable {
            let sub: String
            let email: String?
            let name: String?
            let picture: String?
            let exp: TimeInterval?
        }

        guard let payload = try? JSONDecoder().decode(JWTPayload.self, from: data) else { return nil }

        if let exp = payload.exp, Date(timeIntervalSince1970: exp) < Date() {
            return nil
        }

        return User(id: payload.sub, email: payload.email ?? "", name: payload.name, picture: payload.picture)
    }

    /// Read refresh token from UserDefaults (simulator-injected) first, then Keychain.
    private func getRefreshToken() -> String? {
        #if targetEnvironment(simulator)
        if let ud = UserDefaults.standard.string(forKey: "RORK_AUTH_REFRESH_TOKEN") {
            return ud
        }
        #endif
        return KeychainHelper.get("refresh_token")
    }

    @MainActor
    func checkAuth() async {
        defer { isLoading = false }

        if let accessToken = KeychainHelper.get("access_token"),
           let user = userFromToken(accessToken) {
            self.user = user
            return
        }

        if getRefreshToken() != nil {
            await refreshToken()
        }
    }

    @MainActor
    func signIn(provider: String) async {
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            let verifier = generateCodeVerifier()
            let challenge = generateCodeChallenge(from: verifier)
            codeVerifier = verifier

            guard let url = URL(string: "\(authURL)/oauth/initiate") else {
                setError("Ungültige Adresse")
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var initiateBody: [String: String] = [
                "app_key": appKey,
                "provider": provider,
                "code_challenge": challenge,
                "target": "swift",
                "env": authEnv,
            ]
            if authEnv == "simulator", let hint = developerHint {
                initiateBody["developer_hint"] = hint
            }
            request.httpBody = try JSONEncoder().encode(initiateBody)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                    setError(errorResponse.error)
                } else {
                    setError("Anmeldung fehlgeschlagen (\(statusCode))")
                }
                return
            }
            let initiateResponse = try JSONDecoder().decode(InitiateResponse.self, from: data)

            let code: String
            if initiateResponse.flow == "popup" {
                // OAuth runs in the developer's host browser; poll for the code.
                do {
                    code = try await pollForCode(state: initiateResponse.state)
                } catch AuthError.cancelledByUser {
                    // "Use simulator instead" was pressed — fall back to in-app.
                    code = try await runWebAuthSession(authURL: initiateResponse.auth_url)
                }
            } else {
                code = try await runWebAuthSession(authURL: initiateResponse.auth_url)
            }

            await exchangeCode(code)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return
        } catch {
            setError("Anmeldung fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    /// Poll /oauth/poll-code until the host-browser popup completes the OAuth
    /// callback or the 5-min state TTL elapses.
    private func pollForCode(state: String) async throws -> String {
        guard let url = URL(string: "\(authURL)/oauth/poll-code") else {
            throw AuthError.invalidURL
        }

        let deadline = Date().addingTimeInterval(5 * 60)
        while Date() < deadline {
            try await Task.sleep(for: .milliseconds(1500))

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["app_key": appKey, "state": state])

            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { continue }

            guard let pollResponse = try? JSONDecoder().decode(PollCodeResponse.self, from: data) else { continue }

            if pollResponse.status == "cancelled" {
                throw AuthError.cancelledByUser
            }

            if pollResponse.status == "ready", let code = pollResponse.code {
                return code
            }
        }

        throw AuthError.popupTimeout
    }

    /// Open the OAuth authorize URL inside ASWebAuthenticationSession and
    /// resolve to the auth code captured from the rork-{projectID}:// callback.
    private func runWebAuthSession(authURL authURLString: String) async throws -> String {
        let callbackScheme = "rork-\(projectID)"
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            guard let url = URL(string: authURLString) else {
                continuation.resume(throwing: AuthError.invalidURL)
                return
            }

            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { [weak self] callbackURL, error in
                self?.webAuthSession = nil

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let url = callbackURL,
                      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: AuthError.noCode)
                    return
                }

                continuation.resume(returning: code)
            }

            self.webAuthSession = session
            session.presentationContextProvider = WebAuthPresentationContext.shared
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    @MainActor
    private func exchangeCode(_ code: String) async {
        guard let verifier = codeVerifier else { return }
        codeVerifier = nil

        guard let url = URL(string: "\(authURL)/oauth/token") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode([
            "app_key": appKey,
            "code": code,
            "code_verifier": verifier,
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                    setError(errorResponse.error)
                } else {
                    setError("Anmeldung fehlgeschlagen (\(statusCode))")
                }
                return
            }
            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

            KeychainHelper.set("access_token", value: tokenResponse.access_token)
            KeychainHelper.set("refresh_token", value: tokenResponse.refresh_token)

            user = tokenResponse.user
        } catch {
            setError("Anmeldung fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func refreshToken() async {
        guard let storedRefreshToken = getRefreshToken() else {
            user = nil
            return
        }

        guard let url = URL(string: "\(authURL)/oauth/refresh") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode([
            "app_key": appKey,
            "refresh_token": storedRefreshToken,
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                await signOut()
                return
            }

            let refreshResponse = try JSONDecoder().decode(RefreshResponse.self, from: data)
            KeychainHelper.set("access_token", value: refreshResponse.access_token)

            user = userFromToken(refreshResponse.access_token)
        } catch {
            await signOut()
        }
    }

    @MainActor
    func signOut() async {
        KeychainHelper.delete("access_token")
        KeychainHelper.delete("refresh_token")
        UserDefaults.standard.removeObject(forKey: "RORK_AUTH_REFRESH_TOKEN")
        user = nil
    }

    private func setError(_ message: String) {
        errorMessage = message
        showError = true
    }
}

// MARK: - Response Types

private struct InitiateResponse: Codable {
    let auth_url: String
    let state: String
    let flow: String?
}

private struct PollCodeResponse: Codable {
    let status: String
    let code: String?
}

private struct TokenResponse: Codable {
    let access_token: String
    let refresh_token: String
    let user: AuthManager.User
}

private struct RefreshResponse: Codable {
    let access_token: String
    let expires_in: Int
}

private struct ErrorResponse: Codable {
    let error: String
}

enum AuthError: LocalizedError {
    case noCode
    case invalidURL
    case serverError(statusCode: Int)
    case popupTimeout
    case cancelledByUser

    var errorDescription: String? {
        switch self {
        case .noCode: return "Kein Berechtigungscode erhalten"
        case .invalidURL: return "Ungültige Adresse"
        case .serverError(let code): return "Serverfehler (\(code))"
        case .popupTimeout: return "Anmeldung hat zu lange gedauert – bitte nochmal versuchen"
        case .cancelledByUser: return "Anmeldung abgebrochen"
        }
    }
}

// MARK: - ASWebAuthenticationSession Helper

class WebAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthPresentationContext()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
