import UIKit

final class ViewController: UITabBarController {
    let market = MarketController()
    let news = NewsController()
    let detail = DetailController()
    private let signOut: () -> Void

    init(signOut: @escaping () -> Void = {}) {
        self.signOut = signOut
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        market.tabBarItem = UITabBarItem(title: "Pasar", image: UIImage(systemName: "chart.bar.xaxis"), tag: 0)
        news.tabBarItem = UITabBarItem(title: "Berita", image: UIImage(systemName: "newspaper"), tag: 1)
        detail.tabBarItem = UITabBarItem(title: "Detail & Riset", image: UIImage(systemName: "chart.xyaxis.line"), tag: 2)
        let account = AccountController(signedOut: signOut)
        account.tabBarItem = UITabBarItem(title: "Akun", image: UIImage(systemName: "person"), tag: 3)
        viewControllers = [market, news, detail, account]
        tabBar.accessibilityIdentifier = "app.tabBar"
        tabBar.tintColor = Theme.green; tabBar.unselectedItemTintColor = Theme.secondary
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .white.withAlphaComponent(0.96); appearance.shadowColor = Theme.lavender
        tabBar.standardAppearance = appearance; tabBar.scrollEdgeAppearance = appearance
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.assignMissingAccessibilityIdentifiers(prefix: "tradingflow.application")
    }
    func openStock(_ symbol: String) { detail.select(symbol); selectedIndex = 2 }
}
