import Foundation
import DeskNodesCore

/// Distinct, UUID-backed identities. A deleted identity is never recycled.
public struct StableID<Kind>: Hashable, Codable, Sendable {
    public let rawValue: UUID
    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
}
public enum NoteIdentity: Sendable {}
public enum ItemIdentity: Sendable {}
public typealias NoteID = StableID<NoteIdentity>
public typealias ItemID = StableID<ItemIdentity>

public enum WindowLevel: String, Codable, Sendable { case desktop, ordinary, topmost }
public enum DockEdge: String, Codable, Sendable { case top, left, right }
public enum Placement: Equatable, Codable, Sendable {
    case dock(edge: DockEdge, displayID: String?)
    /// Screen coordinates in points; nil display means primary display preference.
    case free(displayID: String?, x: Double, y: Double, width: Double, height: Double)
}
public struct Note: Equatable, Sendable {
    public let id: NoteID
    public var title: String?
    public var color: NotePalette
    public var placement: Placement
    public var level: WindowLevel
    public var order: Int
    /// Last free placement survives docking, restart and deletion undo. Never a dock value.
    public var freeRestore: Placement? = nil
    public var automaticHeight: Bool = true
    public var collapsed: Bool
    public let createdAt: Date
    public internal(set) var updatedAt: Date
    public internal(set) var deletedAt: Date?
}
public struct Item: Equatable, Sendable {
    public let id: ItemID
    public let noteID: NoteID
    public var text: String
    public var completed: Bool
    public var order: Int
    /// Rollover archival is separate from user deletion; retained content is read-only.
    public internal(set) var archivedDay: HistoryDay? = nil
    public let createdAt: Date
    public internal(set) var updatedAt: Date
    public internal(set) var deletedAt: Date?
}
/// Singleton identity is fixed rather than regenerated on launch.
public enum EdgePreference: String, Sendable { case automatic, left, right }
public struct Settings: Equatable, Sendable {
    public let id = "native-settings"
    public var rolloverHour: Int = 4
    public var rolloverMinute: Int = 0
    public var edgePreference: EdgePreference = .automatic
    public var dockEdge: DockEdge = .top
    public var displayID: String? = nil
    public init() {}
}

/// Caller supplies a local civil day. No timezone, rollover or scheduler inference in N2.
public struct HistoryDay: Hashable, Comparable, Sendable {
    public let rawValue: String
    public init(_ value: String) throws {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              value.utf8.allSatisfy({ (48...57).contains($0) || $0 == 45 }),
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]), y > 0 else {
            throw StoreError.invalid("history day")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: y, month: m, day: d)
        guard let date = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day], from: date) == components else {
            throw StoreError.invalid("history day")
        }
        rawValue = value
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
public struct SnapshotItem: Equatable, Sendable {
    public let id: ItemID
    public let text: String
    public let completed: Bool
    public let order: Int
    public let deletedAt: Date?
    public let carriedTo: HistoryDay?
}
public struct SnapshotNote: Equatable, Sendable {
    public let id: NoteID
    public let title: String?
    public let color: NotePalette
    public let order: Int
    public let deletedAt: Date?
    public let items: [SnapshotItem]
}
public struct DailySnapshot: Equatable, Sendable {
    public let day: HistoryDay
    public let capturedAt: Date
    public let notes: [SnapshotNote]
}
public enum StoreError: Error, Equatable {
    case sqlite(code: Int32, message: String)
    case invalid(String)
    case notFound
    case unsupportedSchema(Int)
    case corrupt(String)
    case closed
}

public enum NativeStorage {
    /// Only explicit production callers use this path; test stores always supply their own URL.
    public static func databaseURL(fileManager: FileManager = .default) throws -> URL {
        let support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                          appropriateFor: nil, create: true)
        let directory = support.appendingPathComponent("local.desknodes.native", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
                                       attributes: [.posixPermissions: 0o700])
        return directory.appendingPathComponent("DeskNodes.sqlite3")
    }
}
