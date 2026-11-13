import Foundation

/// Civil month keys never reinterpret sealed day strings in the current timezone.
public struct HistoryMonth: Equatable, Sendable {
    public let first: HistoryDay
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }
    public init(containing day: HistoryDay) {
        first = try! HistoryDay(String(day.rawValue.prefix(7)) + "-01")
    }
    private var date: Date {
        let p = first.rawValue.split(separator: "-").map { Int($0)! }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: 1))!
    }
    public var title: String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return "\(c.year!)年\(c.month!)月"
    }
    public var days: [HistoryDay] {
        (1...calendar.range(of: .day, in: .month, for: date)!.count).map {
            try! HistoryDay(String(first.rawValue.prefix(8)) + String(format: "%02d", $0))
        }
    }
    /// Monday-first grid, padded to whole weeks (including six-week months).
    public var cells: [HistoryDay?] {
        let leading = (calendar.component(.weekday, from: date) + 5) % 7
        var result = Array<HistoryDay?>(repeating: nil, count: leading) + days.map(Optional.some)
        result += Array(repeating: nil, count: (7 - result.count % 7) % 7)
        return result
    }
    public func offset(_ months: Int) -> HistoryMonth? {
        guard let next = calendar.date(byAdding: .month, value: months, to: date) else { return nil }
        let c = calendar.dateComponents([.era, .year, .month], from: next)
        guard c.era == 1, let y = c.year, let m = c.month, (1...9999).contains(y),
              let key = try? HistoryDay(String(format: "%04d-%02d-01", y, m)) else { return nil }
        return HistoryMonth(containing: key)
    }
}

/// Every recorded item occurrence is in the denominator, including tombstones, except
/// struck-out items, which were dropped rather than left undone.
/// Completion is only the frozen flag: deletion, carry and archive never imply completion.
public struct HistoryCompletion: Equatable, Sendable {
    public let completed: Int
    public let total: Int
    public init(notes: [SnapshotNote]) {
        let items = notes.flatMap(\.items).filter { !$0.struck }
        total = items.count
        completed = items.filter(\.completed).count
    }
    public init(snapshots: [DailySnapshot]) { self.init(notes: snapshots.flatMap(\.notes)) }
    public var rate: Double? { total == 0 ? nil : Double(completed) / Double(total) }
    public var percentage: String { rate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—" }
}

public extension HistoryDay {
    var shortLabel: String {
        let parts = rawValue.split(separator: "-")
        return "\(Int(parts[1])!)月\(Int(parts[2])!)日"
    }
    var detailLabel: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let p = rawValue.split(separator: "-").map { Int($0)! }
        let date = calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))!
        return shortLabel + " 周" + ["日", "一", "二", "三", "四", "五", "六"][calendar.component(.weekday, from: date) - 1]
    }
}
public extension SnapshotNote {
    var historyTitle: String {
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return title }
        return items.first(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.text ?? "无标题便签"
    }
}

public extension SnapshotItem {
    func historyCarryLabel(relativeTo source: HistoryDay) -> String? {
        guard let target = carriedTo else { return nil }
        let label = target.rawValue.prefix(4) == source.rawValue.prefix(4) ? target.shortLabel : target.rawValue
        return "顺延到 \(label)"
    }
}
