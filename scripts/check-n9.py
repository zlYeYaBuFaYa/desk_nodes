#!/usr/bin/env python3
"""N9 source/spec contracts; does not typecheck any macOS SDK or execute OS calls."""
from pathlib import Path
r = Path(__file__).resolve().parents[1]
def read(p): return (r / p).read_text()
app = read('Sources/DeskNodesApp/Application.swift')
settings = read('Sources/DeskNodesApp/SettingsWindow.swift')
services = read('Sources/DeskNodesApp/SystemServices.swift')
backup = read('Sources/DeskNodesPersistence/Backup.swift')
sqlite = read('Sources/DeskNodesPersistence/SQLite.swift')
card = read('Sources/DeskNodesApp/NotePanel.swift')
prototype = read('docs/UI_PROTOTYPE.html')
count = 0
def check(value):
    global count
    assert value
    count += 1
for label in ['通用', '停靠条', '边缘唤出', '快捷键', '数据', '每天跨天时间', '停靠位置', '显示在', '唤出边', '新建便签', '备份（JSON）', '导入…', '导出…']:
    check(label in settings and label in prototype)
for value in ['NSOpenPanel()', 'NSSavePanel()', 'Store.validateBackup', '.alertSecondButtonReturn', 'Data.write']:
    check(value in settings if value != 'Data.write' else 'data.write(to: url, options: .atomic)' in settings)
check(settings.index('Store.validateBackup') < settings.index('alert.messageText = "替换全部本机数据？"') < settings.index('try importBackup(backup)'))
check('.onChange(' not in settings) # Reload/import must not trigger preference writes.
check('displayedComponents: .hourAndMinute' in settings) # full 00:00-23:59 range via one 24-hour time field
check('无法读取 Dock 位置' in settings and '暂用主显示器' in settings)
for value in ['RegisterEventHotKey(', 'UnregisterEventHotKey(', 'InstallEventHandler(', 'RemoveEventHandler(', 'SMAppService.mainApp.register()', 'SMAppService.mainApp.unregister()', 'shouldAskForLogin', 'alert.runModal() == .alertSecondButtonReturn']:
    check(value in services)
check(services.index('guard try store.preferences().shouldAskForLogin') < services.index('let alert = NSAlert()'))
for value in ['invalidateAfterImport()', 'invalidateUndoAfterImport()', 'prepareForRemoval()', 'reloadHistoryIfVisible()', 'hasMarkedComposition', 'store.exportBackup', 'store.replace(with:', 'setActivationPolicy(.accessory)']:
    check(value in app)
check('globalHotkey?.stop()' in app)
check('guard !invalidated' in card and 'invalidated = true' in card)
for field in ['notes', 'items', 'history', 'settings', 'preferences', 'checkpoint', 'pendingNotes', 'pendingItems']:
    check(f'var {field}:' in backup)
for value in ['foreign_key_check', 'integrity_check', 'PRAGMA defer_foreign_keys=ON', 'confirmed', 'depth == 0', 'value.validate()', 'stage.exportBackup()']:
    check(value in backup)
check(backup.index('INSERT INTO snapshot_items') < backup.index('INSERT INTO days'))
for forbidden in ['DROP TRIGGER', 'writable_schema', 'foreign_keys=OFF', 'foreign_keys = OFF']:
    check(forbidden not in backup + sqlite)
for call in ['sqlite3_backup_init', 'sqlite3_backup_step', 'sqlite3_backup_finish']:
    check(call in sqlite)
for file in (r / 'Sources/DeskNodesPersistence').glob('*.swift'):
    for forbidden in ['import AppKit', 'import Carbon', 'import ServiceManagement', 'import SwiftUI']:
        check(forbidden not in file.read_text())
manifest = read('Package.swift')
check(manifest.index('#if os(macOS)') < manifest.index('.executableTarget'))
for file in (r / 'Sources/DeskNodesApp').glob('*.swift'):
    for forbidden in ['CGEventTapCreate', 'addGlobalMonitorForEvents', 'AXIsProcessTrusted', 'SMLoginItemSetEnabled', 'LaunchAgents/']:
        check(forbidden not in file.read_text())
print(f'N9 source/spec contracts: {count} passed (not SDK/runtime evidence)')
