# Personal Edition Release Notes — SocialAccountVault V1

**Edition:** V1 Personal Edition · **Date:** 2026-11-21 · **Branch:** `phase-4-development`

---

## 1. Product Positioning

- **SocialAccountVault V1 Personal Edition** adalah aplikasi macOS native untuk **penggunaan pribadi lokal** pada Mac pemilik proyek.
- UI direction: **dark-only** (`preferredColorScheme(.dark)`); Light Appearance berada di luar scope V1.
- Prinsip inti: **Zero-Credential Storage** — tidak menyimpan password, OTP/seed, recovery code, private key, session token, atau API secret.

## 2. Signing & Distribution (saat ini)

- **Ad-hoc signing** dipakai untuk penggunaan/pengembangan lokal.
- **Tidak** memerlukan Developer ID saat ini.
- **Tidak** ada pipeline notarisasi.
- **Tidak** ada distribusi DMG publik.
- **Tidak** ada rilis GitHub publik.
- Distribusi publik masa depan membutuhkan **fase persiapan terpisah** (lihat §4).

## 3. Current Technical Baseline

- **Swift 6** (strict concurrency complete) · **macOS minimum 14** · SwiftUI + SwiftData + AppKit.
- **Xcode Release build** dan **Archive** terverifikasi (smoke launch archive & release app PASS).
- **App Sandbox** aktif (hanya `com.apple.security.app-sandbox` yang dipertahankan).
- Zero-Credential Storage terjaga; storage failure menolak tulis + banner, file DB tetap utuh.
- DomainRegistry: 4 root terverifikasi (youtube.com, instagram.com, facebook.com, tiktok.com).

## 4. Deferred Public Distribution (future phase — NOT completed)

Hal-hal berikut **belum** diselesaikan dan sengaja ditunda:

- Apple Developer Program.
- Developer ID signing.
- Hardened Runtime (distribution configuration).
- Notarization.
- DMG packaging.
- Gatekeeper validation (`spctl`).
- Public release process.

## 5. Known Limitations Register

1. **Final App Icon** belum tersedia (build setting mengarah ke `AppIcon`; asset belum dibuat).
2. **QA visual/interaksi manual Dark Appearance** masih outstanding (memerlukan sesi GUI interaktif).
3. **Light Appearance** di luar scope V1 (dark-only adalah keputusan produk).
4. **Leaks trace** melaporkan **413 temuan berorigin framework sistem** (Foundation/LinkServices/AppIntents), **nol** dikaitkan ke kode aplikasi, pada sesi yang diuji.
5. Hasil Instruments **terbatas pada skenario yang diuji** (launch idle; navigasi manual belum dicakup).
6. **Tidak ada checksum pra-insiden database**; kesetaraan byte-for-byte historis tak dapat dibuktikan.
7. Deteksi **redirect/shortener lintas-domain** ditunda ke **V1.1** (AC-MOD8-4, PARTIAL).
8. **AC-MOD2-2** (advisory platform detection) tetap **FAIL** historis, ditunda ke V1.1.
9. **MOD5-3** dan **MOD6-3** tetap **PARTIAL**.
10. **Export JSON/CSV & backup database** tetap **tidak tersedia di V1** (UI "Coming Soon", tanpa action handler).

---
Catatan: dokumen ini mencerminkan status terverifikasi per TASK 12.7–12.7.3 & 12.8.1; hasil historis AC tidak direklasifikasi.
