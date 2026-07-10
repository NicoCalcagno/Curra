import AuthenticationServices
import Foundation

/// OAuth 2.0 against Strava with tokens stored in the Keychain.
/// The user provides their own API application credentials in Settings
/// (personal single-user app — no backend to hide a secret behind).
@MainActor
final class StravaAuthService: NSObject {
    static let shared = StravaAuthService()

    private enum Keys {
        static let accessToken = "strava.accessToken"
        static let refreshToken = "strava.refreshToken"
        static let expiresAt = "strava.expiresAt"
        static let clientSecret = "strava.clientSecret"
        static let clientID = "strava.clientID"
    }

    private let keychain = KeychainStore.shared
    private var authSession: ASWebAuthenticationSession?

    // MARK: - Credentials

    var clientID: String {
        get { UserDefaults.standard.string(forKey: Keys.clientID) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.clientID) }
    }

    var clientSecret: String {
        get { keychain.get(Keys.clientSecret) ?? "" }
        set { keychain.set(newValue, for: Keys.clientSecret) }
    }

    var isConnected: Bool { keychain.get(Keys.refreshToken) != nil }

    // MARK: - Connect / disconnect

    func connect() async throws {
        guard !clientID.isEmpty, !clientSecret.isEmpty else {
            throw StravaError.missingCredentials
        }

        var components = URLComponents(string: "https://www.strava.com/oauth/mobile/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: "curra://oauth"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: "activity:read_all")
        ]

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: components.url!,
                callbackURLScheme: "curra"
            ) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(
                        throwing: StravaError.oauthFailed(error?.localizedDescription ?? "cancelled")
                    )
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            session.start()
        }

        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value
        else {
            throw StravaError.oauthFailed("missing authorization code")
        }

        let token = try await requestToken(parameters: [
            "grant_type": "authorization_code",
            "code": code
        ])
        store(token)
    }

    func disconnect() {
        keychain.remove(Keys.accessToken)
        keychain.remove(Keys.refreshToken)
        keychain.remove(Keys.expiresAt)
    }

    // MARK: - Token access

    /// Returns a valid access token, refreshing it when it expires within 5 minutes.
    func validAccessToken() async throws -> String {
        guard let refreshToken = keychain.get(Keys.refreshToken) else {
            throw StravaError.notConnected
        }
        let expiresAt = Double(keychain.get(Keys.expiresAt) ?? "0") ?? 0
        if let access = keychain.get(Keys.accessToken),
           expiresAt - Date().timeIntervalSince1970 > 300 {
            return access
        }

        let token = try await requestToken(parameters: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ])
        store(token)
        return token.accessToken
    }

    // MARK: - Private

    private func requestToken(parameters: [String: String]) async throws -> StravaTokenResponse {
        var request = URLRequest(url: URL(string: "https://www.strava.com/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var allParameters = parameters
        allParameters["client_id"] = clientID
        allParameters["client_secret"] = clientSecret
        request.httpBody = allParameters
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw StravaError.httpError(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }
        do {
            return try JSONDecoder().decode(StravaTokenResponse.self, from: data)
        } catch {
            throw StravaError.decoding(error)
        }
    }

    private func store(_ token: StravaTokenResponse) {
        keychain.set(token.accessToken, for: Keys.accessToken)
        keychain.set(token.refreshToken, for: Keys.refreshToken)
        keychain.set(String(token.expiresAt), for: Keys.expiresAt)
    }
}

extension StravaAuthService: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { ASPresentationAnchor() }
    }
}
