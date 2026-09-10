import UIKit

final class AuthRootController: UIViewController {
    private var isPresentingApp = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(hex: 0xFAF8FF)
        showLoading()
        Task { [weak self] in
            guard let self else { return }
            if await (try? AuthStore.shared.restoreSession()) != nil {
                await showAppIfAllowed()
            } else {
                showLogin()
            }
        }
    }

    private func showLoading() {
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.color = Theme.green
        spinner.startAnimating()
        view.embed(spinner)
    }

    private func replace(with controller: UIViewController) {
        children.forEach { $0.willMove(toParent: nil); $0.view.removeFromSuperview(); $0.removeFromParent() }
        addChild(controller)
        view.embed(controller.view)
        controller.didMove(toParent: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.assignMissingAccessibilityIdentifiers(prefix: "tradingflow.authentication")
    }

    private func showLogin() {
        isPresentingApp = false
        replace(with: LoginController(
            signedIn: { [weak self] in Task { await self?.showAppIfAllowed() } },
            showSignUp: { [weak self] in self?.showSignUp() }
        ))
    }

    private func showSignUp() {
        replace(with: SignUpController(
            signedIn: { [weak self] in Task { await self?.showAppIfAllowed() } },
            showLogin: { [weak self] in self?.showLogin() }
        ))
    }

    private func showAppIfAllowed() async {
        guard !isPresentingApp else { return }
        do {
            let _: Envelope<Market> = try await TradingAPI().get("market")
            isPresentingApp = true
            replace(with: ViewController(signOut: { [weak self] in self?.showLogin() }))
        } catch {
            await AuthStore.shared.clearSession()
            isPresentingApp = false
            showLogin()
            (children.first as? LoginController)?.showMessage(
                "Akun berhasil masuk, tetapi belum diizinkan memakai API. Tambahkan User UID ini ke AUTH_ALLOWED_USER_IDS di backend."
            )
        }
    }
}

private class AuthFormController: UIViewController {
    let content = UIStackView()
    let errorLabel = Theme.label("", 13, color: Theme.red)
    let activity = UIActivityIndicatorView(style: .medium)

    override func loadView() { view = AmbientView() }

    override func viewDidLoad() {
        super.viewDidLoad()
        let scroll = UIScrollView()
        scroll.keyboardDismissMode = .interactive
        scroll.showsVerticalScrollIndicator = false
        view.addSubview(scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .vertical
        content.spacing = 14
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 18),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -30),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40)
        ])
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true
        activity.hidesWhenStopped = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.assignMissingAccessibilityIdentifiers(prefix: "tradingflow.authentication.form")
    }

    func hero(_ title: String, subtitle: String) -> UIView {
        let brand = UIImageView(image: UIImage(named: "BrandMark"))
        brand.contentMode = .scaleAspectFit
        brand.backgroundColor = .white.withAlphaComponent(0.9)
        brand.layer.cornerRadius = 22
        brand.clipsToBounds = true
        NSLayoutConstraint.activate([brand.widthAnchor.constraint(equalToConstant: 80), brand.heightAnchor.constraint(equalToConstant: 80)])
        let brandRow = row([UIView(), brand, UIView()])
        let heading = Theme.label(title, 29, weight: .bold)
        heading.textAlignment = .center
        let detail = Theme.label(subtitle, 14, weight: .medium, color: UIColor(hex: 0x64748B))
        detail.textAlignment = .center
        return column([brandRow, heading, detail], spacing: 12)
    }

    func field(label: String, symbol: String, placeholder: String, password: Bool = false, contentType: UITextContentType? = nil) -> UITextField {
        let input = UITextField()
        input.placeholder = placeholder
        input.font = .systemFont(ofSize: 15)
        input.textColor = Theme.ink
        input.isSecureTextEntry = password
        input.textContentType = contentType
        input.autocorrectionType = .no
        input.autocapitalizationType = password || contentType == .emailAddress ? .none : .words
        input.backgroundColor = UIColor(hex: 0xF8FAFC).withAlphaComponent(0.85)
        input.layer.borderWidth = 1
        input.layer.borderColor = UIColor(hex: 0xE2E8F0).cgColor
        input.layer.cornerRadius = 12
        input.heightAnchor.constraint(equalToConstant: 48).isActive = true
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = Theme.secondary
        icon.contentMode = .scaleAspectFit
        let holder = UIView(frame: CGRect(x: 0, y: 0, width: 42, height: 48))
        icon.frame = CGRect(x: 14, y: 14, width: 18, height: 18)
        holder.addSubview(icon)
        input.leftView = holder
        input.leftViewMode = .always
        let section = column([
            row([Theme.label(label.uppercased(), 11, weight: .semibold, color: UIColor(hex: 0x64748B)), UIView()]),
            input
        ], spacing: 6)
        content.addArrangedSubview(section)
        return input
    }

    func showMessage(_ message: String) {
        errorLabel.text = message
        errorLabel.textColor = Theme.red
        errorLabel.isHidden = false
    }

    func showSuccess(_ message: String) {
        errorLabel.text = message
        errorLabel.textColor = Theme.green
        errorLabel.isHidden = false
    }

    func setLoading(_ loading: Bool, button: UIButton) {
        button.isEnabled = !loading
        loading ? activity.startAnimating() : activity.stopAnimating()
    }
}

