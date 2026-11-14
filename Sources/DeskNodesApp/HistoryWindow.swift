import AppKit
import SwiftUI
import DeskNodesPersistence

enum HistoryMode: Hashable { case calendar, deleted }
enum DeletedTarget: Equatable { case note(NoteID), item(ItemID) }

/// Allocated only when History is requested; no scheduler or second database connection.
/// The calendar stays a read-only view of sealed snapshots; the recently-deleted list is
/// the only part that can change data, and it does so through injected app actions.
@MainActor
final class HistoryPresentation: ObservableObject {
    @Published var mode: HistoryMode = .calendar { didSet { if mode == .deleted { reloadDeleted() } } }
    @Published private(set) var deleted = RecentlyDeleted()
    @Published private(set) var deletedFailure: String?
    var loadDeleted: (() throws -> RecentlyDeleted)?
    var restoreDeleted: ((DeletedTarget) throws -> Void)?
    @Published private(set) var month: HistoryMonth
    @Published var selected: HistoryDay
    @Published private(set) var snapshots: [DailySnapshot] = []
    @Published private(set) var failure: String?
    @Published private(set) var today: HistoryDay
    private let store: Store

    init(store: Store, today: HistoryDay) {
        self.store = store
        self.today = today
        month = HistoryMonth(containing: today)
        selected = today
    }
    func reload() {
        do {
            today = try BusinessCalendar(timeZone: .current).day(at: Date(), settings: store.settings())
            snapshots = try store.history(in: month); failure = nil
        }
        catch { snapshots = []; failure = "无法读取历史记录：\(error)" }
    }
    func navigate(_ offset: Int) {
        guard let next = month.offset(offset) else { return }
        month = next; selected = next.first; reload()
    }
    /// Shows `day` selected, turning to its month when needed.
    func select(_ day: HistoryDay) {
        let target = HistoryMonth(containing: day)
        selected = day
        if target != month { month = target; reload() }
    }
    /// Arrow keys move the selection by days, never past today.
    func step(days: Int) {
        guard let next = selected.adding(days: days) else { return }
        select(min(next, today))
    }
    func showToday() { select(today) }
    var daily: DailySnapshot? { snapshots.first { $0.day == selected } }
    func reloadDeleted() {
        guard let loadDeleted else { return }
        do { deleted = try loadDeleted(); deletedFailure = nil }
        catch { deleted = RecentlyDeleted(); deletedFailure = "无法读取最近删除：\(error)" }
    }
    func restore(_ target: DeletedTarget) {
        do { try restoreDeleted?(target); deletedFailure = nil }
        catch StoreError.notFound { deletedFailure = nil } // already restored elsewhere (e.g. toast undo)
        catch { deletedFailure = "无法恢复：\(error)" }
        reloadDeleted(); reload()
    }
}

enum HistoryColors {
    static let progressInk = NoteTheme.dynamic("4F7A64", "8CB69D")
    static let trackInk = NoteTheme.dynamic("E4E1DA", "4D4942")
    static let background = Color(nsColor: NoteTheme.dynamic("FBFAF8", "242321"))
    static let quiet = Color(nsColor: NoteTheme.dynamic("EFEDE8", "35332F"))
    static let selected = Color(nsColor: NoteTheme.dynamic("2F2C27", "EDEBE6"))
    static let selectedInk = Color(nsColor: NoteTheme.dynamic("FFFFFF", "242321"))
    static let progress = Color(nsColor: progressInk)
    static let carryInk = Color(nsColor: NoteTheme.dynamic("6B5A2E", "E4CF8D"))
    static let carryFill = Color(nsColor: NoteTheme.dynamic("F3E9C9", "494025"))
    static func fill(_ heat: HistoryHeat) -> Color {
        switch heat {
        case .none: return .clear
        case .empty: return quiet
        case .low: return progress.opacity(0.18)
        case .mid: return progress.opacity(0.38)
        case .full: return progress.opacity(0.62)
        }
    }
}

