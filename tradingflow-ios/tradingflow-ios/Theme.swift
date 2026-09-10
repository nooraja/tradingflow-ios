import UIKit

enum Theme {
    static let ink = UIColor(hex: 0x131B2E)
    static let secondary = UIColor(hex: 0x526259)
    static let green = UIColor(hex: 0x007A55)
    static let positive = UIColor(hex: 0x09BD88)
    static let mint = UIColor(hex: 0xA5F7D4)
    static let purple = UIColor(hex: 0x793DED)
    static let lavender = UIColor(hex: 0xEAE7FF)
    static let red = UIColor(hex: 0xC82A3B)

    static func label(_ text: String, _ size: CGFloat = 14, weight: UIFont.Weight = .regular, color: UIColor = ink, mono: Bool = false) -> UILabel {
        let label = UILabel()
        label.text = text
        let font = mono ? UIFont.monospacedSystemFont(ofSize: size, weight: weight) : UIFont.systemFont(ofSize: size, weight: weight)
        label.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: font)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color; label.numberOfLines = 0
        return label
    }
    static func button(_ title: String, symbol: String? = nil, filled: Bool = false, action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.image = symbol.flatMap { UIImage(systemName: $0) }; config.imagePadding = 6
        config.baseBackgroundColor = filled ? green : .white.withAlphaComponent(0.85)
        config.baseForegroundColor = filled ? .white : green
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attr in
            var attr = attr; attr.font = .systemFont(ofSize: 14, weight: .semibold); return attr
        }
        let button = UIButton(configuration: config, primaryAction: UIAction { _ in action() })
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        return button
    }
    static func badge(_ text: String, color: UIColor = green, background: UIColor = mint) -> UIView {
        let text = label(text, 10, weight: .semibold, color: color, mono: true)
        text.numberOfLines = 1
        text.setContentCompressionResistancePriority(.required, for: .horizontal)
        let container = UIView(); container.backgroundColor = background; container.layer.cornerRadius = 8
        container.embed(text, inset: UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8))
        return container
    }
    static func icon(_ symbol: String, color: UIColor = green, background: UIColor = lavender, size: CGFloat = 42) -> UIView {
        let box = UIView(); box.backgroundColor = background; box.layer.cornerRadius = 13
        let image = UIImageView(image: UIImage(systemName: symbol)); image.tintColor = color; image.contentMode = .scaleAspectFit
        box.embed(image, inset: UIEdgeInsets(top: 11, left: 11, bottom: 11, right: 11))
        NSLayoutConstraint.activate([box.widthAnchor.constraint(equalToConstant: size), box.heightAnchor.constraint(equalToConstant: size)])
        return box
    }
    static func stockIcon(_ symbol: String) -> UIView {
        switch symbol {
        case "AAPL": return icon("laptopcomputer", color: ink)
        case "NVDA": return icon("cpu", background: mint.withAlphaComponent(0.7))
        case "MSFT": return icon("square.grid.2x2", color: .systemTeal, background: UIColor(hex: 0xDEF4FF))
        case "TSLA": return icon("bolt.fill", color: red, background: UIColor(hex: 0xFDE5E7))
        case "PLTR": return icon("point.3.connected.trianglepath.dotted", color: purple)
        default: return icon("building.2", color: purple)
        }
    }
}
extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}
extension UIView {
    func embed(_ child: UIView, inset: UIEdgeInsets = .zero) {
        addSubview(child); child.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: topAnchor, constant: inset.top),
            child.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset.left),
            child.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset.right),
            child.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset.bottom)
        ])
    }

    /// Preserves explicit control identifiers and fills in the rest for View Debugger.
    func assignMissingAccessibilityIdentifiers(prefix: String) {
        func visit(_ current: UIView, path: String) {
            if current.accessibilityIdentifier == nil {
                let type = String(describing: type(of: current))
                    .replacingOccurrences(of: "UI", with: "")
                    .replacingOccurrences(of: "_", with: "")
                    .lowercased()
                current.accessibilityIdentifier = "\(prefix).\(path).\(type)"
            }
            for (index, child) in current.subviews.enumerated() {
                visit(child, path: "\(path).\(index)")
            }
        }
        visit(self, path: "root")
    }
}
func column(_ views: [UIView] = [], spacing: CGFloat = 12) -> UIStackView {
    let stack = UIStackView(arrangedSubviews: views); stack.axis = .vertical; stack.spacing = spacing
    return stack
}
func row(_ views: [UIView], spacing: CGFloat = 8) -> UIStackView {
    let stack = UIStackView(arrangedSubviews: views); stack.spacing = spacing; stack.alignment = .center
    return stack
}
func card(_ views: [UIView], inset: CGFloat = 16, spacing: CGFloat = 12) -> UIView {
    let card = UIView(); card.backgroundColor = .white.withAlphaComponent(0.78); card.layer.cornerRadius = 18
    card.layer.borderWidth = 1; card.layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
    card.embed(column(views, spacing: spacing), inset: UIEdgeInsets(top: inset, left: inset, bottom: inset, right: inset))
    return card
}
func horizontalScroll(_ content: UIView, height: CGFloat = 44) -> UIScrollView {
    let scroll = UIScrollView(); scroll.showsHorizontalScrollIndicator = false
    scroll.addSubview(content); content.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
        content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
        content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
        content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
        content.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        scroll.heightAnchor.constraint(equalToConstant: height)
    ])
    return scroll
}
extension UIStackView {
    func clear() { arrangedSubviews.forEach { removeArrangedSubview($0); $0.removeFromSuperview() } }
}
final class AmbientView: UIView {
    private let gradient = CAGradientLayer()
    override init(frame: CGRect) {
        super.init(frame: frame)
        gradient.colors = [UIColor(hex: 0xF9F8FF).cgColor, UIColor(hex: 0xEFF8F7).cgColor, UIColor(hex: 0xEEE5FF).cgColor]
        gradient.startPoint = CGPoint(x: 0.1, y: 0); gradient.endPoint = CGPoint(x: 0.8, y: 1)
        layer.addSublayer(gradient)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() { super.layoutSubviews(); gradient.frame = bounds }
}
class ScreenController: UIViewController {
    let content = column(spacing: 18)
    let scroll = UIScrollView()
    let refresh = UIRefreshControl()
    let api = TradingAPI()
    private let pageName: String
    init(_ pageName: String) { self.pageName = pageName; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() { view = AmbientView() }
    override func viewDidLoad() {
        super.viewDidLoad()
        let brand = UIImageView(image: UIImage(named: "BrandMark")); brand.contentMode = .scaleAspectFit
        NSLayoutConstraint.activate([brand.widthAnchor.constraint(equalToConstant: 32), brand.heightAnchor.constraint(equalToConstant: 32)])
        let header = row([brand, Theme.label("TradingFlow", 18, weight: .semibold), UIView(), Theme.label(pageName, 10, weight: .bold, color: Theme.secondary)])
        let headerBox = UIView(); headerBox.backgroundColor = .white.withAlphaComponent(0.65)
        headerBox.embed(header, inset: UIEdgeInsets(top: 12, left: 20, bottom: 12, right: 20))
        view.addSubview(headerBox); view.addSubview(scroll)
        headerBox.translatesAutoresizingMaskIntoConstraints = false; scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content); content.translatesAutoresizingMaskIntoConstraints = false
        scroll.keyboardDismissMode = .interactive; scroll.showsVerticalScrollIndicator = false
        scroll.refreshControl = refresh; refresh.tintColor = Theme.green
        refresh.addAction(UIAction { [weak self] _ in self?.reload() }, for: .valueChanged)
        NSLayoutConstraint.activate([
            headerBox.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerBox.leadingAnchor.constraint(equalTo: view.leadingAnchor), headerBox.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: headerBox.bottomAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 12),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32)
        ])
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.assignMissingAccessibilityIdentifiers(prefix: "tradingflow.\(pageName.lowercased().replacingOccurrences(of: " ", with: ""))")
    }
    func reload() {}
    func state(_ stack: UIStackView, title: String, message: String, loading: Bool = false, retry: (() -> Void)? = nil) {
        stack.clear()
        let icon = Theme.icon(loading ? "arrow.triangle.2.circlepath" : "chart.line.uptrend.xyaxis", color: Theme.purple)
        var items: [UIView] = [row([icon, UIView()]), Theme.label(title, 18, weight: .semibold), Theme.label(message, 14, color: Theme.secondary)]
        if loading { let spinner = UIActivityIndicatorView(style: .medium); spinner.startAnimating(); items.append(spinner) }
        if let retry { items.append(Theme.button("Coba lagi", symbol: "arrow.clockwise", action: retry)) }
        stack.addArrangedSubview(card(items, inset: 20))
    }
    func showError(_ error: Error) {
        let alert = UIAlertController(title: "Belum berhasil", message: Display.error(error), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default)); present(alert, animated: true)
    }
    func share(_ items: [Any], from sender: UIView) {
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = sender; sheet.popoverPresentationController?.sourceRect = sender.bounds
        present(sheet, animated: true)
    }
}
