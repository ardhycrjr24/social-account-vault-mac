# Security Policy & Invariants — Social Account Vault

## 1. Core Security Model

Social Account Vault operates on a **zero-trust credential isolation model**. It is explicitly architected to manage account cataloging and metadata while completely excluding sensitive secrets.

---

## 2. Inviolable Security Rules

1. **Strictly Prohibited Data Fields:**
   The application database, data models, memory, logs, exports, and UI shall never prompt for, store, or serialize:
   - Account passwords or PINs.
   - One-Time Passwords (OTP) or 2FA secrets.
   - Account recovery codes or seed phrases.
   - Session cookies or local storage dumps.
   - OAuth access tokens or refresh tokens.
   - API keys or secret keys.

2. **Phase 2 Invariant Enforcement Mechanisms:**
   - **Prohibited Token Filter:** `AccountDetail.validate(...)` and `VaultDataService.addDetail(...)` inspect all metadata keys and values for forbidden tokens (`password`, `passphrase`, `oauth`, `token`, `secret`, `private_key`, `otp`, `2fa`, `recovery_code`, `session_cookie`). Any match immediately halts insertion and throws `VaultError.prohibitedCredentialStorage`.
   - **Length Boundary Guard:** 
     - Account name: 1 to 100 characters.
     - Username: 0 to 100 characters.
     - Metadata key: 1 to 100 characters.
     - Metadata value: 1 to 1,000 characters.
     - Notes: 0 to 5,000 characters.
     - Activity log details: 0 to 2,000 characters.

3. **Offline-First Operational Guarantee:**
   - 100% of core features (creation, querying, auditing, editing, filtering, backup, export) execute strictly offline.
   - No analytics SDKs, tracking pixels, or remote telemetry frameworks are embedded.
   - No background network connections or cloud synchronization engines are active in V1.

4. **External Browser Dispatch Safety:**
   - URL launching is delegated to macOS native `NSWorkspace.shared.open(...)`.
   - Semua URL divalidasi (hanya `https://`; skema berbahaya diblokir; host dicocokkan ke allowlist DomainRegistry) sebelum invocation.
   - No credentials or authentication headers are attached to launched URLs.
   - No headless browser injection or automated keystroke synthesis is permitted.

5. **macOS App Sandbox Compliance:**
   - Sandboxed under macOS App Sandbox (`com.apple.security.app-sandbox`).
   - Akses file dibatasi ke container Application Support standar. V1 TIDAK memakai akses file pilihan pengguna: entitlement `com.apple.security.files.user-selected.read-write` dan `com.apple.security.network.client` DIHAPUS karena export/import belum tersedia (Coming Soon) dan tidak ada API jaringan di source.
