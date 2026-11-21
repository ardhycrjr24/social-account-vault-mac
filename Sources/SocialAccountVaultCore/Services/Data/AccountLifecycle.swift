import Foundation

/// Indikator masa berlaku domain. Murni informasi — tidak mengubah status akun.
public enum ExpirationBadge: Sendable, Equatable {
    case none          // tidak ada tanggal / archived / terlalu jauh
    case within90
    case within60
    case within30
    case expired

    public var displayText: String? {
        switch self {
        case .none: return nil
        case .within90: return "Kedaluwarsa dalam 90 hari"
        case .within60: return "Kedaluwarsa dalam 60 hari"
        case .within30: return "Kedaluwarsa dalam 30 hari"
        case .expired: return "Sudah kedaluwarsa"
        }
    }

    public var iconName: String {
        switch self {
        case .none: return "calendar"
        case .within90: return "calendar.badge.clock"
        case .within60: return "calendar.badge.exclamationmark"
        case .within30: return "exclamationmark.triangle"
        case .expired: return "xmark.octagon.fill"
        }
    }
}

/// Logika lifecycle akun berdasarkan tanggal acuan yang konsisten.
/// Tidak ada status baru — hanya turunan dari `domainExpirationDate` & `isArchived`.
public struct AccountLifecycle: Sendable {
    public init() {}

    /// Menghitung badge kedaluwarsa.
    /// - Params:
    ///   - expirationDate: tanggal kedaluwarsa domain (nil → none)
    ///   - isArchived: akun arsip TIDAK menghasilkan notifikasi aktif
    ///   - now: tanggal acuan (injectable untuk deterministic test)
    ///   - calendar: kalendar dengan timezone konsisten (default: current)
    ///
    /// Perbandingan memakai `startOfDay` untuk menghindari salah jam/timezone.
    public func expirationBadge(
        for expirationDate: Date?,
        isArchived: Bool,
        now: Date = Date(),
        calendar: Calendar = Calendar.current
    ) -> ExpirationBadge {
        guard !isArchived, let expirationDate else { return .none }

        let cal = calendar
        let startToday = cal.startOfDay(for: now)
        let startExpiration = cal.startOfDay(for: expirationDate)

        guard let days = cal.dateComponents([.day], from: startToday, to: startExpiration).day else {
            return .none
        }

        if days < 0 { return .expired }
        if days <= 30 { return .within30 }
        if days <= 60 { return .within60 }
        if days <= 90 { return .within90 }
        return .none
    }
}
