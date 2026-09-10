import UIKit

final class AccountController: ScreenController {
    private let signedOut: () -> Void
    private let profileContent = column(spacing: 16)
    private var task: Task<Void, Never>?

    init(signedOut: @escaping () -> Void) {
        self.signedOut = signedOut
        super.init("AKUN")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        content.addArrangedSubview(profileContent)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    override func reload() {
        task?.cancel()
        state(profileContent, title: "Memuat akun", message: "Mengambil informasi sesi Anda.", loading: true)
        task = Task { [weak self] in
            guard let self else { return }
            defer { refresh.endRefreshing() }
            do {
                let user = try await AuthStore.shared.profile()
                try Task.checkCancellation()
                render(user)
            } catch {
                guard !Task.isCancelled else { return }
                state(profileContent, title: "Profil belum termuat", message: error.localizedDescription, retry: { [weak self] in self?.reload() })
            }
        }
    }

    private func render(_ user: AuthUser) {
        profileContent.clear()
        let verified = user.emailConfirmedAt != nil
        let joined = Display.date(user.createdAt).map { date in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "id_ID")
            formatter.dateFormat = "MMMM yyyy"
            return "Bergabung sejak " + formatter.string(from: date)
        } ?? "Tanggal bergabung belum tersedia"
        profileContent.addArrangedSubview(card([
            row([
                column([Theme.label(user.displayName, 28, weight: .semibold),
                        Theme.label("ID: #\(user.id.prefix(8).uppercased())", 11, color: Theme.secondary, mono: true)], spacing: 4),
                UIView(),
                Theme.badge(verified ? "Terverifikasi" : "Belum terverifikasi", color: verified ? Theme.green : Theme.secondary,
                            background: verified ? Theme.mint : Theme.lavender)
            ]),
            row([Theme.icon("calendar", size: 30), Theme.label(joined, 13, color: Theme.secondary), UIView()]),
            Theme.label("Jenis akun: personal\nAkses API bergantung pada allowlist backend.", 12, color: Theme.secondary)
        ]))
        profileContent.addArrangedSubview(sectionTitle("INFORMASI AKUN", symbol: "person.text.rectangle"))
        profileContent.addArrangedSubview(card([
            accountRow("Alamat Email", value: user.email ?? "Belum tersedia", badge: verified ? "Terverifikasi" : "Belum dikonfirmasi"),
//            accountRow("User UID", value: user.id, mono: true),
            accountRow("Zona Waktu Pasar", value: "WIB (UTC+7) / EDT", symbol: "clock"),
            Theme.label("Data profil berasal dari Supabase Auth. Nomor telepon, preferensi riset, notifikasi, 2FA, Face ID, dan ubah kata sandi belum tersedia pada API V1.", 11, color: Theme.secondary)
        ]))
        profileContent.addArrangedSubview(sectionTitle("KEAMANAN SESI", symbol: "lock.shield"))
        profileContent.addArrangedSubview(card([
            accountRow("Sesi Tersimpan", value: "Keychain perangkat", symbol: "key.fill"),
            Theme.label("Access token diperbarui sekali saat kedaluwarsa atau API mengembalikan 401. Token tidak disimpan di UserDefaults.", 11, color: Theme.secondary)
        ]))
        let logout = Theme.button("Keluar dari Akun", symbol: "rectangle.portrait.and.arrow.right") { [weak self] in self?.logout() }
        logout.configuration?.baseForegroundColor = Theme.red
        logout.configuration?.baseBackgroundColor = .white
        profileContent.addArrangedSubview(logout)
        profileContent.addArrangedSubview(Theme.label("TradingFlow · sesi API Supabase terenkripsi di perangkat", 10, color: Theme.secondary, mono: true))
    }

    private func sectionTitle(_ text: String, symbol: String) -> UIView {
        row([UIImageView(image: UIImage(systemName: symbol)), Theme.label(text, 11, weight: .bold, color: Theme.secondary), UIView()])
    }

    private func accountRow(_ label: String, value: String, badge: String? = nil, symbol: String? = nil, mono: Bool = false) -> UIView {
        var leading: [UIView] = []
        if let symbol { leading.append(Theme.icon(symbol, size: 30)) }
        let body = column([Theme.label(label, 12, color: Theme.secondary), Theme.label(value, 14, weight: .medium, mono: mono)], spacing: 2)
        leading.append(body)
        leading.append(UIView())
        if let badge { leading.append(Theme.badge(badge, color: Theme.green, background: Theme.lavender)) }
        return row(leading)
    }

    private func logout() {
        let alert = UIAlertController(title: "Keluar dari akun?", message: "Sesi aman pada perangkat ini akan dihapus.", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Keluar", style: .destructive) { [weak self] _ in
            Task { await AuthStore.shared.signOut(); self?.signedOut() }
        })
        alert.addAction(UIAlertAction(title: "Batal", style: .cancel))
        alert.popoverPresentationController?.sourceView = view
        alert.popoverPresentationController?.sourceRect = view.bounds
        present(alert, animated: true)
    }
}
