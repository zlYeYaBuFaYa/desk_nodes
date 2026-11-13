#!/usr/bin/env python3
"""Source contracts only; never substitutes for SDK typechecking/native acceptance."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
app = root / 'Sources/DeskNodesApp'
desk = (app / 'Desk.swift').read_text()
application = (app / 'Application.swift').read_text()
card = (app / 'NotePanel.swift').read_text()
checks = 0
def check(value):
    global checks
    assert value
    checks += 1
# 浮起 lifts the real note windows; there is no second copy of any note.
check(not (app / 'EdgeRevealController.swift').exists())
check('modes.peek = peeking' in desk)
check('if peek { return .topmost }' in (root / 'Sources/DeskNodesActions/WindowState.swift').read_text())
# Leaving is Esc inside DeskNodes or switching apps; never a global event monitor.
check('NSEvent.addLocalMonitorForEvents(matching: .keyDown)' in application)
check('NSApplication.didResignActiveNotification' in application)
check('surfaces?.hasMarkedComposition == true' in application)
check('try self.surfaces?.flushEdits()' in application)
check('if self.hasMarkedComposition { return false }' in application)
check('window?.isKeyWindow == true && window?.firstResponder === row.editor' in card)
check('EditorSynchronization.receive' in card)
check('EditorSynchronization.flush' in card)
check('titleEditor.currentEditor()' in card)
check('hasMarkedText()' in card)
check('!hasMarkedComposition, actions?.prefersDeletionUndo' in application)
check('refreshReveal' not in (app / 'NoteSurfaces.swift').read_text())
for path in app.glob('*.swift'):
    text = path.read_text()
    # docs/REQUIREMENTS.md (FR-09): the toolbar, its stack hint and
    # effectively topmost notes (置顶 or 浮起) may cover fullscreen apps; so may the
    # batch-selection overlay, which only exists while it lifts the notes like 浮起.
    if path.name not in ('Toolbar.swift', 'WindowChrome.swift', 'SelectionOverlay.swift'):
        check('.fullScreenAuxiliary' not in text)
    for forbidden in ['CGS', 'CGEventTapCreate', 'addGlobalMonitorForEvents', 'AXIsProcessTrusted', 'CGRequestListenEventAccess']:
        check(forbidden not in text)
for name in ['WindowChrome.swift', 'DeletionToast.swift']:
    check('.fullScreenNone' in (app / name).read_text())
chrome = (app / 'WindowChrome.swift').read_text()
check('effective == .topmost ? .fullScreenAuxiliary : .fullScreenNone' in chrome)
for name in ['NotePanel.swift', 'DockController.swift']:
    check('applyNoteLevel' in (app / name).read_text() or 'applyLevel()' in (app / name).read_text())
print(f'N7 source contracts: {checks} passed (not native API/runtime verification)')
