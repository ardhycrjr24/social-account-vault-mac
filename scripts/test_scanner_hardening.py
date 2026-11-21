#!/usr/bin/env python3
"""
Phase 4.1 — Security Scanner Hardening regression tests (static scanner).

Exercises scripts/verify_code_integrity.py::check_security_invariants against
credential declarations that MUST be flagged and legitimate metadata/comments
that MUST NOT be flagged. Run: python3 scripts/test_scanner_hardening.py
Exit code 0 = all cases pass.
"""
import importlib.util
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("vci", os.path.join(HERE, "verify_code_integrity.py"))
assert spec is not None and spec.loader is not None, "cannot load verify_code_integrity.py"
vci = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vci)


def flagged(line: str) -> bool:
    with tempfile.NamedTemporaryFile("w", suffix=".swift", delete=False) as f:
        f.write(line + "\n")
        path = f.name
    try:
        return len(vci.check_security_invariants(path)) > 0
    finally:
        os.unlink(path)


# (declaration, must_be_flagged)
CASES = [
    # Whole-word credentials — MUST flag
    ("public var password: String", True),
    ("var token: String", True),
    ("var secret = x", True),
    ("var otp: String", True),
    ("var private_key: String", True),
    ("var passphrase: String", True),
    ("let password: String", True),
    # camelCase compounds — MUST flag
    ("public var accessToken: String", True),
    ("public var oauthSecret: String", True),
    ("public var otpSeed: String", True),
    ("public var privateKey: String", True),
    ("public var sessionToken: String", True),
    ("var refreshToken: String", True),
    ("var apiKey: ***", True),
    ("var recoveryCode: String", True),
    # snake_case compounds — MUST flag
    ("var access_token: String", True),
    ("var refresh_token: String", True),
    ("var api_key: String", True),
    ("var recovery_code: String", True),
    ("var session_cookie: String", True),
    ("var oauth_secret: String", True),
    # Uppercase / mixed-case — MUST flag
    ("VAR PASSWORD: String", True),
    ("Var AccessToken : String", True),
    ("var PRIVATE_KEY = x", True),
    ("var OAuthSecret: String", True),
    ("var ReCoVeRy_CoDe: String", True),
    ("var SESSION_TOKEN: String", True),
    # Legitimate metadata — MUST NOT flag
    ("public var passwordLastRotatedDate: Date?", False),
    ("var passwordLastRotatedDate: Date? = nil", False),
    ("public var twoFactorStatusRaw: String", False),
    ("public var twoFactorMethodRaw: String", False),
    ("public var recoveryEmailReference: String", False),
    ("public var recoveryPhoneHint: String", False),
    ("public var deviceOSRaw: String", False),
    ("public var primaryDeviceName: String", False),
    ("public var directLoginURLString: String", False),
    ("public var name: String", False),
    ("let twoFactorStatus: TwoFactorStatus = .unknown", False),
    # Comments / documentation — MUST NOT flag (no false positives)
    ("// var password: String (example)", False),
    ("/// var accessToken: String (doc example)", False),
    (" * var privateKey: String (block comment)", False),
    ("public var name: String // var password: ignored inline", False),
    ("// let sessionToken = \"x\"", False),
]


def main():
    passed = 0
    failed = 0
    print("=" * 70)
    print(" Security Scanner Hardening — Static Regression Tests")
    print("=" * 70)
    for line, expected in CASES:
        got = flagged(line)
        ok = got == expected
        if ok:
            passed += 1
            print(f"[PASS] expect_flag={expected!s:5} | {line}")
        else:
            failed += 1
            print(f"[FAIL] expect_flag={expected!s:5} got={got!s:5} | {line}")
    print("=" * 70)
    print(f" Summary: {passed} passed, {failed} failed (total {len(CASES)})")
    if failed:
        print("[FAIL] SCANNER HARDENING REGRESSION FAILED")
        sys.exit(1)
    print("[PASS] ALL SCANNER HARDENING REGRESSION TESTS PASSED")
    sys.exit(0)


if __name__ == "__main__":
    main()