import UIKit
import SafariServices

final class NewsController: ScreenController {
    private let filters = row([])
    private let feed = column(spacing: 12)
    private var selected = 0
    private var task: Task<Void, Never>?

    init() { super.init("BERITA") }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        content.addArrangedSubview(column([
            Theme.label("Wawasan Pasar", 26, weight: .semibold),
            Theme.label("Update Wall Street & dinamika makro global", 13, color: Theme.secondary)
        ], spacing: 4))
        content.addArrangedSubview(horizontalScroll(filters))
        content.addArrangedSubview(feed)
        renderFilters()
    }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); reload() }
    private func renderFilters() {
        filters.clear()
        for (index, title) in ["Terkini", "Saham Pantauan", "Earnings", "Makro"].enumerated() {
            let button = Theme.button(title, filled: selected == index) { [weak self] in
                self?.selected = index; self?.renderFilters(); self?.reload()
            }
            if selected == index { button.configuration?.baseBackgroundColor = Theme.ink }
            button.accessibilityTraits = selected == index ? [.button, .selected] : .button
            filters.addArrangedSubview(button)
        }
    }
    override func reload() {
        task?.cancel()
        state(feed, title: "Memuat berita", message: "Mengambil kabar terbaru dari sumber pasar.", loading: true)
        let selection = selected
        var query = ["limit": "20"]
        if selection == 1 { query["scope"] = "watchlist" }
        if selection == 2 { query["topic"] = "earnings" }
        if selection == 3 { query["topic"] = "macro" }
        task = Task { [weak self] in
            guard let self else { return }
            defer { refresh.endRefreshing() }
            do {
                let response: Envelope<[Article]> = try await api.get("news", query: query)
                try Task.checkCancellation()
                guard selection == selected else { return }
                feed.clear()
                if response.meta?.mode == "demo" {
                    feed.addArrangedSubview(row([Theme.badge("DATA CONTOH", color: Theme.purple, background: Theme.lavender), UIView()]))
                }
                if response.meta?.partial == true {
                    feed.addArrangedSubview(card([
                        Theme.label("Sebagian berita belum termuat", 14, weight: .semibold),
                        Theme.label("Belum tersedia: \(response.meta?.unavailable_symbols?.joined(separator: ", ") ?? "sebagian sumber").", 12, color: Theme.secondary),
                        Theme.button("Coba lagi") { [weak self] in self?.reload() }
                    ]))
                }
                if response.data.isEmpty {
                    state(feed, title: "Belum ada berita", message: selection == 1 ? "Tambahkan saham ke watchlist untuk melihat berita terkait." : "Belum ada artikel yang cocok dengan kategori ini.")
                    return
                }
                for (index, article) in response.data.enumerated() {
                    if index == 1 {
                        feed.addArrangedSubview(row([Theme.label("SOROTAN PENTING", 11, weight: .semibold, color: Theme.secondary),
                                                     UIView(), Theme.badge("\(response.data.count - 1) Artikel", color: Theme.secondary, background: Theme.lavender)]))
                    }
                    feed.addArrangedSubview(articleCard(article, featured: index == 0))
                }
                feed.addArrangedSubview(Theme.label("Berita mengikuti bahasa sumber. Earnings dan Makro memakai filter kata kunci.", 11, color: Theme.secondary))
            } catch {
                guard !Task.isCancelled else { return }
                state(feed, title: "Berita belum termuat", message: Display.error(error), retry: { [weak self] in self?.reload() })
            }
        }
    }
    private func articleCard(_ article: Article, featured: Bool) -> UIView {
        let date = RelativeDateTimeFormatter()
        date.locale = Locale(identifier: "id_ID"); date.unitsStyle = .short
        let time = date.localizedString(for: Date(timeIntervalSince1970: article.datetime), relativeTo: Date())
        let category = article.category.isEmpty ? "PASAR AS" : article.category.uppercased()
        let meta = Theme.label("\(article.source) · \(time)", 11, color: Theme.secondary, mono: true)
        let headline = Theme.label(article.headline, featured ? 21 : 17, weight: .semibold)
        headline.numberOfLines = featured ? 4 : 3
        let headlineButton = UIButton()
        headlineButton.embed(headline); headline.isUserInteractionEnabled = false
        headlineButton.contentHorizontalAlignment = .leading
        headlineButton.accessibilityLabel = article.headline
        headlineButton.addAction(UIAction { [weak self] _ in self?.openArticle(article) }, for: .touchUpInside)
        var body: [UIView] = []
        if featured {
            if let url = URL(string: article.image), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                body.append(ArticleImage(url: url, height: 170))
            }
            body += [row([Theme.badge(category, color: Theme.purple, background: Theme.lavender), UIView()]), headlineButton]
            if !article.summary.isEmpty {
                let summary = Theme.label(article.summary, 13, color: Theme.secondary); summary.numberOfLines = 3
                body.append(summary)
            }
            body.append(meta)
        } else {
            let text = column([row([Theme.badge(category, color: Theme.purple, background: Theme.lavender), UIView()]), headlineButton, meta], spacing: 7)
            if let url = URL(string: article.image), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                let image = ArticleImage(url: url, height: 82)
                image.widthAnchor.constraint(equalToConstant: 82).isActive = true
                body.append(row([text, image], spacing: 12))
            } else { body.append(text) }
        }
        if !article.related_symbols.isEmpty {
            let related = article.related_symbols.prefix(5).map { symbol in
                let button = Theme.button(symbol) { [weak self] in (self?.tabBarController as? ViewController)?.openStock(symbol) }
                button.configuration?.baseBackgroundColor = Theme.lavender
                return button
            }
            body.append(horizontalScroll(row(related), height: 44))
        }
        if featured { body.append(Theme.button("Baca artikel", symbol: "arrow.up.right") { [weak self] in self?.openArticle(article) }) }
        return card(body, inset: featured ? 16 : 12, spacing: 10)
    }
}
extension ScreenController {
    func openArticle(_ article: Article) {
        guard let url = URL(string: article.url), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
            showError(APIError(message: "Tautan artikel belum tersedia.")); return
        }
        let browser = SFSafariViewController(url: url)
        present(browser, animated: true)
    }
}
final class ArticleImage: UIView {
    private var task: Task<Void, Never>?
    init(url: URL, height: CGFloat) {
        super.init(frame: .zero)

        backgroundColor = Theme.lavender; layer.cornerRadius = 12; clipsToBounds = true
        let image = UIImageView(image: UIImage(systemName: "newspaper"))
        image.tintColor = Theme.purple.withAlphaComponent(0.4); image.contentMode = .center
        image.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 32, weight: .light)
        image.isAccessibilityElement = false
        embed(image)
        self.accessibilityIdentifier = "ArticleImage"
        heightAnchor.constraint(equalToConstant: height).isActive = true
        task = Task { [weak image] in
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard !Task.isCancelled, (response as? HTTPURLResponse)?.statusCode == 200, let photo = UIImage(data: data) else { return }
                image?.image = photo; image?.contentMode = .scaleAspectFill
            } catch { /* Keep the native newspaper symbol when the source image cannot load. */ }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { task?.cancel() }
}
