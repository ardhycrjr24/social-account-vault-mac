#!/usr/bin/env python3
"""
Social Account Vault — Code Integrity & Phase 1 Compliance Verification
Runs static analysis and structural checks across Swift files, manifests, and documentation.
"""

import os
import re
import sys

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

def log(msg, status="INFO"):
    colors = {
        "INFO": "\033[0m",
        "PASS": "\033[32m",
        "FAIL": "\033[31m",
        "WARN": "\033[33m"
    }
    reset = "\033[0m"
    print(f"{colors.get(status, '')}[{status}] {msg}{reset}")

def check_file_exists(rel_path):
    full_path = os.path.join(PROJECT_ROOT, rel_path)
    if os.path.exists(full_path):
        log(f"Found required file: {rel_path}", "PASS")
        return True
    else:
        log(f"Missing required file: {rel_path}", "FAIL")
        return False

def check_balanced_delimiters(file_path):
    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Accurate state-machine lexer to ignore string literals and comments
    chars = []
    i = 0
    n = len(content)
    line_num = 1
    
    while i < n:
        # Track line numbers
        if content[i] == '\n':
            line_num += 1
            chars.append(('\n', line_num))
            i += 1
            continue

        # Single-line comment
        if i + 1 < n and content[i:i+2] == '//':
            while i < n and content[i] != '\n':
                i += 1
            continue

        # Multi-line comment
        if i + 1 < n and content[i:i+2] == '/*':
            i += 2
            while i + 1 < n and content[i:i+2] != '*/':
                if content[i] == '\n':
                    line_num += 1
                i += 1
            i += 2
            continue

        # Multi-line string literal """..."""
        if i + 2 < n and content[i:i+3] == '"""':
            i += 3
            while i + 2 < n and content[i:i+3] != '"""':
                if content[i] == '\n':
                    line_num += 1
                elif content[i] == '\\':
                    i += 1
                i += 1
            i += 3
            continue

        # Single-line string literal "..."
        if content[i] == '"':
            i += 1
            while i < n and content[i] != '"':
                if content[i] == '\\':
                    i += 1
                elif content[i] == '\n':
                    line_num += 1
                i += 1
            i += 1
            continue

        chars.append((content[i], line_num))
        i += 1

    pairs = {'{': '}', '(': ')', '[': ']'}
    stack = []
    
    for ch, line in chars:
        if ch in pairs.keys():
            stack.append((ch, line))
        elif ch in pairs.values():
            if not stack:
                return False, f"Unmatched closing '{ch}' near line {line}"
            open_ch, open_line = stack.pop()
            if pairs[open_ch] != ch:
                return False, f"Mismatched '{open_ch}' (line {open_line}) with '{ch}' (line {line})"

    if stack:
        open_ch, open_line = stack[-1]
        return False, f"Unclosed '{open_ch}' opened at line {open_line}"

    return True, "Balanced"

