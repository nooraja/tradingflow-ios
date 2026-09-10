import Foundation
import Security

struct AuthConfiguration {
    let supabaseURL: URL
    let publishableKey: String

    static func load() throws -> AuthConfiguration {
        let environment = ProcessInfo.processInfo.environment
        let rawURL = environment["TRADINGFLOW_SUPABASE_URL"]
            ?? Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String
            ?? ""
        let key = environment["TRADINGFLOW_SUPABASE_PUBLISHABLE_KEY"]
            ?? Bundle.main.object(forInfoDictionaryKey: "SupabasePublishableKey") as? String
            ?? ""
        guard let url = URL(string: rawURL), url.scheme == "https", url.host != nil, !key.isEmpty else {
            throw AuthError.configurationMissing
        }
        return AuthConfiguration(supabaseURL: url, publishableKey: key)
    }
}

enum AuthError: LocalizedError {
    case configurationMissing
    case invalidResponse
    case emailConfirmationRequired
    case signedOut
    case message(String)

    var errorDescription: String? {
        switch self {
        case .configurationMissing:
            return "Konfigurasi Supabase belum diisi. Tambahkan URL proyek dan publishable key sesuai panduan iOS."
        case .invalidResponse:
            return "Respons autentikasi tidak valid. Coba lagi."
        case .emailConfirmationRequired:
            return "Akun dibuat. Periksa email Anda untuk mengonfirmasi akun, lalu masuk."
        case .signedOut:
            return "Sesi tidak tersedia. Silakan masuk kembali."
        case .message(let message):
            return message
        }
    }
}

struct SupabaseSession: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let user: AuthUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
        case user
    }

    init(accessToken: String, refreshToken: String, expiresAt: Date, user: AuthUser) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.user = user
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        refreshToken = try container.decode(String.self, forKey: .refreshToken)
        user = try container.decode(AuthUser.self, forKey: .user)
        if let timestamp = try container.decodeIfPresent(Double.self, forKey: .expiresAt) {
            expiresAt = Date(timeIntervalSince1970: timestamp)
        } else {
            expiresAt = Date().addingTimeInterval(try container.decodeIfPresent(Double.self, forKey: .expiresIn) ?? 0)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accessToken, forKey: .accessToken)
        try container.encode(refreshToken, forKey: .refreshToken)
        try container.encode(expiresAt.timeIntervalSince1970, forKey: .expiresAt)
        try container.encode(user, forKey: .user)
    }
}

struct AuthUser: Codable, Sendable {
    let id: String
    let email: String?
    let createdAt: String?
    let emailConfirmedAt: String?
    let userMetadata: UserMetadata?

    enum CodingKeys: String, CodingKey {
        case id, email
        case createdAt = "created_at"
        case emailConfirmedAt = "email_confirmed_at"
        case userMetadata = "user_metadata"
    }

    var displayName: String {
        let name = userMetadata?.fullName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty { return name }
        return email?.split(separator: "@").first.map(String.init) ?? "Investor"
    }
}

struct UserMetadata: Codable, Sendable {
    let fullName: String?
    enum CodingKeys: String, CodingKey { case fullName = "full_name" }
}

private struct SupabaseErrorResponse: Decodable {
    let message: String?
    let errorDescription: String?
    enum CodingKeys: String, CodingKey {
        case message
        case errorDescription = "error_description"
    }
}

private enum SessionKeychain {
    static let service = "co.id.tradingflow-ios.auth"
    static let account = "supabase-session"

    static func read() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw AuthError.message("Keychain tidak dapat dibaca.") }
        return item as? Data
    }

    static func save(_ data: Data) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let update = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        var addition = base
        addition[kSecValueData as String] = data
        addition[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(addition as CFDictionary, nil)
        guard added == errSecSuccess else { throw AuthError.message("Sesi tidak dapat disimpan dengan aman.") }
    }

    static func remove() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

actor AuthStore {
    static let shared = AuthStore()
    private var session: SupabaseSession?

    func restoreSession() async throws -> SupabaseSession? {
        if let session { return session }
        guard let data = try SessionKeychain.read() else { return nil }
        let stored = try JSONDecoder().decode(SupabaseSession.self, from: data)
        session = stored
        do {
            return try await refreshed(stored)
        } catch {
            SessionKeychain.remove()
            session = nil
            return nil
        }
    }

    func currentSession() -> SupabaseSession? { session }

    func signIn(email: String, password: String) async throws -> SupabaseSession {
        let config = try AuthConfiguration.load()
        let data = try await send(
            config,
            path: "auth/v1/token",
            query: [URLQueryItem(name: "grant_type", value: "password")],
            body: ["email": email, "password": password]
        )
        let fresh = try JSONDecoder().decode(SupabaseSession.self, from: data)
        try save(fresh)
        return fresh
    }

    func signUp(name: String, email: String, password: String) async throws {
        let config = try AuthConfiguration.load()
        let body: [String: Any] = [
            "email": email,
            "password": password,
            "data": ["full_name": name]
        ]
        let data = try await send(config, path: "auth/v1/signup", body: body)
        if let fresh = try? JSONDecoder().decode(SupabaseSession.self, from: data), !fresh.accessToken.isEmpty {
            try save(fresh)
            return
        }
        throw AuthError.emailConfirmationRequired
    }

    func accessToken() async throws -> String {
        guard let session else { throw AuthError.signedOut }
        if session.expiresAt > Date().addingTimeInterval(60) { return session.accessToken }
        return try await refreshed(session).accessToken
    }

    func refreshAccessToken() async throws -> String {
        guard let session else { throw AuthError.signedOut }
        return try await refreshed(session).accessToken
    }

    func profile() async throws -> AuthUser {
        let config = try AuthConfiguration.load()
        let token = try await accessToken()
        var request = URLRequest(url: config.supabaseURL.appendingPathComponent("auth/v1/user"))
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw try error(data, response: response) }
        let user = try JSONDecoder().decode(AuthUser.self, from: data)
        if var current = session {
            current = SupabaseSession(accessToken: current.accessToken, refreshToken: current.refreshToken, expiresAt: current.expiresAt, user: user)
            try save(current)
        }
        return user
    }

    func signOut() async {
        defer { clearSession() }
        guard let session, let config = try? AuthConfiguration.load() else { return }
        var request = URLRequest(url: config.supabaseURL.appendingPathComponent("auth/v1/logout"))
        request.httpMethod = "POST"
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: request)
    }

    func clearSession() {
        session = nil
        SessionKeychain.remove()
    }

    private func refreshed(_ old: SupabaseSession) async throws -> SupabaseSession {
        let config = try AuthConfiguration.load()
        let data = try await send(
            config,
            path: "auth/v1/token",
            query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            body: ["refresh_token": old.refreshToken]
        )
        let fresh = try JSONDecoder().decode(SupabaseSession.self, from: data)
        try save(fresh)
        return fresh
    }

    private func save(_ fresh: SupabaseSession) throws {
        session = fresh
        try SessionKeychain.save(JSONEncoder().encode(fresh))
    }

    private func send(_ config: AuthConfiguration, path: String, query: [URLQueryItem] = [], body: Any) async throws -> Data {
        var components = URLComponents(url: config.supabaseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw try error(data, response: response) }
        return data
    }

    private func error(_ data: Data, response: HTTPURLResponse) throws -> Error {
        let decoded = try? JSONDecoder().decode(SupabaseErrorResponse.self, from: data)
        let message = decoded?.errorDescription ?? decoded?.message ?? "Autentikasi gagal (\(response.statusCode))."
        return AuthError.message(message)
    }
}
