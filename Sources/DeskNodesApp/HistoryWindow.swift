import AppKit
import SwiftUI
import DeskNodesPersistence

/// Allocated only when History is requested; no scheduler or second database connection.
@MainActor
final class HistoryPresentation: ObservableObject {
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
    var daily: DailySnapshot? { snapshots.first { $0.day == selected } }
}

private enum HistoryColors {
    static let background = Color(nsColor: NoteTheme.dynamic("FBFAF8", "242321"))
    static let quiet = Color(nsColor: NoteTheme.dynamic("EFEDE8", "35332F"))
    static let selected = Color(nsColor: NoteTheme.dynamic("2F2C27", "EDEBE6"))
    static let selectedInk = Color(nsColor: NoteTheme.dynamic("FFFFFF", "242321"))
    static let progress = Color(nsColor: NoteTheme.dynamic("4F7A64", "8CB69D"))
    static let track = Color(nsColor: NoteTheme.dynamic("E4E1DA", "4D4942"))
    static let carryInk = Color(nsColor: NoteTheme.dynamic("6B5A2E", "E4CF8D"))
    static let carryFill = Color(nsColor: NoteTheme.dynamic("F3E9C9", "494025"))
}

@MainActor
struct HistoryView: View {
    @ObservedObject var model: HistoryPresentation
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    var body: some View {
        HStack(spacing: 0) {
            calendar.padding(.horizontal, 28).padding(.vertical, 24).frame(width: 400)
            Divider()
            detail.padding(.horizontal, 32).padding(.vertical, 24)
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
        let selected = day == model.selected
        let snapshot = model.snapshots.first { $0.day == day }
        let counts = HistoryCompletion(notes: snapshot?.notes ?? [])
        let ink = selected ? HistoryColors.selectedInk : Color(nsColor: NoteTheme.primary)
        return Button { model.selected = day } label: {
            VStack(spacing: 5) {
                Text(String(Int(day.rawValue.suffix(2))!))
                    .font(.system(size: 13, weight: selected || day == model.today ? .semibold : .regular))
                    .foregroundStyle(snapshot == nil && !selected ? Color.secondary : ink)
                ZStack(alignment: .leading) {
                    Capsule().fill(selected ? ink.opacity(0.25) : HistoryColors.track)
                    Capsule().fill(selected ? ink : HistoryColors.progress).frame(width: 22 * (counts.rate ?? 0))
                }.frame(width: 22, height: 3).opacity(counts.rate == nil ? 0 : 1)
            }.frame(maxWidth: .infinity).frame(height: 46)
                .background(selected ? HistoryColors.selected : todayFill(day), in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
            .accessibilityLabel("\(day.rawValue)，\(snapshot == nil ? "无历史记录" : "完成 \(counts.completed) / \(counts.total)")")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func todayFill(_ day: HistoryDay) -> Color {
        return day == model.today ? HistoryColors.quiet : .clear
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
                Text("当天没有历史记录").foregroundStyle(.secondary)
                Text("每日结束后保存快照；未记录的日期不会补造数据。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private func group(_ note: SnapshotNote) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Circle().fill(Color(nsColor: NoteTheme.background(note.color)))
                    .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1)).frame(width: 10, height: 10)
                Text(note.historyTitle).fontWeight(.semibold).lineLimit(2)
                if note.deletedAt != nil { badge("已删除", carry: false) }
            }.padding(.bottom, 4)
            ForEach(note.items, id: \.id) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(.secondary).frame(width: 14).padding(.top, 2)
                            .accessibilityLabel(item.completed ? "已完成" : "未完成")
                        Text(item.text.isEmpty ? "空白事项" : item.text)
                            .strikethrough(item.deletedAt != nil || note.deletedAt != nil)
                            .foregroundStyle(item.deletedAt != nil || note.deletedAt != nil ? Color.secondary : Color.primary)
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
