# Glance untuk Intel dan macOS Sonoma 14.8.9

**Status: paket kode sumber yang telah disesuaikan. Belum dikompilasi dan belum diuji berjalan di macOS. Paket ini belum berisi aplikasi `.app` atau installer `.dmg` hasil modifikasi.**

## Hasil pemeriksaan aplikasi awal

File `Glance.dmg` yang diberikan sudah berisi kode Intel (`x86_64`) dan Apple Silicon (`arm64`). Aplikasi aslinya menetapkan minimum macOS **26.4** pada `Info.plist` dan pada executable Mach-O. Karena itu, mengedit angka pada `Info.plist` saja tidak menambahkan dukungan Sonoma.

Paket ini menggunakan kode sumber resmi [jonnyoo/glance](https://github.com/jonnyoo/glance) pada commit `295830146e334ec36e2b578aecde511672ab3c31`.

## Perubahan yang disiapkan

- Target kompilasi diubah menjadi macOS **14.8.9**, khusus Intel **x86_64**.
- Pengaturan jendela `defaultLaunchBehavior` dan `restorationBehavior` digunakan hanya pada macOS 15+. Pada Sonoma digunakan perilaku jendela standar; jendela Settings bisa muncul saat aplikasi dibuka. Pemulihan jendela dimatikan melalui AppKit.
- Animasi pergantian ikon kunci memakai pengganti yang tersedia di Sonoma.
- Ikon aplikasi menggunakan asset catalog biasa dari gambar ikon bawaan.
- Pembaruan otomatis upstream dinonaktifkan dan dependensi Sparkle dilepas, agar build Sonoma tidak diganti oleh aplikasi dengan kebutuhan macOS yang berbeda.
- Penandatanganan diatur sebagai build pribadi dengan tanda tangan lokal (ad-hoc). Entitlement kamera tetap digunakan; grup berbagi Keychain milik tim developer asli tidak diklaim oleh build ini.
- Tersedia script kompilasi, pemeriksaan executable, pembuatan DMG, dan alur GitHub Actions.

## Menghasilkan aplikasi

Kode sumber memakai fitur compiler Swift 6.2. Builder memerlukan **Xcode 26**, yang dijalankan pada Mac dengan macOS lebih baru. Contohnya, Xcode 26.3 memerlukan macOS 15.6 atau lebih baru. Hasil kompilasinya dapat ditargetkan ke macOS 14.8.9.

**Xcode 26 tidak dapat dijalankan langsung pada Mac Sonoma 14.8.9.** Menginstal Xcode 16.2 tidak cukup untuk kode sumber ini. Lihat [syarat resmi Xcode](https://developer.apple.com/xcode/system-requirements).

### Melalui GitHub Actions

Alur sudah disiapkan di `.github/workflows/build-sonoma.yml`. Untuk menjalankannya diperlukan repository GitHub milik Anda dan akses GitHub yang terhubung, atau unggahan paket secara manual.

1. Masukkan seluruh isi paket ke repository, termasuk `.github/workflows/build-sonoma.yml`, folder `glance`, folder `glance.xcodeproj`, dan folder `support`.
2. Buka **Actions → Build Glance for Sonoma Intel → Run workflow**.
3. Workflow memakai mesin **macos-15-intel** dan **Xcode 26.3**.
4. Jika kompilasi berhasil, unduh artifact **Glance-Sonoma-Intel-macOS14.8.9**. Isinya mencakup DMG dan laporan pemeriksaan paket.
5. Jika gagal, unduh **Glance-Sonoma-build-logs**. Log tersebut diperlukan untuk memperbaiki error kompilasi; source yang belum berhasil dikompilasi tidak boleh dianggap sudah kompatibel.

Workflow dapat dijalankan secara manual, dan berjalan otomatis saat perubahan kode atau konfigurasi build di-push ke `main`. Build memperlakukan warning Swift sebagai error dan menjalankan tes liveness yang sudah tersedia sebelum mengunggah DMG. Workflow menggunakan kuota GitHub Actions pada akun pemilik repository. [Dokumentasi runner GitHub](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).

### Melalui Mac lain yang memiliki Xcode 26

Di Terminal pada folder paket, gunakan Xcode yang sudah terpasang:

```bash
DEVELOPER_DIR=/Applications/Xcode_26.3.app/Contents/Developer bash support/build-sonoma.sh
```

Sesuaikan lokasi Xcode dengan instalasi pada Mac pembuat aplikasi. Setelah berhasil, hasil berada di:

```text
build/artifacts/Glance-Sonoma-Intel-macOS14.8.9.dmg
```

Script memeriksa arsitektur Intel, minimum macOS pada executable dan Info.plist, model Core ML, serta tanda tangan paket sebelum menghasilkan DMG.

## Batas hasil pemeriksaan saat paket ini dibuat

Pemeriksaan dilakukan pada lingkungan Linux. Perubahan konfigurasi dan kode telah diperiksa secara statis; **Xcode tidak tersedia, sehingga kompilasi aplikasi belum dilakukan**. Pengujian kamera, penyimpanan Keychain, pengenalan wajah, dan unlock layar pada **Mac Intel dengan macOS 14.8.9** juga belum dilakukan.

Build ad-hoc belum mempunyai notarization Apple. Jika berhasil dibangun, build ini masih perlu diuji di perangkat sebelum diandalkan. Integrasi overlay layar kunci menggunakan API privat macOS milik proyek awal dan masih harus diverifikasi pada Sonoma.

Setelah aplikasi berhasil dikompilasi, uji pembukaan Settings dan onboarding, izin kamera, pendaftaran wajah, penyimpanan kredensial melalui Keychain, serta penguncian dan pembukaan layar. Laporkan pesan error yang muncul agar penyebabnya dapat ditelusuri.

Lisensi dan atribusi proyek tersedia di `LICENSE`. Dokumentasi upstream asli disimpan di `UPSTREAM-README.md`.
