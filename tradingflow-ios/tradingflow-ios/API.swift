import Foundation

struct Envelope<T: Decodable>: Decodable {
    let data: T
    let meta: Metadata?
}

struct SourceValue<T: Decodable>: Decodable {
    let data: T?
    let meta: Metadata?
    let status: String?
    let reason: String?
}

struct Metadata: Decodable {
    let source: String?
    let mode: String?
    let fetched_at: String?
    let partial: Bool?
    let unavailable_symbols: [String]?
    var caption: String {
        if mode == "demo" { return "Data contoh · bukan harga pasar" }
        let provider = source == "yahoo_chart" ? "Yahoo" : (source == "finnhub" ? "Finnhub" : "Snapshot")
        return "\(provider) · diambil \(Display.time(fetched_at))"
    }
}

struct Profile: Decodable {
    let ticker: String
    let name: String
    let exchange: String?
    let currency: String?
    let finnhubIndustry: String?
    let marketCapitalization: Double?
}
struct Quote: Decodable {
    let price: Double?
    let change: Double?
    let change_percent: Double?
    let market_time: String?
}
struct StockCard: Decodable {
    let symbol: String
    var is_saved: Bool
    let profile: SourceValue<Profile>
    let quote: SourceValue<Quote>
    let sparkline: SourceValue<StockChart>?
}
struct WatchlistPage: Decodable {
    let data: [StockCard]
    let total: Int
    let next_offset: Int?
}
struct StockDetail: Decodable {
    let symbol: String
    let profile: SourceValue<Profile>
    let quote: SourceValue<Quote>
    var is_saved: Bool
}
struct StockChart: Decodable {
    let points: [ChartPoint]
    let min: Double?
    let max: Double?
    let currency: String?
    let timezone: String?
}
struct ChartPoint: Decodable, Identifiable {
    let time: String
    let close: Double
    let volume: Int64?
    var id: String { time }
    var date: Date { Display.date(time) ?? .distantPast }
}
struct Statistics: Decodable {
    let market_cap_millions: Double?
    let pe_ttm: Double?
    let week_52_high: Double?
    let week_52_low: Double?
    let average_volume_3m_millions: Double?
    let dividend_yield_percent: Double?
    let dividend_per_share_annual: Double?
}
struct Analysts: Decodable {
    let period: String
    let total: Int
    let buy: Int
    let hold: Int
    let sell: Int
    let buy_percent: Double?
    let hold_percent: Double?
    let sell_percent: Double?
}
struct Market: Decodable {
    let market_status: SourceValue<MarketStatus>
    let indices: [MarketIndex]
}
struct MarketStatus: Decodable { let isOpen: Bool? }
struct MarketIndex: Decodable {
    let name: String
    let price: Double?
    let change_percent: Double?
    let meta: Metadata?
}
struct SearchResults: Decodable { let result: [SearchStock] }
struct SearchStock: Decodable {
    let symbol: String
    let description: String
    let type: String?
}
struct Article: Decodable {
    let id: Int64
    let headline: String
    let summary: String
    let source: String
    let url: String
    let image: String
    let datetime: Double
    let category: String
    let related_symbols: [String]
}
struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct TradingAPI {
    static var baseURL: URL {
        let raw = ProcessInfo.processInfo.environment["TRADINGFLOW_API_URL"]
            ?? Bundle.main.object(forInfoDictionaryKey: "TradingFlowAPIBaseURL") as? String
            ?? "http://127.0.0.1:8080"
        return URL(string: raw) ?? URL(string: "http://127.0.0.1:8080")!
    }
    let baseURL: URL
    private let suppliedAccessToken: String?

    init(baseURL: URL = TradingAPI.baseURL, accessToken: String? = nil) {
        self.baseURL = baseURL
        self.suppliedAccessToken = accessToken
    }

    func request(_ path: String, query: [String: String] = [:], method: String = "GET", symbol: String? = nil) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/v1/" + path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!, timeoutInterval: 30)
        request.httpMethod = method
        if let symbol {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["symbol": symbol])
        }
        let token = try await authorizationToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw APIError(message: "Respons server tidak valid.") }
        if response.statusCode == 401 {
            if suppliedAccessToken != nil {
                return try validated(data, response: response)
            }
            let refreshedToken = try await AuthStore.shared.refreshAccessToken()
            request.setValue("Bearer \(refreshedToken)", forHTTPHeaderField: "Authorization")
            let (retryData, retryResponse) = try await URLSession.shared.data(for: request)
            guard let retryResponse = retryResponse as? HTTPURLResponse else {
                throw APIError(message: "Respons server tidak valid.")
            }
            if retryResponse.statusCode == 401 {
                await AuthStore.shared.clearSession()
                throw APIError(message: "Sesi Anda sudah berakhir. Silakan masuk kembali.")
            }
            return try validated(retryData, response: retryResponse)
        }
        return try validated(data, response: response)
    }

    private func authorizationToken() async throws -> String {
        if let suppliedAccessToken { return suppliedAccessToken }
        return try await AuthStore.shared.accessToken()
    }

    private func validated(_ data: Data, response: HTTPURLResponse) throws -> Data {
        guard (200..<300).contains(response.statusCode) else {
            struct Failure: Decodable { let error: Detail; struct Detail: Decodable { let message: String } }
            let message = (try? JSONDecoder().decode(Failure.self, from: data))?.error.message ?? "Server gagal merespons (\(response.statusCode))."
            let retry = response.statusCode == 429 ? " Coba lagi dalam \(response.value(forHTTPHeaderField: "Retry-After") ?? "60") detik." : ""
            throw APIError(message: message + retry)
        }
        return data
    }
    func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        let data = try await request(path, query: query)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIError(message: "Format data tidak sesuai. Coba muat ulang.") }
    }
    func save(_ symbol: String, saved: Bool) async throws {
        _ = try await request(saved ? "watchlist" : "watchlist/\(symbol)", method: saved ? "POST" : "DELETE", symbol: saved ? symbol : nil)
    }
}

enum Display {
    static func number(_ value: Double?, digits: Int = 2) -> String {
        guard let value, value.isFinite else { return "—" }
        return value.formatted(.number.locale(Locale(identifier: "en_US")).precision(.fractionLength(digits)))
    }
    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return (value >= 0 ? "+" : "") + number(value) + "%"
    }
    static func money(_ value: Double?, currency: String? = "USD") -> String {
        guard let value else { return "—" }
        return (currency == "USD" ? "$" : "\(currency ?? "") ") + number(value)
    }
    static func compact(_ value: Double?) -> String {
        guard let value else { return "—" }
        for (threshold, suffix) in [(1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "K")] where abs(value) >= threshold {
            return number(value / threshold) + suffix
        }
        return number(value)
    }
    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
    static func time(_ value: String?, zone: String? = nil) -> String {
        guard let date = date(value) else { return "belum tersedia" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "id_ID")
        formatter.timeZone = zone.flatMap(TimeZone.init(identifier:)) ?? .current
        formatter.dateFormat = "d MMM, HH:mm z"
        return formatter.string(from: date)
    }
    static func error(_ error: Error) -> String {
        if let error = error as? URLError {
            if error.code == .timedOut { return "Permintaan terlalu lama. Tarik untuk mencoba lagi." }
            return "Tidak dapat terhubung ke server. Pastikan backend TradingFlow berjalan, lalu coba lagi."
        }
        return error.localizedDescription
    }
}
