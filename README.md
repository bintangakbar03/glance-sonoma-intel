# Glance — Sonoma Intel source port

Target: **Intel x86_64, macOS Sonoma 14.8.9**.

**Status: source changes prepared; not compiled or runtime-tested.**
This archive does not contain a rebuilt application or installer.

Buka [MULAI-DI-SINI.md](MULAI-DI-SINI.md) untuk hasil pemeriksaan, perubahan,
panduan kompilasi, dan batas pengujian.

- macOS build script: `support/build-sonoma.sh`
- Manual GitHub Actions workflow: `.github/workflows/build-sonoma.yml`
- Built-package checks: `support/verify-built-app.py`
- Original project documentation: [UPSTREAM-README.md](UPSTREAM-README.md)
- License: [LICENSE](LICENSE)

The source requires Swift 6.2 / Xcode 26 on a compatible builder Mac.
The deployment target is the OS where the resulting application is intended to run.
