import UIKit
import SwiftUI

final class DetailController: ScreenController {
    private var symbol = UserDefaults.standard.string(forKey: "lastStock") ?? "AAPL"
    private var detail: StockDetail?
    private var range = "1W"
    private let header = column()
    private let chartContent = column()
    private let statsContent = column()
    private let analystContent = column()
    private let stockNews = column()
    private let ranges = UISegmentedControl(items: ["1D", "1W", "1M", "1Y", "SEMUA"])
    private var loadTask: Task<Void, Never>?
    private var chartTask: Task<Void, Never>?
    private var chartHost: UIViewController?
    private var saving = false
    private var sessionCaption = "Status pasar belum tersedia"

    init() { super.init("DETAIL & RISET") }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        ranges.selectedSegmentIndex = 1; ranges.selectedSegmentTintColor = .white
        ranges.backgroundColor = Theme.lavender.withAlphaComponent(0.65)
        ranges.setTitleTextAttributes([.foregroundColor: Theme.green, .font: UIFont.systemFont(ofSize: 13, weight: .semibold)], for: .selected)
        ranges.heightAnchor.constraint(equalToConstant: 36).isActive = true
        ranges.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            range = ["1D", "1W", "1M", "1Y", "ALL"][ranges.selectedSegmentIndex]; loadChart()
        }, for: .valueChanged)
        content.addArrangedSubview(header)
        content.addArrangedSubview(card([ranges, chartContent]))
        content.addArrangedSubview(Theme.label("Statistik Utama", 20, weight: .semibold))
        content.addArrangedSubview(statsContent)
        content.addArrangedSubview(analystContent)
        content.addArrangedSubview(stockNews)
    }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); reload() }
    func select(_ symbol: String) {
        guard self.symbol != symbol else { return }
        self.symbol = symbol; detail = nil
        UserDefaults.standard.set(symbol, forKey: "lastStock")
        if isViewLoaded { scroll.setContentOffset(.zero, animated: false) }
    }
    override func reload() {
        loadTask?.cancel()
        let requestedSymbol = symbol
        state(header, title: requestedSymbol, message: "Memuat profil dan harga saham.", loading: true)
        state(statsContent, title: "Memuat statistik", message: "Kapitalisasi, valuasi, dan dividen.", loading: true)
        analystContent.clear(); stockNews.clear()
        loadChart()
        loadTask = Task { [weak self] in
            guard let self else { return }
            defer { refresh.endRefreshing() }
            do {
                let response: Envelope<StockDetail> = try await api.get("stocks/\(requestedSymbol)")
                let market: Envelope<Market>? = try? await api.get("market")
                sessionCaption = market?.data.market_status.data?.isOpen.map { $0 ? "PASAR DIBUKA" : "PASAR DITUTUP" } ?? "STATUS BELUM TERSEDIA"
                try Task.checkCancellation()
                guard symbol == requestedSymbol else { return }
                detail = response.data; renderHeader()
            } catch {
                guard !Task.isCancelled else { return }
                detail = nil
                state(header, title: "\(requestedSymbol) belum termuat", message: Display.error(error), retry: { [weak self] in self?.reload() })
            }
            guard !Task.isCancelled else { return }
            await loadStatistics(requestedSymbol)
            guard !Task.isCancelled else { return }
            await loadAnalysts(requestedSymbol)
            guard !Task.isCancelled else { return }
            await loadNews(requestedSymbol)
        }
    }
    private func renderHeader() {
        guard let detail else { return }
        header.clear()
        let profile = detail.profile.data
        let quote = detail.quote.data
        let title = row([Theme.stockIcon(symbol), column([
            Theme.label(profile?.name ?? symbol, 20, weight: .semibold),
            Theme.label("\(symbol) · \(profile?.exchange ?? "Bursa belum tersedia")\n\(profile?.finnhubIndustry ?? "Sektor belum tersedia")", 12, color: Theme.secondary)
        ], spacing: 4)], spacing: 12)
        let price = row([Theme.label(Display.money(quote?.price, currency: profile?.currency), 34, weight: .semibold, mono: true),
                         Theme.label(profile?.currency ?? "", 10, weight: .bold, color: Theme.secondary), UIView()])
        let change = quote?.change
        let delta = change.map { ($0 >= 0 ? "+" : "−") + Display.money(abs($0), currency: profile?.currency) } ?? "—"
        let negative = (quote?.change_percent ?? 0) < 0
        let changes = row([Theme.badge("\(delta) (\(Display.percent(quote?.change_percent)))",
                                      color: negative ? Theme.red : Theme.green,
                                      background: negative ? UIColor(hex: 0xFDE5E7) : Theme.mint),
                           Theme.label("Hari ini", 12, color: Theme.secondary), UIView()])
        let save = Theme.button(detail.is_saved ? "Tersimpan" : "Simpan", symbol: detail.is_saved ? "bookmark.fill" : "bookmark") { [weak self] in self?.toggleSaved() }
        save.isEnabled = !saving; save.accessibilityIdentifier = "saveStock"
        let shareButton = Theme.button("Bagikan", symbol: "square.and.arrow.up") { [weak self] in
            guard let self else { return }
            share(["\(profile?.name ?? symbol) (\(symbol))\n\(Display.money(quote?.price, currency: profile?.currency)) · \(Display.percent(quote?.change_percent))\n\(detail.quote.meta?.caption ?? "Snapshot")\nWaktu harga: \(Display.time(quote?.market_time))"], from: header)
        }
        header.addArrangedSubview(card([
            row([Theme.badge(sessionCaption, color: Theme.secondary, background: Theme.lavender), UIView()]),
            title, price, changes,
            Theme.label("Waktu harga: \(Display.time(quote?.market_time))", 11, color: Theme.secondary),
            row([save, shareButton, UIView()]),
            Theme.label(detail.quote.meta?.caption ?? "Snapshot · waktu pembaruan belum tersedia", 11, color: Theme.secondary)
        ], inset: 16))
    }
    private func toggleSaved() {
        guard let detail, !saving else { return }
        let requestedSymbol = symbol, newValue = !detail.is_saved
        saving = true; renderHeader()
        Task { [weak self] in
            guard let self else { return }
            do {
                try await api.save(requestedSymbol, saved: newValue)
                if symbol == requestedSymbol { self.detail?.is_saved = newValue }
            } catch { showError(error) }
            saving = false; renderHeader()
        }
    }
    private func loadChart() {
        chartTask?.cancel()
        chartHost?.willMove(toParent: nil); chartHost?.view.removeFromSuperview(); chartHost?.removeFromParent(); chartHost = nil
        state(chartContent, title: "Grafik \(range)", message: "Mengambil riwayat harga.", loading: true)
        let requestedSymbol = symbol, requestedRange = range
        chartTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response: Envelope<StockChart> = try await api.get("stocks/\(requestedSymbol)/chart", query: ["range": requestedRange])
                try Task.checkCancellation()
                guard requestedSymbol == symbol, requestedRange == range else { return }
                chartContent.clear()
                guard !response.data.points.isEmpty else {
                    state(chartContent, title: "Grafik belum tersedia", message: "Belum ada titik harga untuk rentang ini."); return
                }
                let host = UIHostingController(rootView: PriceChart(chart: response.data))
                addChild(host); host.view.backgroundColor = .clear
                chartContent.addArrangedSubview(host.view)
                host.view.heightAnchor.constraint(equalToConstant: 276).isActive = true
                host.didMove(toParent: self); chartHost = host
                chartContent.addArrangedSubview(Theme.label(response.meta?.caption ?? "Riwayat harga Yahoo", 10, color: Theme.secondary))
            } catch {
                guard !Task.isCancelled else { return }
                state(chartContent, title: "Grafik belum tersedia", message: Display.error(error), retry: { [weak self] in self?.loadChart() })
            }
        }
    }
    private func loadStatistics(_ requestedSymbol: String) async {
        do {
            let response: Envelope<Statistics> = try await api.get("stocks/\(requestedSymbol)/statistics")
            try Task.checkCancellation()
            guard symbol == requestedSymbol else { return }
            let stats = response.data
            statsContent.clear()
            let currency = detail?.profile.data?.currency ?? "USD"
            let cap = stats.market_cap_millions.map { Display.compact($0 * 1_000_000) } ?? "—"
            let first = row([
                metric("Kapitalisasi Pasar", value: (stats.market_cap_millions == nil ? "" : (currency == "USD" ? "$" : currency + " ")) + cap, symbol: "building.columns", foot: "Nilai pasar perusahaan"),
                metric("Rasio P/E (TTM)", value: stats.pe_ttm.map { Display.number($0, digits: 1) + "x" } ?? "—", symbol: "function", foot: "12 bulan terakhir")
            ])
            first.distribution = .fillEqually
            if traitCollection.preferredContentSizeCategory.isAccessibilityCategory { first.axis = .vertical; first.alignment = .fill; first.distribution = .fill }
            statsContent.addArrangedSubview(first)
            let lowHigh = row([
                column([Theme.label("52-WK LOW", 10, weight: .semibold, color: Theme.secondary), Theme.label(Display.money(stats.week_52_low, currency: currency), 15, weight: .semibold, mono: true)], spacing: 3),
                UIView(),
                column([Theme.label("52-WK HIGH", 10, weight: .semibold, color: Theme.secondary), Theme.label(Display.money(stats.week_52_high, currency: currency), 15, weight: .semibold, mono: true)], spacing: 3)
            ])
            var rangeViews: [UIView] = [Theme.label("Rentang 52 Minggu", 13, color: Theme.secondary)]
            if let low = stats.week_52_low, let high = stats.week_52_high, high > low, let price = detail?.quote.data?.price {
                let progress = UIProgressView(progressViewStyle: .bar)
                progress.progressTintColor = Theme.positive; progress.trackTintColor = Theme.lavender
                progress.progress = Float(min(1, max(0, (price - low) / (high - low))))
                progress.accessibilityLabel = "Posisi harga dalam rentang 52 minggu"
                rangeViews.append(progress)
            }
            rangeViews.append(lowHigh)
            statsContent.addArrangedSubview(card(rangeViews))
            let last = row([
                metric("Volume Rata-rata", value: stats.average_volume_3m_millions.map { Display.number($0, digits: 1) + "M" } ?? "—", symbol: "chart.bar.fill", foot: "Rata-rata 3 bulan"),
                metric("Imbal Hasil Dividen", value: stats.dividend_yield_percent.map { Display.number($0) + "%" } ?? "—", symbol: "banknote", foot: "\(Display.money(stats.dividend_per_share_annual, currency: currency)) / saham / tahun")
            ])
            last.distribution = .fillEqually
            if traitCollection.preferredContentSizeCategory.isAccessibilityCategory { last.axis = .vertical; last.alignment = .fill; last.distribution = .fill }
            statsContent.addArrangedSubview(last)
            statsContent.addArrangedSubview(Theme.label((response.meta?.caption ?? "") + "\n— berarti belum tersedia.", 10, color: Theme.secondary))
        } catch {
            guard !Task.isCancelled else { return }
            state(statsContent, title: "Statistik belum tersedia", message: Display.error(error), retry: { [weak self] in self?.reload() })
        }
    }
    private func metric(_ title: String, value: String, symbol: String, foot: String) -> UIView {
        card([
            row([Theme.label(title, 12, color: Theme.secondary), UIView(), Theme.icon(symbol, color: Theme.purple, size: 30)]),
            Theme.label(value, 23, weight: .semibold, mono: true),
            Theme.label(foot, 10, color: Theme.green, mono: true)
        ], inset: 12, spacing: 9)
    }
    private func loadAnalysts(_ requestedSymbol: String) async {
        do {
            let response: Envelope<Analysts> = try await api.get("stocks/\(requestedSymbol)/analysts")
            try Task.checkCancellation()
            guard symbol == requestedSymbol else { return }
            let data = response.data
            analystContent.clear()
            var views: [UIView] = [
                row([Theme.icon("checkmark.shield", background: Theme.mint), column([
                    Theme.label("Konsensus Analis", 19, weight: .semibold),
                    Theme.label("\(data.total) analis · periode \(data.period)", 12, color: Theme.secondary)
                ], spacing: 3)])
            ]
            if data.total > 0 {
                let bar = row([], spacing: 2); bar.alignment = .fill
                bar.heightAnchor.constraint(equalToConstant: 8).isActive = true
                bar.layer.cornerRadius = 4; bar.clipsToBounds = true
                for (value, color) in [(data.buy, Theme.positive), (data.hold, UIColor(hex: 0xCFBAFF)), (data.sell, Theme.red)] where value > 0 {
                    let segment = UIView(); segment.backgroundColor = color; bar.addArrangedSubview(segment)
                    // Small spacing is excluded from the proportions through a common width ratio.
                    if let first = bar.arrangedSubviews.first, first !== segment {
                        let firstCount = data.buy > 0 ? data.buy : (data.hold > 0 ? data.hold : data.sell)
                        segment.widthAnchor.constraint(equalTo: first.widthAnchor, multiplier: CGFloat(value) / CGFloat(firstCount)).isActive = true
                    }
                }
                views.append(bar)
                let legend = row([
                    Theme.label("● \(Display.number(data.buy_percent, digits: 0))% Beli (\(data.buy))", 11, color: Theme.green),
                    Theme.label("● \(Display.number(data.hold_percent, digits: 0))% Tahan (\(data.hold))", 11, color: Theme.purple),
                    Theme.label("● \(Display.number(data.sell_percent, digits: 0))% Jual (\(data.sell))", 11, color: Theme.red)
                ]); legend.distribution = .fillEqually
                if traitCollection.preferredContentSizeCategory.isAccessibilityCategory { legend.axis = .vertical; legend.alignment = .leading }
                views.append(legend)
            } else { views.append(Theme.label("Belum ada rekomendasi analis untuk periode ini.", 13, color: Theme.secondary)) }
            views.append(Theme.label("Target harga belum tersedia pada paket data saat ini.", 12, color: Theme.secondary))
            views.append(Theme.label(response.meta?.caption ?? "", 10, color: Theme.secondary))
            analystContent.addArrangedSubview(card(views))
        } catch {
            guard !Task.isCancelled else { return }
            state(analystContent, title: "Analis belum tersedia", message: Display.error(error), retry: { [weak self] in self?.reload() })
        }
    }
    private func loadNews(_ requestedSymbol: String) async {
        do {
            let response: Envelope<[Article]> = try await api.get("stocks/\(requestedSymbol)/news", query: ["limit": "3"])
            try Task.checkCancellation()
            guard requestedSymbol == symbol else { return }
            stockNews.clear()
            stockNews.addArrangedSubview(Theme.label("Berita \(symbol)", 20, weight: .semibold))
            if response.meta?.mode == "demo" { stockNews.addArrangedSubview(Theme.label("Data contoh", 11, color: Theme.purple)) }
            for article in response.data {
                stockNews.addArrangedSubview(Theme.button(article.headline, symbol: "newspaper") { [weak self] in self?.openArticle(article) })
            }
            if response.data.isEmpty { stockNews.addArrangedSubview(Theme.label("Belum ada berita saham ini.", 13, color: Theme.secondary)) }
        } catch {
            guard !Task.isCancelled else { return }
            state(stockNews, title: "Berita saham belum tersedia", message: Display.error(error), retry: { [weak self] in self?.reload() })
        }
    }
}
