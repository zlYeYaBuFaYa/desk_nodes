#!/usr/bin/env python3
"""N8 history source/spec contracts only; no native SDK or screenshot claim."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
view = (root / 'Sources/DeskNodesApp/HistoryWindow.swift').read_text()
aux = (root / 'Sources/DeskNodesApp/AuxiliaryWindows.swift').read_text()
app = (root / 'Sources/DeskNodesApp/Application.swift').read_text()
store = (root / 'Sources/DeskNodesPersistence/Store.swift').read_text()
model = (root / 'Sources/DeskNodesPersistence/History.swift').read_text()
ui_spec = (root / 'docs/UI_SPEC.md').read_text()
count = 0
def check(value):
    global count
    assert value
    count += 1
for text in ['本月完成率', '已删除', '顺延到', '上个月', '下个月']:
    check(text in view + model)
for text in ['width: 400', 'height: 46', 'width: 22, height: 3', 'size: 20', 'size: 24', 'cornerRadius: 9', 'spacing: 18', '.horizontal, 28', '.horizontal, 32']:
    check(text in view)
for color in ['FBFAF8', 'EFEDE8', '2F2C27', '4F7A64', 'E4E1DA', '6B5A2E', 'F3E9C9']:
    check(color in view and color in ui_spec)
for text in ['ScrollView', 'LazyVStack', 'note.historyTitle', 'note.deletedAt', 'item.deletedAt', 'item.historyCarryLabel', 'HistoryCompletion(snapshots: model.snapshots)', 'counts.rate == nil ? 0 : 1', '当天没有历史记录', '无法读取历史记录']:
    check(text in view)
for text in ['TextField(', 'Toggle(', 'DatePicker(', 'Timer(', '.capture(', '.rollover(', 'WKWebView']:
    check(text not in view)
check('auxiliary.show(.history, store: actions?.store)' in app)
check('auxiliary.reloadHistoryIfVisible()' in app)
check('controllers[.history]?.window?.isVisible == true' in aux)
check('if destination == .history { history?.reload() }' in aux)
check('NSHostingController(rootView: HistoryView(model: history))' in aux)
check('window.isReleasedWhenClosed = false' in aux)
check('setActivationPolicy(.accessory)' in app)
check('applicationShouldTerminateAfterLastWindowClosed' in app)
read = store[store.index('public func history(in'):store.index('public func rolloverCheckpoint')]
check('SELECT day FROM days WHERE day>=? AND day<=? ORDER BY day' in read)
check('snapshot(day:' in read)
check('notes(' not in read and 'items(' not in read and 'capture(' not in read)
check('Double(completed) / Double(total)' in model)
check('items.filter(\\.completed).count' in model)
check('total == 0 ? nil' in model)
check('c.era == 1' in model)
print(f'N8 history source/spec contracts: {count} passed (not native API/runtime verification)')
