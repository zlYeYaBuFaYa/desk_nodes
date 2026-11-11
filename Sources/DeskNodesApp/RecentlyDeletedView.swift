import AppKit
import SwiftUI
import DeskNodesPersistence

/// "最近删除": deleted notes and rows from the last 30 days, restorable with one click.
/// Restoring never edits sealed history; snapshots keep their 「已删除」 records.
@MainActor
struct RecentlyDeletedView: View {
    @ObservedObject var model: HistoryPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("最近删除").font(.system(size: 20, weight: .semibold))
                Text("删除的便签和事项保留 \(RecentlyDeleted.retentionDays) 天，可随时恢复；历史记录中的快照不受影响。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if let failure = model.deletedFailure {
                HStack {
                    Text(failure).foregroundStyle(.secondary).textSelection(.enabled)
                    Button("重试") { model.reloadDeleted() }
                }
            }
            if model.deleted.isEmpty && model.deletedFailure == nil {
                VStack(spacing: 8) {
                    Image(systemName: "trash").font(.system(size: 28)).foregroundStyle(.tertiary)
                    Text("最近 \(RecentlyDeleted.retentionDays) 天没有删除的内容").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if !model.deleted.notes.isEmpty {
                            section("便签", count: model.deleted.notes.count)
                            ForEach(model.deleted.notes, id: \.note.id) { noteCard($0) }
                        }
                        if !model.deleted.items.isEmpty {
                            section("事项", count: model.deleted.items.count)
                            VStack(spacing: 0) {
                                ForEach(Array(model.deleted.items.enumerated()), id: \.element.item.id) { index, entry in
                                    if index > 0 { Divider().padding(.leading, 38) }
                                    itemRow(entry)
                                }
                            }
                            .background(HistoryColors.quiet.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }.frame(maxWidth: 720, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 32).padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func section(_ title: String, count: Int) -> some View {
        Text("\(title) · \(count)").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
    }

    private func noteCard(_ entry: RecentlyDeleted.DeletedNote) -> some View {
        let title = DeletedText.noteTitle(entry.note, items: entry.items)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).fontWeight(.semibold).lineLimit(1)
                Spacer(minLength: 12)
                Button("恢复") { model.restore(.note(entry.note.id)) }
                    .accessibilityLabel("恢复便签：\(title)")
            }
            Text(DeletedText.meta(entry.note.deletedAt)).font(.system(size: 11)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(entry.items.prefix(4), id: \.id) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 2)
                            .accessibilityLabel(item.completed ? "已完成" : "未完成")
                        Text(item.text).lineLimit(1).foregroundStyle(item.completed ? .secondary : .primary)
                            .strikethrough(item.completed)
                    }
                }
                if entry.items.count > 4 {
                    Text("还有 \(entry.items.count - 4) 项").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                if entry.items.isEmpty { Text("没有事项").font(.system(size: 12)).foregroundStyle(.secondary) }
            }
        }
        .padding(14)
        .background(Color(nsColor: NoteTheme.background(entry.note.color)), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08)))
    }

    private func itemRow(_ entry: RecentlyDeleted.DeletedItem) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Circle().fill(Color(nsColor: NoteTheme.background(entry.note.color)))
                .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1)).frame(width: 10, height: 10)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.item.text).lineLimit(2)
                Text("来自「\(DeletedText.noteTitle(entry.note, items: []))」 · \(DeletedText.meta(entry.item.deletedAt))")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 12)
            Button("恢复") { model.restore(.item(entry.item.id)) }
                .help("恢复到原便签的末尾")
                .accessibilityLabel("恢复事项：\(entry.item.text)")
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }
}

enum DeletedText {
    static func noteTitle(_ note: Note, items: [Item]) -> String {
        if let title = note.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return title }
        return items.first?.text ?? "无标题便签"
    }
    /// "删除于 今天 14:32 · 30 天后移出列表"
    static func meta(_ deletedAt: Date?, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let deletedAt else { return "" }
        let time = DateFormatter(); time.calendar = calendar; time.timeZone = calendar.timeZone
        time.locale = Locale(identifier: "zh_CN"); time.dateFormat = "HH:mm"
        let day: String
        if calendar.isDate(deletedAt, inSameDayAs: now) { day = "今天" }
        else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(deletedAt, inSameDayAs: yesterday) { day = "昨天" }
        else {
            let date = DateFormatter(); date.calendar = calendar; date.timeZone = calendar.timeZone
            date.dateFormat = "M月d日"; day = date.string(from: deletedAt)
        }
        let elapsed = max(0, Int(now.timeIntervalSince(deletedAt) / 86_400))
        let left = max(1, RecentlyDeleted.retentionDays - elapsed)
        return "删除于 \(day) \(time.string(from: deletedAt)) · \(left) 天后移出列表"
    }
}
