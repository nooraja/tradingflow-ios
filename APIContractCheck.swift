import Foundation

// Runs against a dedicated DEMO backend; never use with a user's watchlist.
@main
struct APIContractCheck {
    static func main() async throws {
        guard let token = ProcessInfo.processInfo.environment["TRADINGFLOW_TEST_ACCESS_TOKEN"], !token.isEmpty else {
            fatalError("Set TRADINGFLOW_TEST_ACCESS_TOKEN to a permitted Supabase access token.")
        }
        let api = TradingAPI(baseURL: URL(string: "http://127.0.0.1:8081")!, accessToken: token)
        let (healthData, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:8081/health")!)
        let health = try JSONSerialization.jsonObject(with: healthData) as? [String: String]
        precondition(health?["mode"] == "demo", "Only a dedicated demo backend is allowed.")
        let search: Envelope<SearchResults> = try await api.get("stocks/search", query: ["q": "Apple"])
        precondition(search.data.result.contains { $0.symbol == "AAPL" })
        precondition(search.meta?.mode == "demo")
        let missing: Envelope<SearchResults> = try await api.get("stocks/search", query: ["q": "zzzznotastock"])
        precondition(missing.data.result.isEmpty)
        try await api.save("AAPL", saved: true)
        try await api.save("AAPL", saved: true)
        let page: WatchlistPage = try await api.get("watchlist", query: ["view": "cards", "sparkline": "true", "limit": "1"])
        precondition(page.data.count == 1 && page.data[0].symbol == "AAPL")
        precondition(page.data[0].quote.data?.price == 200)
        let detail: Envelope<StockDetail> = try await api.get("stocks/AAPL")
        precondition(detail.data.is_saved && detail.data.profile.data?.name == "Apple Inc.")
        for range in ["1D", "1W", "1M", "1Y", "ALL"] {
            let chart: Envelope<StockChart> = try await api.get("stocks/AAPL/chart", query: ["range": range])
            precondition(!chart.data.points.isEmpty)
            precondition(chart.data.points.allSatisfy { Display.date($0.time) != nil })
            precondition(chart.data.min == chart.data.points.map(\.close).min())
        }
        let stats: Envelope<Statistics> = try await api.get("stocks/AAPL/statistics")
        precondition(stats.data.market_cap_millions == 3_000_000)
        precondition(Display.compact(stats.data.market_cap_millions.map { $0 * 1e6 }) == "3.00T")
        precondition(Display.money(nil) == "—")
        precondition(Display.percent(-1.15) == "-1.15%")
        precondition(Display.date("2026-09-09T15:00:00.123456789Z") != nil)
        let analysts: Envelope<Analysts> = try await api.get("stocks/AAPL/analysts")
        precondition(analysts.data.total == analysts.data.buy + analysts.data.hold + analysts.data.sell)
        let market: Envelope<Market> = try await api.get("market")
        precondition(market.data.indices.count == 2)
        let news: Envelope<[Article]> = try await api.get("news")
        precondition(!news.data.isEmpty && news.meta?.mode == "demo")
        let macro: Envelope<[Article]> = try await api.get("news", query: ["topic": "macro"])
        precondition(macro.data.isEmpty)
        let watchNews: Envelope<[Article]> = try await api.get("news", query: ["scope": "watchlist"])
        precondition(watchNews.data.contains { $0.related_symbols.contains("AAPL") })
        let partial = Data(#"{"data":null,"status":"unavailable","reason":"Unavailable"}"#.utf8)
        let unavailable = try JSONDecoder().decode(SourceValue<Quote>.self, from: partial)
        precondition(unavailable.data == nil)
        do {
            let _: Envelope<StockChart> = try await api.get("stocks/AAPL/chart", query: ["range": "INVALID"])
            preconditionFailure("Invalid range must fail")
        } catch let error as APIError { precondition(error.message.contains("range")) }
        try await api.save("AAPL", saved: false)
        try await api.save("AAPL", saved: false)
        let removed: Envelope<StockDetail> = try await api.get("stocks/AAPL")
        precondition(!removed.data.is_saved)
        print("PASS: search, no results, mutations, cards, detail, five chart ranges, statistics units, analysts, market, news filters, partial data, dates, missing values, API errors.")
    }
}