def check_security_invariants(file_path):
    """Ensure no passwords, tokens, recovery codes are stored in models.

    Hardened detection (Phase 4.1 Security Scanner Hardening):
    - Detects credential property declarations introduced by `var` or `let`.
    - Catches whole-word credentials (password, token, secret, otp, private_key),
      camelCase compounds (accessToken, oauthSecret, otpSeed, privateKey,
      sessionToken), snake_case compounds (access_token, private_key), and any
      letter-case variation (case-insensitive).
    - Preserves legitimate non-credential metadata: a rotation timestamp such as
      `passwordLastRotatedDate` is explicitly allowed and never flagged.
    - Ignores commented-out lines and documentation so examples in comments do
      not produce false positives.

    Detection works by extracting the declared identifier and splitting it into
    lowercase word components on camelCase boundaries and `_` separators, then
    checking whether any forbidden credential word appears as a whole component.
    An explicit allowlist exempts known-safe date/metadata identifiers.
    """
    with open(file_path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    # Forbidden credential words matched as whole identifier components.
    forbidden_words = {
        "password", "passphrase", "token", "oauth", "secret", "otp",
        "privatekey", "recoverycode", "sessioncookie", "apikey", "credential",
    }
    # Identifiers that are legitimate non-credential metadata and must never be
    # flagged even though they contain a forbidden word as a prefix/component.
    allowed_identifiers = {
        "passwordlastrotateddate",
    }

    # Match a property declaration: `var <identifier>` or `let <identifier>`.
    # Case-insensitive on the keyword so case variations (VAR/Var) are also caught.
    decl_re = re.compile(r"\b(?:var|let)\s+([A-Za-z_][A-Za-z0-9_]*)", re.IGNORECASE)

    def components(identifier):
        # Split camelCase / PascalCase boundaries and underscores into words.
        spaced = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", identifier)
        spaced = re.sub(r"([A-Z]+)([A-Z][a-z])", r"\1_\2", spaced)
        return [p.lower() for p in spaced.split("_") if p]

    def is_credential(identifier):
        lower = identifier.lower()
        if lower in allowed_identifiers:
            return False
        comps = components(identifier)
        # Whole-component match (e.g. accessToken -> [access, token]).
        if any(c in forbidden_words for c in comps):
            return True
        # Underscore-free compound match (e.g. privateKey -> privatekey).
        joined = "".join(comps)
        if joined in forbidden_words:
            return True
        return False

    violations = []
    for num, line in enumerate(lines, 1):
        stripped = line.strip()
        # Skip full-line comments and documentation markers.
        if stripped.startswith("//") or stripped.startswith("*") or stripped.startswith("///"):
            continue
        # Strip trailing inline comment before scanning declarations.
        code = line.split("//", 1)[0]
        for match in decl_re.finditer(code):
            identifier = match.group(1)
            if is_credential(identifier):
                violations.append((num, stripped))
                break

    return violations

def main():
    print("=" * 70)
    print(" Social Account Vault — Phase 2 Static Verification & Audit")
    print(f" Root: {PROJECT_ROOT}")
    print("=" * 70)

    total_checks = 0
    failures = 0

    # 1. Required Files Inventory
    required_files = [
        "Package.swift",
        "SocialAccountVault.xcodeproj/project.pbxproj",
        "SocialAccountVault.xcodeproj/xcshareddata/xcschemes/SocialAccountVault.xcscheme",
        "Sources/SocialAccountVaultApp/SocialAccountVaultApp.swift",
        "Sources/SocialAccountVaultCore/Models/VaultError.swift",
        "Sources/SocialAccountVaultCore/Models/Enums/NavigationItem.swift",
        "Sources/SocialAccountVaultCore/Models/Enums/PlatformType.swift",
        "Sources/SocialAccountVaultCore/Models/Enums/AccountStatus.swift",
        "Sources/SocialAccountVaultCore/Models/Enums/MonetizationStatus.swift",
        "Sources/SocialAccountVaultCore/Models/Enums/AccountType.swift",
        "Sources/SocialAccountVaultCore/Models/Account.swift",
        "Sources/SocialAccountVaultCore/Models/PlatformCategory.swift",
        "Sources/SocialAccountVaultCore/Models/AccountDetail.swift",
        "Sources/SocialAccountVaultCore/Models/ActivityLog.swift",
        "Sources/SocialAccountVaultCore/Services/Data/DatabaseConfiguration.swift",
        "Sources/SocialAccountVaultCore/Services/Data/CategorySeeder.swift",
        "Sources/SocialAccountVaultCore/Services/Data/VaultDataService.swift",
        "Sources/SocialAccountVaultCore/ViewModels/NavigationViewModel.swift",
        "Sources/SocialAccountVaultCore/Views/Navigation/SidebarView.swift",
        "Sources/SocialAccountVaultCore/Views/Navigation/MainNavigationView.swift",
        "Sources/SocialAccountVaultCore/Views/Dashboard/DashboardPlaceholderView.swift",
        "Sources/SocialAccountVaultCore/Views/Accounts/AccountsPlaceholderView.swift",
        "Sources/SocialAccountVaultCore/Views/Accounts/AddAccountView.swift",
        "Sources/SocialAccountVaultCore/Views/Accounts/AccountDetailView.swift",
        "Sources/SocialAccountVaultCore/Views/Archive/ArchivePlaceholderView.swift",
        "Sources/SocialAccountVaultCore/Views/Settings/SettingsPlaceholderView.swift",
        "Sources/SocialAccountVaultCore/Resources/Info.plist",
        "Sources/SocialAccountVaultCore/Resources/SocialAccountVault.entitlements",
        "Tests/SocialAccountVaultTests/NavigationTests.swift",
        "Tests/SocialAccountVaultTests/ModelFoundationTests.swift",
        "Tests/SocialAccountVaultTests/PersistenceTests.swift",
        "Tests/SocialAccountVaultTests/CategorySeederTests.swift",
        "Tests/SocialAccountVaultTests/SecurityInvariantTests.swift"
    ]

    print("\n--- 1. File Structure & Manifest Checks ---")
    for f in required_files:
        total_checks += 1
        if not check_file_exists(f):
            failures += 1

    # 2. Syntax & Delimiter Integrity
    print("\n--- 2. Swift Syntax & Delimiter Balance Checks ---")
    swift_files = []
    for root, _, files in os.walk(PROJECT_ROOT):
        for f in files:
            if f.endswith(".swift"):
                swift_files.append(os.path.join(root, f))

    for sf in sorted(swift_files):
        total_checks += 1
        rel = os.path.relpath(sf, PROJECT_ROOT)
        ok, reason = check_balanced_delimiters(sf)
        if ok:
            log(f"Delimiters balanced: {rel}", "PASS")
        else:
            log(f"Delimiter syntax error in {rel}: {reason}", "FAIL")
            failures += 1

    # 3. Strict Concurrency & Safety Checks
    print("\n--- 3. Swift 6 Strict Concurrency & Security Audit ---")
    for sf in sorted(swift_files):
        total_checks += 1
        rel = os.path.relpath(sf, PROJECT_ROOT)
        with open(sf, "r", encoding="utf-8") as f:
            content = f.read()

        # Check unchecked Sendable
        if "@unchecked Sendable" in content:
            log(f"Forbidden '@unchecked Sendable' detected in {rel}", "FAIL")
            failures += 1
        else:
            log(f"No '@unchecked Sendable' bypasses in {rel}", "PASS")

        # Check security invariant
        violations = check_security_invariants(sf)
        total_checks += 1
        if violations:
            for line_no, text in violations:
                log(f"Security invariant violation in {rel}:{line_no} -> {text}", "FAIL")
            failures += 1
        else:
            log(f"Security invariant satisfied (no credential fields) in {rel}", "PASS")

    # 4. Core Navigation & Categories Verification
    print("\n--- 4. Domain & Category Coverage ---")
    nav_file = os.path.join(PROJECT_ROOT, "Sources/SocialAccountVaultCore/Models/Enums/NavigationItem.swift")
    with open(nav_file, "r", encoding="utf-8") as f:
        nav_content = f.read()

    expected_navs = [
        "dashboard", "allAccounts", "youtube", "instagram", "tiktok", "facebook",
        "email", "affiliateMonetization", "websiteDomain", "archive", "settings"
    ]
    for nav in expected_navs:
        total_checks += 1
        if f"case {nav}" in nav_content:
            log(f"Navigation destination verified: {nav}", "PASS")
        else:
            log(f"Missing navigation destination: {nav}", "FAIL")
            failures += 1

    platform_file = os.path.join(PROJECT_ROOT, "Sources/SocialAccountVaultCore/Models/Enums/PlatformType.swift")
    with open(platform_file, "r", encoding="utf-8") as f:
        platform_content = f.read()

    expected_platforms = [
        "youtube", "instagram", "tiktok", "facebook", "email",
        "shopeeAffiliate", "googleAdSense", "websiteDomain"
    ]
    for plat in expected_platforms:
        total_checks += 1
        if f"case {plat}" in platform_content:
            log(f"Platform category verified: {plat}", "PASS")
        else:
            log(f"Missing platform category: {plat}", "FAIL")
            failures += 1

    print("\n--- 5. URL Safety: no unvalidated NSWorkspace.open ---")
    for sf in sorted(swift_files):
        total_checks += 1
        rel = os.path.relpath(sf, PROJECT_ROOT)
        with open(sf, "r", encoding="utf-8") as f:
            content = f.read()
        if "NSWorkspace.shared.open" not in content:
            log(f"No URL open call in {rel}", "PASS")
            continue
        safe = ("SafeLinkButton.swift" in rel or
                "URLSafetyValidator" in content or
                "decision.isOpenable" in content or
                "classify(" in content)
        if safe:
            log(f"URL open path is validator-backed in {rel}", "PASS")
        else:
            log(f"UNVALIDATED NSWorkspace.shared.open in {rel}", "FAIL")
            failures += 1

    print("\n" + "=" * 70)
    print(f" Summary: {total_checks} checks executed, {failures} failures.")
    if failures == 0:
        log("ALL STATIC AND STRUCTURAL AUDITS PASSED CLEANLY!", "PASS")
        print("=" * 70)
        sys.exit(0)
    else:
        log(f"AUDIT FAILED WITH {failures} ISSUES.", "FAIL")
        print("=" * 70)
        sys.exit(1)

if __name__ == "__main__":
    main()
