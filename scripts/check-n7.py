#!/usr/bin/env python3
"""Source contracts only; never substitutes for SDK typechecking/native acceptance."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
app = root / 'Sources/DeskNodesApp'
reveal = (app / 'EdgeRevealController.swift').read_text()
application = (app / 'Application.swift').read_text()
card = (app / 'NotePanel.swift').read_text()
checks = 0
def check(value):
    global checks
    assert value
    checks += 1
check('NSEvent.mouseLocation' in reveal)
check('ProcessInfo.processInfo.systemUptime' in reveal)
check('[.borderless, .nonactivatingPanel]' in reveal)
check('[.canJoinAllSpaces, .fullScreenAuxiliary]' in reveal)
check('self.generation == token' in reveal)
check('accessibilityDisplayShouldReduceMotion' in reveal)
check('spring.duration = 0.30' in reveal)
check('UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation")' in reveal)
check('reveal?.hasMarkedComposition' in application)
check('try self.reveal?.flushEdits()' in application)
check('if self.hasMarkedComposition { return false }' in application)
check('window?.isKeyWindow == true && window?.firstResponder === row.editor' in card)
check('EditorSynchronization.receive' in card)
check('EditorSynchronization.flush' in card)
check('titleEditor.currentEditor()' in card)
check('hasMarkedText()' in card)
check('!hasMarkedComposition, actions?.prefersDeletionUndo' in application)
check('reveal?.refresh(notes)' in application)
check('undoClicked() { _ = restoreDeletion() }' in reveal)
check('restoreDeletion: { [weak self] in self?.undoDeletion() ?? false }' in application)
for path in app.glob('*.swift'):
    text = path.read_text()
    if path.name != 'EdgeRevealController.swift':
        check('.fullScreenAuxiliary' not in text)
    for forbidden in ['CGS', 'CGEventTapCreate', 'addGlobalMonitorForEvents', 'AXIsProcessTrusted', 'CGRequestListenEventAccess']:
        check(forbidden not in text)
for name in ['NotePanel.swift', 'DockController.swift', 'DeletionToast.swift']:
    check('.fullScreenNone' in (app / name).read_text())
print(f'N7 source contracts: {checks} passed (not native API/runtime verification)')