/// One day in the status menu's 历史记录 submenu: its label, a small completion bar and
/// "done/total", the same numbers the calendar shows for that day.
enum HistoryMenuRow {
    /// "昨天 · 11月12日", "周三 · 11月11日" within the week, else "11月3日". Business days.
    static func label(_ day: HistoryDay, today: HistoryDay) -> String {
        if day.adding(days: 1) == today { return "昨天 · " + day.shortLabel }
        if let week = today.adding(days: -7), day > week { return day.weekdayLabel + " · " + day.shortLabel }
        return day.shortLabel
    }
    static func title(_ snapshot: DailySnapshot, today: HistoryDay) -> NSAttributedString {
        let counts = HistoryCompletion(notes: snapshot.notes)
        let font = NSFont.menuFont(ofSize: 0)
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: 236)]
        let title = NSMutableAttributedString(string: label(snapshot.day, today: today) + "\t",
                                              attributes: [.font: font, .paragraphStyle: paragraph])
        let bar = NSTextAttachment()
        bar.image = image(counts.rate)
        bar.bounds = CGRect(x: 0, y: (font.capHeight - 4) / 2, width: 28, height: 4)
        title.append(NSAttributedString(attachment: bar))
        title.append(NSAttributedString(string: "  \(counts.completed)/\(counts.total)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: font.pointSize - 1, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor]))
        return title
    }
    /// Drawn on demand, so it follows light and dark appearance.
    private static func image(_ rate: Double?) -> NSImage {
        NSImage(size: NSSize(width: 28, height: 4), flipped: false) { rect in
            HistoryColors.trackInk.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
            let done = NSRect(x: 0, y: 0, width: rect.width * CGFloat(rate ?? 0), height: rect.height)
            HistoryColors.progressInk.setFill()
            NSBezierPath(roundedRect: done, xRadius: 2, yRadius: 2).fill()
            return true
        }
    }
}

/// How full a day cell is tinted: by completion rate, so a month reads at a glance.
enum HistoryHeat: Equatable {
    /// No snapshot: the day was never sealed.
    case none
    /// Sealed, but nothing on it or nothing done.
    case empty
    case low, mid, full
    init(_ snapshot: DailySnapshot?) {
        guard let snapshot else { self = .none; return }
        guard let rate = HistoryCompletion(notes: snapshot.notes).rate, rate > 0 else { self = .empty; return }
        self = rate < 0.5 ? .low : rate < 1 ? .mid : .full
    }
}