private final class LoginController: AuthFormController {
    private enum EmailPreference {
        static let key = "rememberedLoginEmail"

        static var email: String? {
            get { UserDefaults.standard.string(forKey: key) }
            set {
                if let newValue, !newValue.isEmpty {
                    UserDefaults.standard.set(newValue, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        }
    }

    private let signedIn: () -> Void
    private let showSignUp: () -> Void
    private var email: UITextField!
    private var password: UITextField!
    private var submit: UIButton!
    private let rememberEmail = UISwitch()

    init(signedIn: @escaping () -> Void, showSignUp: @escaping () -> Void) {
        self.signedIn = signedIn
        self.showSignUp = showSignUp
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        content.addArrangedSubview(hero("Selamat Datang", subtitle: "Masuk ke dashboard riset pasar saham AS dan watchlist pribadi Anda."))
        content.addArrangedSubview(divider("MASUK DENGAN EMAIL"))
        let form = UIStackView()
        form.axis = .vertical
        form.spacing = 12
        let formCard = card([form], inset: 17, spacing: 0)
        content.addArrangedSubview(formCard)
        email = appendField(to: form, label: "Alamat Email", symbol: "envelope", placeholder: "nama@email.com", contentType: .emailAddress)
        email.accessibilityIdentifier = "auth.login.emailField"
        email.text = EmailPreference.email
        password = appendField(to: form, label: "Kata Sandi", symbol: "lock", placeholder: "Kata sandi", password: true, contentType: .password)
        password.accessibilityIdentifier = "auth.login.passwordField"
        rememberEmail.isOn = EmailPreference.email != nil
        rememberEmail.onTintColor = Theme.green
        rememberEmail.accessibilityIdentifier = "auth.login.rememberEmailSwitch"
        form.addArrangedSubview(row([
            Theme.label("Ingat alamat email", 13, weight: .medium, color: Theme.secondary),
            UIView(),
            rememberEmail
        ]))
        submit = Theme.button("Masuk ke Akun", symbol: "arrow.right", filled: true) { [weak self] in self?.login() }
        submit.accessibilityIdentifier = "auth.login.submitButton"
        form.addArrangedSubview(errorLabel)
        form.addArrangedSubview(row([submit, activity, UIView()]))
        let footer = Theme.button("Belum punya akun? Daftar Sekarang", symbol: "arrow.right") { [weak self] in self?.showSignUp() }
        footer.configuration?.baseBackgroundColor = .clear
        content.addArrangedSubview(footer)
        content.addArrangedSubview(Theme.label("Sesi disimpan aman di Keychain perangkat. Fitur lupa kata sandi belum tersedia.", 11, color: UIColor(hex: 0x94A3B8)))
    }

    private func appendField(to stack: UIStackView, label: String, symbol: String, placeholder: String, password: Bool = false, contentType: UITextContentType? = nil) -> UITextField {
        let input = UITextField()
        input.placeholder = placeholder; input.font = .systemFont(ofSize: 15); input.textColor = Theme.ink
        input.isSecureTextEntry = password; input.textContentType = contentType
        input.autocorrectionType = .no; input.autocapitalizationType = .none
        input.backgroundColor = UIColor(hex: 0xF8FAFC).withAlphaComponent(0.85)
        input.layer.borderWidth = 1; input.layer.borderColor = UIColor(hex: 0xE2E8F0).cgColor; input.layer.cornerRadius = 12
        input.heightAnchor.constraint(equalToConstant: 48).isActive = true
        let icon = UIImageView(image: UIImage(systemName: symbol)); icon.tintColor = Theme.secondary; icon.contentMode = .scaleAspectFit
        let holder = UIView(frame: CGRect(x: 0, y: 0, width: 42, height: 48)); icon.frame = CGRect(x: 14, y: 14, width: 18, height: 18); holder.addSubview(icon)
        input.leftView = holder; input.leftViewMode = .always
        stack.addArrangedSubview(column([Theme.label(label.uppercased(), 11, weight: .semibold, color: UIColor(hex: 0x64748B)), input], spacing: 6))
        return input
    }

    private func login() {
        view.endEditing(true)
        let address = email.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let secret = password.text ?? ""
        guard address.contains("@"), !secret.isEmpty else {
            showMessage("Masukkan alamat email dan kata sandi."); return
        }
        setLoading(true, button: submit)
        Task { [weak self] in
            guard let self else { return }
            defer { setLoading(false, button: submit) }
            do {
                _ = try await AuthStore.shared.signIn(email: address, password: secret)
                EmailPreference.email = rememberEmail.isOn ? address : nil
                signedIn()
            } catch {
                showMessage(error.localizedDescription)
            }
        }
    }
}

private final class SignUpController: AuthFormController {
    private let signedIn: () -> Void
    private let showLogin: () -> Void
    private var name: UITextField!
    private var email: UITextField!
    private var password: UITextField!
    private let acceptTerms = UISwitch()
    private var submit: UIButton!

    init(signedIn: @escaping () -> Void, showLogin: @escaping () -> Void) {
        self.signedIn = signedIn
        self.showLogin = showLogin
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        content.addArrangedSubview(hero("Buat Akun Baru", subtitle: "Akses analisis mendalam saham Wall Street dan watchlist pribadi Anda."))
        let form = column(spacing: 12)
        content.addArrangedSubview(card([form], inset: 17, spacing: 0))
        name = appendField(to: form, label: "Nama Lengkap", symbol: "person", placeholder: "cth. Reihan Pratama", contentType: .name)
        name.accessibilityIdentifier = "auth.signup.nameField"
        email = appendField(to: form, label: "Alamat Email", symbol: "envelope", placeholder: "nama@email.com", contentType: .emailAddress)
        email.accessibilityIdentifier = "auth.signup.emailField"
        password = appendField(to: form, label: "Kata Sandi", symbol: "lock", placeholder: "Minimal 8 karakter", password: true, contentType: .newPassword)
        password.accessibilityIdentifier = "auth.signup.passwordField"
        password.addAction(UIAction { [weak self] _ in self?.updateStrength() }, for: .editingChanged)
        let strength = UIProgressView(progressViewStyle: .bar)
        strength.progressTintColor = Theme.positive; strength.trackTintColor = Theme.lavender; strength.progress = 0
        strength.accessibilityLabel = "Kekuatan kata sandi"
        strength.accessibilityIdentifier = "auth.signup.passwordStrength"
        strength.tag = 77
        form.addArrangedSubview(column([row([Theme.label("Kekuatan Sandi", 12, color: Theme.secondary), UIView(), Theme.label("Gunakan 8+ karakter", 11, color: Theme.secondary)]), strength], spacing: 6))
        acceptTerms.onTintColor = Theme.green
        acceptTerms.accessibilityIdentifier = "auth.signup.acceptTermsSwitch"
        form.addArrangedSubview(row([acceptTerms, Theme.label("Saya menyetujui ketentuan layanan dan kebijakan privasi.", 12, color: Theme.secondary)]))
        submit = Theme.button("Daftar Sekarang", symbol: "paperplane.fill", filled: true) { [weak self] in self?.register() }
        submit.accessibilityIdentifier = "auth.signup.submitButton"
        form.addArrangedSubview(errorLabel)
        form.addArrangedSubview(row([submit, activity, UIView()]))
        let footer = Theme.button("Sudah memiliki akun? Masuk", symbol: "arrow.right") { [weak self] in self?.showLogin() }
        footer.configuration?.baseBackgroundColor = .clear
        content.addArrangedSubview(footer)
    }

    private func appendField(to stack: UIStackView, label: String, symbol: String, placeholder: String, password: Bool = false, contentType: UITextContentType? = nil) -> UITextField {
        let input = UITextField()
        input.placeholder = placeholder; input.font = .systemFont(ofSize: 15); input.textColor = Theme.ink
        input.isSecureTextEntry = password; input.textContentType = contentType
        input.autocorrectionType = .no; input.autocapitalizationType = contentType == .emailAddress ? .none : .words
        input.backgroundColor = UIColor(hex: 0xF8FAFC).withAlphaComponent(0.85)
        input.layer.borderWidth = 1; input.layer.borderColor = UIColor(hex: 0xE2E8F0).cgColor; input.layer.cornerRadius = 12
        input.heightAnchor.constraint(equalToConstant: 48).isActive = true
        let icon = UIImageView(image: UIImage(systemName: symbol)); icon.tintColor = Theme.secondary; icon.contentMode = .scaleAspectFit
        let holder = UIView(frame: CGRect(x: 0, y: 0, width: 42, height: 48)); icon.frame = CGRect(x: 14, y: 14, width: 18, height: 18); holder.addSubview(icon)
        input.leftView = holder; input.leftViewMode = .always
        stack.addArrangedSubview(column([Theme.label(label.uppercased(), 11, weight: .semibold, color: UIColor(hex: 0x64748B)), input], spacing: 6))
        return input
    }

    private func updateStrength() {
        let length = password.text?.count ?? 0
        let score: Float = length >= 12 ? 1 : length >= 8 ? 0.66 : length >= 5 ? 0.33 : 0
        (content.arrangedSubviews.compactMap { findProgress(in: $0) }.first)?.progress = score
    }

    private func findProgress(in view: UIView) -> UIProgressView? {
        if let progress = view as? UIProgressView, progress.tag == 77 { return progress }
        for child in view.subviews {
            if let progress = findProgress(in: child) { return progress }
        }
        return nil
    }

    private func register() {
        view.endEditing(true)
        let fullName = name.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let address = email.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let secret = password.text ?? ""
        guard fullName.count >= 2, address.contains("@"), secret.count >= 8 else {
            showMessage("Masukkan nama, email valid, dan kata sandi minimal 8 karakter."); return
        }
        guard acceptTerms.isOn else {
            showMessage("Setujui ketentuan layanan sebelum membuat akun."); return
        }
        setLoading(true, button: submit)
        Task { [weak self] in
            guard let self else { return }
            defer { setLoading(false, button: submit) }
            do {
                try await AuthStore.shared.signUp(name: fullName, email: address, password: secret)
                signedIn()
            } catch AuthError.emailConfirmationRequired {
                showSuccess("Akun dibuat. Periksa email untuk konfirmasi, lalu masuk.")
            } catch {
                showMessage(error.localizedDescription)
            }
        }
    }
}

private func divider(_ title: String) -> UIView {
    let left = UIView(); left.backgroundColor = UIColor(hex: 0xE2E8F0)
    let right = UIView(); right.backgroundColor = UIColor(hex: 0xE2E8F0)
    left.heightAnchor.constraint(equalToConstant: 1).isActive = true
    right.heightAnchor.constraint(equalToConstant: 1).isActive = true
    let stack = row([left, Theme.label(title, 11, weight: .semibold, color: UIColor(hex: 0x94A3B8)), right])
    left.widthAnchor.constraint(equalTo: right.widthAnchor).isActive = true
    return stack
}
