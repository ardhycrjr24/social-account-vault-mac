import Foundation

/// Hasil validasi metadata/advisory. Bukan jaminan kebenaran data eksternal.
public enum MetadataValidation: Sendable, Equatable {
    case valid
    case invalid(reason: String)
    case warning(reason: String)
    case unknown(reason: String)

    public var isAccepted: Bool {
        switch self {
        case .invalid: return false
        case .valid, .warning, .unknown: return true
        }
    }

    public var reason: String? {
        switch self {
        case .valid: return nil
        case .invalid(let reason), .warning(let reason), .unknown(let reason): return reason
        }
    }
}

/// Validator metadata & recovery information pada service layer.
///
/// Prinsip:
/// - Format divalidasi HANYA untuk key yang aturannya disebut spesifikasi.
/// - Format yang belum ditentukan tidak ditolak, tetapi ditandai `unknown`.
/// - Tidak pernah mengubah nilai secara diam-diam.
/// - Pesan alasan tidak memuat data sensitif (email/nomor/identifier mentah).
public struct MetadataValidator: Sendable {
    public init() {}

    // MARK: - Platform Identifier

    /// Validasi identifier berdasarkan jenis `StandardMetadataKey`.
    public func validateIdentifier(_ value: String, for key: StandardMetadataKey) -> MetadataValidation {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .invalid(reason: "Identifier tidak boleh kosong")
        }

        switch key {
        case .youtubeChannelID:
            guard trimmed.hasPrefix("UC") else {
                return .invalid(reason: "YouTube Channel ID harus diawali 'UC'")
            }
            let suffix = trimmed.dropFirst(2)
            guard !suffix.isEmpty, suffix.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else {
                return .invalid(reason: "Format YouTube Channel ID tidak valid")
            }
            if trimmed.count != 24 {
                return .warning(reason: "Panjang YouTube Channel ID tidak lazim (umumnya 24 karakter)")
            }
            return .valid

        case .adsensePublisherID:
            guard trimmed.hasPrefix("pub-") else {
                return .invalid(reason: "Publisher ID harus diawali 'pub-'")
            }
            let suffix = trimmed.dropFirst(4)
            guard !suffix.isEmpty, suffix.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else {
                return .invalid(reason: "Format Publisher ID tidak valid")
            }
            return .valid

        case .payoutSchedule:
            let allowed = ["monthly", "net30", "biweekly"]
            guard allowed.contains(trimmed.lowercased()) else {
                return .invalid(reason: "Jadwal pembayaran harus monthly, net30, atau biweekly")
            }
            return .valid

        case .payoutCurrency:
            guard trimmed.count == 3, trimmed.allSatisfy({ $0.isUppercase }) else {
                return .invalid(reason: "Mata uang harus kode ISO 3 huruf kapital")
            }
            let common = ["USD", "IDR", "EUR", "SGD"]
            if !common.contains(trimmed) {
                return .warning(reason: "Kode mata uang di luar daftar umum spesifikasi")
            }
            return .valid

        default:
            // Spesifikasi tidak menentukan format untuk key lain — jangan
            // mengarang aturan atau menolak nilai yang belum dikenali.
            return .unknown(reason: "Format identifier untuk jenis metadata ini belum ditentukan spesifikasi")
        }
    }

    /// Validasi konsistensi kategori dengan key metadata.
    public func validateCategory(key: StandardMetadataKey, expected: MetadataCategory) -> MetadataValidation {
        let actual = key.category
        guard actual == expected else {
            return .invalid(reason: "Kategori metadata tidak sesuai dengan jenis key")
        }
        return .valid
    }

    /// Menerima key mentah dari UI; mengembalikan `.unknown` bila bukan key standar.
    public func resolveKey(_ rawValue: String) -> MetadataValidation {
        if StandardMetadataKey(rawValue: rawValue) != nil {
            return .valid
        }
        return .unknown(reason: "Key metadata bukan merupakan StandardMetadataKey")
    }

    // MARK: - Recovery Email

    /// Validasi format email recovery. Kosong diperbolehkan (field opsional).
    /// Tidak memverifikasi keberadaan/aktifitas email, dan tidak menyimpan kata sandi.
    public func validateRecoveryEmail(_ value: String) -> MetadataValidation {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .valid }
        guard trimmed.count <= 150 else {
            return .invalid(reason: "Email recovery terlalu panjang")
        }

        let pattern = #"^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$"#
        guard trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil else {
            return .invalid(reason: "Format email recovery tidak valid")
        }

        // Tolak nilai yang menyisipkan materi kredensial.
        let lowered = trimmed.lowercased()
        let blocked = ["password", "passphrase", "token", "secret", "otp", "private", "recovery_code", "apikey", "api_key"]
        if blocked.contains(where: { lowered.contains($0) }) {
            return .invalid(reason: "Email recovery mengandung kata yang dilarang")
        }
        return .valid
    }

    // MARK: - Password Rotation Date

    /// Validasi timestamp rotasi kata sandi: metadata historis saja.
    /// - `nil` diperbolehkan (field opsional).
    /// - Tanggal di masa depan DITOLAK (spec: `<= Date.now`).
    /// Tidak ada tanggal yang diubah/dibulatkan secara diam-diam.
    public func validatePasswordRotationDate(
        _ value: Date?,
        now: Date = Date()
    ) -> MetadataValidation {
        guard let value else { return .valid }
        guard value <= now else {
            return .invalid(reason: "Tanggal rotasi kata sandi tidak boleh di masa depan")
        }
        return .valid
    }

    // MARK: - Masked Recovery Phone

    /// Hanya menerima petunjuk nomor yang sudah dimasking.
    /// Aturan konsisten: bullet/asterisk + maksimal 4 digit tak tertutup.
    public func validateRecoveryPhoneHint(_ value: String) -> MetadataValidation {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .valid }

        let digits = trimmed.filter { $0.isNumber }
        if digits.count > 4 {
            return .invalid(reason: "Nomor telepon harus disamarkan menjadi maksimal 4 digit terakhir")
        }

        let hasMask = trimmed.contains("•") || trimmed.contains("*") || trimmed.contains("x")
        guard hasMask, digits.count == 4 else {
            return .invalid(reason: "Gunakan format petunjuk tersamar, misalnya •••• 8899")
        }
        return .valid
    }
}
