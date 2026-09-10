# TradingFlow iOS

Aplikasi UIKit dari light mode Figma TradingFlow. Seluruh file Swift aplikasi berada langsung di folder utama target, tanpa pengelompokan subfolder.

## Jalankan

1. Salin `tradingflow-ios/Config/Secrets.xcconfig.example` menjadi `tradingflow-ios/Config/Secrets.xcconfig`.
2. Isi URL API, URL Supabase, dan Supabase publishable key pada file lokal tersebut.
3. Buka `tradingflow-ios/tradingflow-ios.xcodeproj`.
4. Pilih scheme `tradingflow-ios` dan iPhone Simulator, lalu Run.

Target minimum mengikuti proyek awal: iOS 26.5. Tidak ada dependency pihak ketiga.
Clone baru tidak memuat alamat maupun key lokal. Key Finnhub tetap berada di backend.

## Konfigurasi autentikasi

Isi `SUPABASE_URL` dan `SUPABASE_PUBLISHABLE_KEY` pada `Secrets.xcconfig` dengan konfigurasi proyek yang sama dengan runtime backend. Publishable key boleh digunakan oleh aplikasi client; jangan pernah memasukkan secret key, service-role key, Finnhub key, atau `LOCAL_API_TOKEN`.

Untuk pengembangan Simulator, Anda juga dapat memberi dua environment variable pada scheme:

    TRADINGFLOW_SUPABASE_URL=https://project.supabase.co
    TRADINGFLOW_SUPABASE_PUBLISHABLE_KEY=sb_publishable_...

Email/password memakai endpoint Supabase Auth, kemudian setiap permintaan TradingFlow mengirim access token lewat Authorization Bearer. Sesi disimpan di Keychain dan access token di-refresh sekali saat API mengembalikan 401. Sign out menghapus sesi lokal dan memanggil logout Supabase.

Sakelar **Ingat alamat email** menyimpan hanya alamat email di UserDefaults setelah login berhasil. Kata sandi, access token, refresh token, dan data sesi tidak pernah masuk ke UserDefaults.

## View Debugger

Setiap UIView aplikasi mendapat accessibilityIdentifier. Target interaktif autentikasi memakai identifier yang eksplisit, misalnya `auth.login.emailField`, `auth.login.passwordField`, `auth.login.submitButton`, dan `auth.signup.submitButton`. Komponen lain, termasuk kartu dan konten yang dirender dari API, memperoleh identifier deterministik dari layar, posisi hierarki, dan tipe UIView ketika layout berjalan.

Base URL diatur lewat `TRADINGFLOW_API_BASE_URL` pada `Secrets.xcconfig` atau environment variable `TRADINGFLOW_API_URL` pada scheme Xcode. Simulator dapat mengakses loopback Mac. Perangkat fisik membutuhkan backend yang dapat dijangkau dari perangkat; backend saat ini hanya mendengarkan loopback, sehingga mengganti URL saja tidak cukup. Gunakan tunnel HTTPS yang Anda kelola jika ingin menjalankan pada perangkat.

## Konfigurasi lokal dan secret

Konfigurasi lokal Xcode berada di `tradingflow-ios/Config/Secrets.xcconfig`. File tersebut diabaikan oleh Git. Untuk menyiapkan clone baru, salin `Secrets.xcconfig.example` menjadi `Secrets.xcconfig`, lalu isi `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, dan `TRADINGFLOW_API_BASE_URL`.

`SUPABASE_PUBLISHABLE_KEY` dapat digunakan oleh aplikasi client dan harus dilindungi oleh Row Level Security Supabase. Jangan pernah menaruh `SUPABASE_SERVICE_ROLE_KEY`, Finnhub API key, password database, private key, atau token deploy di proyek iOS; credential tersebut hanya boleh berada di backend atau secret manager deployment.

## Fitur

- Pasar: indeks, status sesi, pencarian dengan debounce dan pembatalan request lama, riwayat pencarian lokal.
- Watchlist: tambah dari detail saham, hapus lewat bintang, harga dan sparkline, pagination lima kartu per halaman.
- Filter Mega Cap dan Teknologi berlaku pada profil saham yang sudah dimuat; bukan screener seluruh pasar. Mega Cap membutuhkan kapitalisasi profil minimal US$200 miliar.
- Detail: harga dan waktu sumber, simpan/hapus, native share sheet, statistik, konsensus analis, berita saham.
- Grafik: Swift Charts milik Apple, ditanam menggunakan UIHostingController di UIKit. Mendukung 1D, 1W, 1M, 1Y, ALL, seleksi titik, harga, tanggal zona waktu bursa, dan volume.
- Berita: feed pasar, watchlist, earnings, makro, gambar dari API, artikel sumber dalam Safari, navigasi simbol terkait.
- Pull to refresh, loading, kosong, error/retry, data parsial, rate limit, dan penanda data demo. Nilai null tampil sebagai tanda pisah.
- UI light mode, SF Symbols, Dynamic Type, Auto Layout, dan native tab bar.
- Autentikasi: masuk, daftar email/password, konfirmasi email, pemulihan sesi, refresh token, sign out, dan tab Akun.

OAuth Apple/Google, lupa kata sandi, MFA/2FA, Face ID, telepon, edit profil, notifikasi, dan ubah kata sandi belum ditampilkan karena belum dikonfigurasi atau belum tersedia pada API V1. Tidak ada fallback diam-diam ke data contoh. Angka/grafik/berita berasal dari backend, bukan screenshot.

## Pemeriksaan kontrak API

APIContractCheck.swift memeriksa model Swift, unit statistik, tanggal RFC3339, data kosong/parsial, pencarian, mutasi watchlist, lima rentang grafik, analis, indeks, dan filter berita. Jalankan hanya dengan backend demo khusus pada port 8081, file watchlist terpisah, dan access token Supabase dari pengguna yang diizinkan backend.

Dari service-be:
    DATA_MODE=demo PORT=8081 WATCHLIST_FILE=/tmp/tradingflow-ios-test-watchlist.json go run .

Dari direktori ini:
    swiftc -module-cache-path /tmp/tradingflow-swift-cache -parse-as-library tradingflow-ios/tradingflow-ios/API.swift tradingflow-ios/tradingflow-ios/Authentication.swift APIContractCheck.swift -o /tmp/tradingflow-ios-contract-check
    TRADINGFLOW_TEST_ACCESS_TOKEN='access-token-pengguna-yang-diizinkan' \
    /tmp/tradingflow-ios-contract-check

Pemeriksaan menambah/menghapus AAPL pada backend demo khusus. Jangan arahkan backend pengujian ke file watchlist pribadi.
