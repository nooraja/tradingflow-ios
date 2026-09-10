import UIKit
import SwiftUI

final class MarketController: ScreenController, UITextFieldDelegate {
    private let indices = column(spacing: 8)
    private let history = row([])
    private let results = column(spacing: 8)
    private let list = column(spacing: 8)
    private let count = Theme.label("Instrumen yang Anda pantau", 12, color: Theme.secondary)
    private let search = UITextField()
    private let filters = row([])
    private var cards: [StockCard] = []
    private var total = 0
    private var nextOffset: Int?
    private var selectedFilter = 0
    private var searchTask: Task<Void, Never>?
    private var listTask: Task<Void, Never>?
    private var marketTask: Task<Void, Never>?
    private var miniCharts: [UIViewController] = []
    private var pendingSymbols = Set<String>()

    init() { super.init("PASAR") }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        search.placeholder = "Cari saham AS (AAPL, NVDA…)"
        search.font = .systemFont(ofSize: 14); search.textColor = Theme.ink
        search.autocorrectionType = .no; search.autocapitalizationType = .allCharacters
        search.returnKeyType = .search; search.clearButtonMode = .whileEditing
        search.accessibilityIdentifier = "stockSearch"
        search.backgroundColor = UIColor(hex: 0xF3F3FE); search.layer.cornerRadius = 12
        search.layer.borderWidth = 1; search.layer.borderColor = UIColor(hex: 0x89909E).cgColor
        let searchIcon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        searchIcon.tintColor = Theme.secondary; searchIcon.contentMode = .scaleAspectFit
        let left = UIView(frame: CGRect(x: 0, y: 0, width: 40, height: 48))
        searchIcon.frame = CGRect(x: 14, y: 14, width: 20, height: 20); left.addSubview(searchIcon)
        search.leftView = left; search.leftViewMode = .always
        search.heightAnchor.constraint(equalToConstant: 48).isActive = true
        search.delegate = self
        search.addAction(UIAction { [weak self] _ in self?.searchChanged() }, for: .editingChanged)
        content.addArrangedSubview(indices)
        content.addArrangedSubview(card([
            row([Theme.label("●", 12, color: Theme.positive), Theme.label("Eksplorasi Pasar", 18, weight: .semibold), UIView(), Theme.badge("AS", color: Theme.secondary, background: Theme.lavender)]),
            search, horizontalScroll(history, height: 44)
        ]))
        content.addArrangedSubview(results)
        content.addArrangedSubview(horizontalScroll(filters))
        content.addArrangedSubview(row([
            column([Theme.label("Watchlist Utama", 20, weight: .semibold), count], spacing: 3),
            UIView(), Theme.button("Tambah", symbol: "bookmark.badge.plus") { [weak self] in
                self?.scroll.setContentOffset(.zero, animated: true); self?.search.becomeFirstResponder()
            }
        ]))
        content.addArrangedSubview(list)
        renderHistory(); renderFilters()
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated); reload()
    }
    override func reload() {
        loadMarket(); loadWatchlist()
    }
    private func loadMarket() {
        marketTask?.cancel()
        marketTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response: Envelope<Market> = try await api.get("market")
                try Task.checkCancellation()
                indices.clear()
                let chips = response.data.indices.map { index in
                    card([row([Theme.label("●", 10, color: Theme.positive),
                               Theme.label(index.name, 10, weight: .bold),
                               Theme.label(Display.number(index.price), 13, weight: .medium, mono: true),
                               Theme.badge(Display.percent(index.change_percent), color: (index.change_percent ?? 0) < 0 ? Theme.red : Theme.green,
                                           background: (index.change_percent ?? 0) < 0 ? UIColor(hex: 0xFDE5E7) : Theme.mint)])], inset: 8)
                }
                indices.addArrangedSubview(horizontalScroll(row(chips), height: 38))
                let demo = response.data.market_status.meta?.mode == "demo" || response.data.indices.contains { $0.meta?.mode == "demo" }
                let status = response.data.market_status.data?.isOpen.map { $0 ? "Pasar dibuka" : "Pasar ditutup" } ?? "Status pasar belum tersedia"
                indices.addArrangedSubview(Theme.label(demo ? "Data contoh · \(status)" : "\(status) · Snapshot, bukan streaming", 11, color: Theme.secondary))
            } catch {
                guard !Task.isCancelled else { return }
                indices.clear(); indices.addArrangedSubview(Theme.label("Indeks belum tersedia · tarik untuk muat ulang", 11, color: Theme.secondary))
            }
        }
    }
    private func loadWatchlist(more: Bool = false) {
        listTask?.cancel()
        let offset = more ? nextOffset ?? 0 : 0
        if !more && cards.isEmpty { state(list, title: "Memuat watchlist", message: "Mengambil harga dan grafik terbaru.", loading: true) }
        listTask = Task { [weak self] in
            guard let self else { return }
            defer { refresh.endRefreshing() }
            do {
                let page: WatchlistPage = try await api.get("watchlist", query: ["view": "cards", "sparkline": "true", "limit": "5", "offset": "\(offset)"])
                try Task.checkCancellation()
                cards = more ? cards + page.data : page.data
                total = page.total; nextOffset = page.next_offset
                renderCards()
            } catch {
                guard !Task.isCancelled else { return }
                if cards.isEmpty {
                    state(list, title: "Watchlist belum termuat", message: Display.error(error), retry: { [weak self] in self?.loadWatchlist() })
                } else {
                    renderCards()
                    list.insertArrangedSubview(card([Theme.label("Pembaruan gagal · data sebelumnya", 13, weight: .semibold),
                                                    Theme.label(Display.error(error), 12, color: Theme.secondary),
                                                    Theme.button("Coba lagi") { [weak self] in self?.loadWatchlist(more: more) }]), at: 0)
                }
            }
        }
    }
    private func renderFilters() {
        filters.clear()
        for (index, title) in ["Semua", "Watchlist Saya", "Mega Cap", "Teknologi"].enumerated() {
            let button = Theme.button(title, filled: index == selectedFilter) { [weak self] in
                self?.selectedFilter = index; self?.renderFilters(); self?.renderCards()
            }
            if index == selectedFilter { button.configuration?.baseBackgroundColor = Theme.ink }
            button.accessibilityTraits = index == selectedFilter ? [.button, .selected] : .button
            filters.addArrangedSubview(button)
        }
    }
    private func renderCards() {
        miniCharts.forEach { $0.willMove(toParent: nil); $0.view.removeFromSuperview(); $0.removeFromParent() }
        miniCharts.removeAll(); list.clear()
        count.text = "\(total) instrumen dipantau"
        let shown = cards.filter { stock in
            if selectedFilter == 2 { return (stock.profile.data?.marketCapitalization ?? -1) >= 200_000 }
            if selectedFilter == 3 {
                let sector = stock.profile.data?.finnhubIndustry?.lowercased() ?? ""
                return ["tech", "semiconductor", "software"].contains { sector.contains($0) }
            }
            return true
        }
        if shown.isEmpty {
            state(list, title: cards.isEmpty ? "Mulai watchlist Anda" : "Belum ada yang cocok",
                  message: cards.isEmpty ? "Cari saham, buka detail, lalu ketuk Simpan untuk memantaunya di sini." : "Filter berlaku pada \(cards.count) saham yang sudah dimuat.")
        }
        for stock in shown {
            let name = Theme.label(stock.profile.data?.name ?? "Profil belum tersedia", 12, color: Theme.secondary)
            name.numberOfLines = 1; name.lineBreakMode = .byTruncatingTail
            let names = column([Theme.label(stock.symbol, 18, weight: .semibold), name], spacing: 3)
            names.widthAnchor.constraint(greaterThanOrEqualToConstant: 65).isActive = true
            let open = UIButton()
            open.accessibilityLabel = "Buka detail \(stock.symbol)"
            open.embed(row([Theme.stockIcon(stock.symbol), names], spacing: 10))
            open.subviews.forEach { $0.isUserInteractionEnabled = false }
            open.addAction(UIAction { [weak self] _ in self?.open(stock.symbol) }, for: .touchUpInside)
            let price = Theme.label(Display.money(stock.quote.data?.price, currency: stock.profile.data?.currency), 14, weight: .semibold, mono: true)
            price.textAlignment = .right; price.numberOfLines = 1
            price.setContentCompressionResistancePriority(.required, for: .horizontal)
            let change = stock.quote.data?.change_percent
            let prices = column([price, Theme.badge(Display.percent(change), color: (change ?? 0) < 0 ? Theme.red : Theme.green, background: (change ?? 0) < 0 ? UIColor(hex: 0xFDE5E7) : Theme.mint)], spacing: 4)
            prices.alignment = .trailing
            let star = Theme.button("", symbol: "star.fill") { [weak self] in self?.remove(stock.symbol) }
            star.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
            star.configuration?.baseBackgroundColor = .clear
            star.widthAnchor.constraint(equalToConstant: 44).isActive = true
            star.accessibilityLabel = "Hapus \(stock.symbol) dari watchlist"; star.isEnabled = !pendingSymbols.contains(stock.symbol)
            var elements: [UIView] = [open]
            if let chart = stock.sparkline?.data, !chart.points.isEmpty, !traitCollection.preferredContentSizeCategory.isAccessibilityCategory {
                let host = UIHostingController(rootView: PriceChart(chart: chart, compact: true))
                addChild(host); host.view.backgroundColor = .clear
                host.view.widthAnchor.constraint(equalToConstant: 52).isActive = true
                host.view.heightAnchor.constraint(equalToConstant: 32).isActive = true
                elements.append(host.view); host.didMove(toParent: self); miniCharts.append(host)
            }
            if traitCollection.preferredContentSizeCategory.isAccessibilityCategory {
                elements = [column([open, prices], spacing: 8), star]
            } else { elements += [prices, star] }
            let stockRow = row(elements, spacing: 5)
            var body: [UIView] = [stockRow]
            if stock.quote.data == nil || stock.profile.data == nil {
                body.append(Theme.label("Sebagian data belum tersedia · tarik untuk mencoba lagi", 11, color: Theme.secondary))
            }
            list.addArrangedSubview(card(body, inset: 10, spacing: 6))
        }
        if nextOffset != nil {
            list.addArrangedSubview(Theme.button("Muat saham berikutnya", symbol: "chevron.down") { [weak self] in self?.loadWatchlist(more: true) })
        }
        if let meta = cards.first?.quote.meta {
            list.addArrangedSubview(Theme.label(meta.caption + "\nWaktu harga mengikuti sumber; keterlambatan belum diketahui.", 11, color: Theme.secondary))
        }
        if selectedFilter >= 2 {
            list.addArrangedSubview(Theme.label("Filter dari \(cards.count) saham yang dimuat. Mega Cap: kapitalisasi ≥ US$200 miliar; profil tanpa kapitalisasi tidak disertakan.", 11, color: Theme.secondary))
        }
    }
    private func remove(_ symbol: String) {
        guard pendingSymbols.insert(symbol).inserted else { return }
        renderCards()
        Task { [weak self] in
            guard let self else { return }
            defer { pendingSymbols.remove(symbol); renderCards() }
            do { try await api.save(symbol, saved: false); loadWatchlist() }
            catch { showError(error) }
        }
    }
    private func renderHistory() {
        history.clear()
        history.addArrangedSubview(Theme.label("↶ RIWAYAT", 10, weight: .semibold, color: Theme.secondary))
        let recent = UserDefaults.standard.stringArray(forKey: "recentSearches") ?? []
        if recent.isEmpty { history.addArrangedSubview(Theme.label("Pencarian Anda tampil di sini", 11, color: Theme.secondary)) }
        for query in recent {
            let button = Theme.button(query) { [weak self] in self?.search.text = query; self?.searchChanged() }
            button.configuration?.baseBackgroundColor = Theme.lavender
            button.configuration?.baseForegroundColor = Theme.ink
            history.addArrangedSubview(button)
        }
    }
    private func searchChanged() {
        searchTask?.cancel()
        let query = (search.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        results.clear()
        guard !query.isEmpty else { return }
        guard query.utf8.count <= 80 else {
            results.addArrangedSubview(Theme.label("Pencarian maksimal 80 byte.", 13, color: Theme.red)); return
        }
        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .milliseconds(350))
                state(results, title: "Mencari \(query)", message: "Mencari simbol dan nama perusahaan.", loading: true)
                let response: Envelope<SearchResults> = try await api.get("stocks/search", query: ["q": query])
                try Task.checkCancellation()
                results.clear()
                if response.meta?.mode == "demo" { results.addArrangedSubview(Theme.label("Hasil pencarian · Data contoh", 11, color: Theme.purple)) }
                if response.data.result.isEmpty {
                    state(results, title: "Saham tidak ditemukan", message: "Coba simbol lain atau nama perusahaan.")
                }
                for stock in response.data.result.prefix(30) {
                    let button = Theme.button("\(stock.symbol)  ·  \(stock.description)", symbol: "arrow.up.right") { [weak self] in self?.open(stock.symbol) }
                    button.contentHorizontalAlignment = .leading
                    button.titleLabel?.numberOfLines = 2
                    results.addArrangedSubview(button)
                }
            } catch {
                guard !Task.isCancelled else { return }
                state(results, title: "Pencarian belum berhasil", message: Display.error(error), retry: { [weak self] in self?.searchChanged() })
            }
        }
    }
    private func open(_ symbol: String) {
        let query = (search.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            var recent = UserDefaults.standard.stringArray(forKey: "recentSearches") ?? []
            recent.removeAll { $0 == query }; recent.insert(query, at: 0)
            UserDefaults.standard.set(Array(recent.prefix(4)), forKey: "recentSearches"); renderHistory()
        }
        view.endEditing(true)
        (tabBarController as? ViewController)?.openStock(symbol)
    }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool { textField.resignFirstResponder(); searchChanged(); return true }
}
