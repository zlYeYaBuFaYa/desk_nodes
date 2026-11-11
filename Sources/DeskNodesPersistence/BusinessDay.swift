import Foundation

/// Gregorian civil dates, with a wall-clock boundary in an injected timezone.
/// A missing DST time uses the next valid time; a repeated time uses its first occurrence.
public struct BusinessCalendar {
    public let calendar: Calendar
    public init(timeZone: TimeZone, calendar: Calendar = Calendar(identifier: .gregorian)) throws {
        guard calendar.identifier == .gregorian else { throw StoreError.invalid("Gregorian calendar required") }
        var value = calendar; value.timeZone = timeZone
        self.calendar = value
    }
    public func day(at instant: Date, settings: Settings) throws -> HistoryDay {
        guard instant.timeIntervalSince1970.isFinite,
              (0...23).contains(settings.rolloverHour), (0...59).contains(settings.rolloverMinute) else {
            throw StoreError.invalid("business clock/boundary")
        }
        let start = calendar.startOfDay(for: instant)
        guard let boundary = calendar.nextDate(after: start.addingTimeInterval(-1),
            matching: DateComponents(hour: settings.rolloverHour, minute: settings.rolloverMinute, second: 0),
            matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward),
              let previous = calendar.date(byAdding: .day, value: -1, to: start) else {
            throw StoreError.invalid("business date")
        }
        return try civilDay(instant < boundary ? previous : start)
    }
    private func civilDay(_ instant: Date) throws -> HistoryDay {
        let c = calendar.dateComponents([.year, .month, .day], from: instant)
        guard let y = c.year, let m = c.month, let d = c.day else { throw StoreError.invalid("civil date") }
        return try HistoryDay(String(format: "%04d-%02d-%02d", y, m, d))
    }
}

public struct RolloverCheckpoint: Equatable, Sendable {
    public let activeDay: HistoryDay
    public let highWater: Date
}
public enum RolloverResult: Equatable, Sendable {
    case initialized(HistoryDay)
    case deferredEditing
    case unchanged
    case heldForClockReversal
    case advanced(DailySnapshot)
}
