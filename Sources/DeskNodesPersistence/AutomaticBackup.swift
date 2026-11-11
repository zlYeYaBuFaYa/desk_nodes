import Foundation

/// Daily rolling copies of the live database, written after a successful rollover.
/// Each copy is a complete SQLite file that can replace DeskNodes.sqlite3 while the app is quit.
public enum AutomaticBackup {
    public static let retained = 7

    public static func directory(fileManager: FileManager = .default) throws -> URL {
        let directory = try NativeStorage.databaseURL(fileManager: fileManager)
            .deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
                                       attributes: [.posixPermissions: 0o700])
        return directory
    }

    /// Writes `DeskNodes-<day>.sqlite3` once per day and keeps the newest `retained` copies.
    @discardableResult
    public static func write(_ store: Store, day: HistoryDay, to directory: URL,
                             fileManager: FileManager = .default) throws -> URL {
        let target = directory.appendingPathComponent("DeskNodes-\(day.rawValue).sqlite3")
        if !fileManager.fileExists(atPath: target.path) {
            let partial = directory.appendingPathComponent(".partial-\(UUID().uuidString).sqlite3")
            defer { try? fileManager.removeItem(at: partial) }
            try store.writeCopy(to: partial)
            try fileManager.moveItem(at: partial, to: target)
        }
        let copies = try fileManager.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("DeskNodes-") && $0.hasSuffix(".sqlite3") }.sorted()
        for name in copies.dropLast(retained) {
            try fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
        return target
    }
}
