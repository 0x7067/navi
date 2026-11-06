import Foundation

/// What kind of capture an item holds. Every feature writes into the same Inbox.
public enum CaptureKind: String, Codable, Sendable {
    case text
    case image
    case screenshot
    case recording
    case dictation
}

/// One entry in the shared history list.
public struct CaptureItem: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var kind: CaptureKind
    /// First time this content was captured.
    public var createdAt: Date
    /// Last time this content was copied or pasted. The history is sorted by this.
    public var lastUsedAt: Date
    /// How many times this content was copied.
    public var copyCount: Int
    public var pinned: Bool
    /// Text content, for text and dictation items.
    public var text: String?
    /// File name inside the Inbox files folder, for images, screenshots, and recordings.
    public var fileName: String?
    /// Name of the app that was in front when the item was captured.
    public var sourceApp: String?
    /// Bundle ID of that app, used to show its icon.
    public var sourceBundleID: String?
    /// SHA-256 of the content. Used to find duplicates.
    public var contentHash: String
}

extension CaptureItem {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(CaptureKind.self, forKey: .kind)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt) ?? createdAt
        copyCount = try container.decodeIfPresent(Int.self, forKey: .copyCount) ?? 1
        pinned = try container.decode(Bool.self, forKey: .pinned)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName)
        sourceApp = try container.decodeIfPresent(String.self, forKey: .sourceApp)
        sourceBundleID = try container.decodeIfPresent(String.self, forKey: .sourceBundleID)
        contentHash = try container.decode(String.self, forKey: .contentHash)
    }
}
