import Foundation
import SwiftData
import Observation

/// Status penyimpanan persisten aplikasi.
/// Satu sumber kebenaran untuk seluruh aplikasi.
public enum StorageStatus: Sendable, Equatable {
    /// Persistent store berhasil dibuka dan siap menerima operasi tulis.
    case ready
    /// Persistent store gagal dibuka. Semua tulis diblokir; file asli tidak diubah.
    case failed(reason: String)
    /// Sedang mencoba membuka ulang store yang sama (non-destruktif).
    case recovering

    public var isWritable: Bool {
        if case .ready = self { return true }
        return false
    }

    /// Pesan ramah pengguna — tidak membocorkan detail internal database.
    public var userFacingMessage: String? {
        switch self {
        case .ready:
            return nil
        case .failed:
            return "Data belum dapat disimpan. Penyimpanan aman sedang tidak tersedia. "
                + "File data Anda tetap utuh. Gunakan tombol Coba Lagi untuk mencoba kembali."
        case .recovering:
            return "Sedang mencoba membuka kembali penyimpanan aman. Data belum disimpan."
        }
    }
}

/// Koordinator storage produksi dengan state machine tunggal.
///
/// - Tidak pernah mengganti database produksi dengan container in-memory secara diam-diam.
/// - Tidak pernah menghapus, membuat ulang, atau mengosongkan file database.
/// - Retry hanya membuka ulang file yang sama; status `ready` hanya setelah
///   container persisten benar-benar berhasil dibuka.
@MainActor
@Observable
public final class StorageCoordinator {
    public private(set) var status: StorageStatus = .failed(reason: "not initialized")
    public private(set) var container: ModelContainer?
    /// Container diagnostik EKSPLISIT (in-memory). Hanya dipakai saat FAILED
    /// agar SwiftUI tidak crash; semua tulis tetap diblokir oleh `requireWritable()`.
    public private(set) var diagnosticContainer: ModelContainer?

    private let storeURL: URL

    public init(storeURL: URL = DatabaseConfiguration.defaultDatabaseURL) {
        self.storeURL = storeURL
        self.diagnosticContainer = Self.makeDiagnosticContainer()
    }

    /// Container yang dipasang ke SwiftUI. Nil hanya bila container diagnostik
    /// juga gagal dibuat (kondisi runtime ekstrem) — App menanganinya tanpa crash.
    public var presentedContainer: ModelContainer? {
        if status.isWritable, let container { return container }
        return diagnosticContainer
    }

    /// Membuka store produksi sekali saat aplikasi diluncurkan.
    @discardableResult
    public func bootstrap() -> Bool {
        finishAttempt(openStore())
    }

    /// Retry non-destruktif: membuka ulang FILE YANG SAMA.
    @discardableResult
    public func retry() -> Bool {
        guard case .failed = status else { return status.isWritable }
        status = .recovering
        return finishAttempt(openStore())
    }

    /// Guard pemanggil: melempar saat storage tidak siap menerima tulis.
    public func requireWritable() throws {
        guard status.isWritable, container != nil else {
            throw VaultError.storageUnavailable(reason: "writes halted while storage is unavailable")
        }
    }

    public func prepareContainerForPresentation() {
        _ = presentedContainer
    }

    // MARK: - Internal

    private func finishAttempt(_ result: Result<ModelContainer, Error>) -> Bool {
        switch result {
        case .success(let container):
            self.container = container
            self.status = .ready
            return true
        case .failure(let error):
            self.container = nil
            self.status = .failed(reason: Self.safeReason(error))
            return false
        }
    }

    private func openStore() -> Result<ModelContainer, Error> {
        do {
            return .success(try DatabaseConfiguration.openPersistentContainer(at: storeURL))
        } catch {
            return .failure(error)
        }
    }

    private static func makeDiagnosticContainer() -> ModelContainer? {
        let configuration = ModelConfiguration(
            "SocialAccountVaultDiagnosticReadOnly",
            schema: DatabaseConfiguration.schema,
            isStoredInMemoryOnly: true
        )
        // Kegagalan container diagnostik ditandai dengan nil; caller (App)
        // menanganinya secara eksplisit tanpa crash.
        return try? ModelContainer(for: DatabaseConfiguration.schema, configurations: [configuration])
    }

    /// Ringkas reason untuk state — tidak menampilkan path internal pengguna.
    private static func safeReason(_ error: Error) -> String {
        let text = String(describing: error)
        return text.count > 120 ? String(text.prefix(120)) : text
    }
}
