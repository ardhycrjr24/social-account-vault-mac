import Foundation
import SwiftData

/// Audit record tracking actions performed on an account (creation, edits, archiving, status verification).
@Model
public final class ActivityLog {
    public static let maxDetailsLength = 2000

    @Attribute(.unique)
    public var id: UUID
    public var actionType: String
    public var details: String
    public var timestamp: Date
    public var sequenceNumber: Int
    public var createdAt: Date
    public var updatedAt: Date

    public var account: Account?

    public init(
        id: UUID = UUID(),
        actionType: String,
        details: String = "",
        timestamp: Date = Date(),
        sequenceNumber: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        account: Account? = nil
    ) {
        self.id = id
        self.actionType = actionType
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDetails.count > Self.maxDetailsLength {
            self.details = String(trimmedDetails.prefix(Self.maxDetailsLength))
        } else {
            self.details = trimmedDetails
        }
        self.timestamp = timestamp
        self.sequenceNumber = sequenceNumber
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.account = account
    }
}