@MainActor
struct HistoryView: View {
    @ObservedObject var model: HistoryPresentation
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    var body: some View {
        Group {
            if model.mode == .calendar {
                HStack(spacing: 0) {
                    calendar.padding(.horizontal, 28).padding(.vertical, 24).frame(width: 400)
                    Divider()
                    detail.padding(.horizontal, 32).padding(.vertical, 24)
                }
            } else {
                RecentlyDeletedView(model: model)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("视图", selection: $model.mode) {
                    Text("日历").tag(HistoryMode.calendar)
                    Text("最近删除").tag(HistoryMode.deleted)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 200)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            if model.mode == .deleted { model.reloadDeleted() }
        }
        .font(.system(size: 13)).monospacedDigit()
        .foregroundStyle(Color(nsColor: NoteTheme.primary))
        .background(HistoryColors.background)
        .frame(minWidth: 900, minHeight: 656)
    }
    private var calendar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(model.month.title).font(.system(size: 20, weight: .semibold))
                Spacer()
                Button { model.showToday() } label: {
                    Text("今天").font(.system(size: 12)).padding(.horizontal, 9).frame(height: 28)
                        .background(HistoryColors.quiet, in: RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain).disabled(model.selected == model.today).help("回到今天（⌘T）")
                navigation("chevron.left", label: "上个月", offset: -1)
                navigation("chevron.right", label: "下个月", offset: 1)
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) {
                    Text($0).font(.system(size: 11)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(model.month.cells.enumerated()), id: \.offset) { _, day in
                    if let day { dayCell(day) }
                    else { Color.clear.frame(height: 46).accessibilityHidden(true) }
                }
            }
            Spacer(minLength: 18)
            let counts = HistoryCompletion(snapshots: model.snapshots)
            VStack(alignment: .leading, spacing: 6) {
                Text("本月完成率").font(.system(size: 12)).foregroundStyle(.secondary)
                Text(counts.percentage).font(.system(size: 24, weight: .semibold))
                Text("共 \(counts.total) 项，完成 \(counts.completed) 项").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
    private func navigation(_ symbol: String, label: String, offset: Int) -> some View {
        Button { model.navigate(offset) } label: {
            Image(systemName: symbol).font(.system(size: 12)).frame(width: 28, height: 28)
                .background(HistoryColors.quiet, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).accessibilityLabel(label).disabled(model.month.offset(offset) == nil)
    }
    private func dayCell(_ day: HistoryDay) -> some View {
        let selected = day == model.selected, today = day == model.today
        let snapshot = model.snapshots.first { $0.day == day }
        let counts = HistoryCompletion(notes: snapshot?.notes ?? [])
        let ink = selected ? HistoryColors.selectedInk : Color(nsColor: NoteTheme.primary)
        return Button { model.selected = day } label: {
            Text(String(Int(day.rawValue.suffix(2))!))
                .font(.system(size: 13, weight: selected || today ? .semibold : .regular))
                .foregroundStyle(snapshot == nil && !selected ? Color.secondary : ink)
                .frame(maxWidth: .infinity).frame(height: 46)
                .overlay(alignment: .bottom) {
                    if today { Circle().fill(ink).frame(width: 4, height: 4).padding(.bottom, 6) }
                }
                .background(selected ? HistoryColors.selected : HistoryColors.fill(HistoryHeat(snapshot)),
                            in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
            .accessibilityLabel("\(day.rawValue)，\(snapshot == nil ? "无历史记录" : "完成 \(counts.completed) / \(counts.total)")")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private var detail: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.selected.detailLabel).font(.system(size: 20, weight: .semibold))
                Spacer()
                let counts = HistoryCompletion(notes: model.daily?.notes ?? [])
                Text("完成 \(counts.completed) / \(counts.total)").foregroundStyle(.secondary)
            }
            if let failure = model.failure {
                Text(failure).foregroundStyle(.secondary)
                Button("重试") { model.reload() }
            } else if let snapshot = model.daily {
                if snapshot.notes.isEmpty { Text("当天没有事项").foregroundStyle(.secondary) }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(snapshot.notes, id: \.id) { note in group(note) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.id(model.selected)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock").font(.system(size: 32)).foregroundStyle(.tertiary)
                    Text("当天没有历史记录").fontWeight(.semibold)
                    Text("每个业务日结束后保存快照；未记录的日期不会补造数据。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private func group(_ note: SnapshotNote) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // A header in the note's own colour, as it looked on the desk.
            HStack(spacing: 8) {
                Text(note.historyTitle).fontWeight(.semibold).lineLimit(1)
                if note.deletedAt != nil { badge("已删除", carry: false) }
                Spacer(minLength: 0)
            }.padding(.horizontal, 10).frame(height: 28)
                .background(Color(nsColor: NoteTheme.background(note.color)), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.primary.opacity(0.08)))
                .padding(.bottom, 4)
            ForEach(note.items, id: \.id) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(.secondary).frame(width: 14).padding(.top, 2)
                            .accessibilityLabel(item.completed ? "已完成" : item.struck ? "已划掉" : "未完成")
                        Text(item.text.isEmpty ? "空白事项" : item.text)
                            .strikethrough(item.struck || item.deletedAt != nil || note.deletedAt != nil)
                            .foregroundStyle(item.struck || item.deletedAt != nil || note.deletedAt != nil ? Color.secondary : Color.primary)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        if item.deletedAt != nil || note.deletedAt != nil { badge("已删除", carry: false) }
                        else if let label = item.historyCarryLabel(relativeTo: model.selected) {
                            badge(label, carry: true)
                        }
                        Spacer(minLength: 0)
                    }
                }.frame(minHeight: 28, alignment: .center).padding(.leading, 18)
            }
            if note.items.isEmpty { Text("没有事项").foregroundStyle(.secondary).padding(.leading, 18) }
        }
    }
    private func badge(_ text: String, carry: Bool) -> some View {
        Text(text).font(.system(size: 11))
            .foregroundStyle(carry ? HistoryColors.carryInk : Color.secondary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(carry ? HistoryColors.carryFill : HistoryColors.quiet, in: RoundedRectangle(cornerRadius: 4))
    }
}
