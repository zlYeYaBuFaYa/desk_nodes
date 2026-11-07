# N3 editing and deletion protection

Implementation baseline: `035aced`. N3 only, uncommitted for supervisor review. The authoritative plan/spec and historical N1/N2 documents are unchanged. The old Tauri checkout is untouched. No app launch, network repair, system-setting change, memory measurement or performance project was performed.

## Architecture and behavior

`DeskNodesActions` is a separate portable production target, depending on the N2 repository. `NoteActions` owns optional-title binding, item CRUD, completion, insertion and contiguous same-note permutation validation, plus deletion recovery with an injected clock. Tests use isolated temporary SQLite files, never the production storage-path helper. No AppKit types or timer live in this target.

`Store.restoreItem` and `restoreNote` extend N2 without a schema migration. They restore existing tombstones, require matching retained content/identity/parent/order, and restore original update timestamps as well as IDs, creation dates and data. Note restoration includes only the children live at deletion; earlier tombstones remain deleted. A mismatching child aborts and rolls back the whole restore, including the note. No restore/action path writes history. SQLite's existing sealed-history triggers stay intact.

`Application.swift` explicitly opens the native production database at the N2 path and creates one retained NSPanel per live note. No fixture data is seeded. First launch and deleting the last note show an explicit new-note flow; the menu-bar new-note action always remains available. New notes have a nil title and one empty item. New note positions do not reuse tombstoned positions. Database errors are surfaced rather than resetting a database or reporting false success.

`NotePanel.swift` binds actual models to an optional native title field, count, completion circles, NSTextView rows, add/delete controls and same-note drag handles. Dragging a handle onto another row inserts before that row; append is possible by moving intervening rows before it. The source view identity must belong to the same card, and portable actions independently validate the entire item-ID permutation. Cross-note/external drops are rejected. Reorder changes frames without removing existing editors from the view hierarchy. New rows receive focus; deleting a row focuses its surviving neighbor. Completed text receives temporary layout-manager gray/strike-through attributes; it remains editable.

The paper colors, 12pt corners, subtle border/shadow, 13pt type, 26pt rows and monospaced count retain the prototype vocabulary. Native visual fidelity is **pending Mac review**. The fixed 240×260 panel, internal scroll area and always-visible quiet action controls are an N3 presentation bridge, not N4 sizing/hover or N5 docking. Multiline pasted content remains in the same item, scrolling within its native row text view. No persisted placement/level/collapse values are overwritten by this bridge.

`NoteTextView` lets AppKit own text storage, input context, native selection and text undo. Text-change persistence does not reload strings. `keyDown` remembers whether composition existed before the input context handles an event, and `doCommand` also checks the current marked range. Marked commands stay native; an unmarked Return adds an empty item after the current one without splitting its text, and Backspace deletes only an entirely empty, unmarked item. Native text behavior handles nonempty Backspace. No synthetic event or Mac API shim was used as evidence of real IME behavior.

## Deletion and undo policy

The latest successful note/item deletion has one five-second, in-memory recovery slot. A subsequent successful deletion replaces it; failed actions do not. Eligibility is strictly `0 <= elapsed < 5` seconds. Exactly five seconds expires; invalid or reversed clocks fail closed. The UI expires the slot in common run-loop modes and checks the clock again on every undo attempt, so delayed UI timers cannot extend eligibility. Restart does not resurrect a slot; durable tombstones remain retained.

A separate bottom toast survives deleting the last note, with a button and short reduced-motion-aware insertion. Command–Z restores the latest eligible deletion immediately after deletion. Once new item/title typing occurs, Command–Z follows native text undo; the toast button can still restore the deletion before expiry. Marked composition never routes Command–Z to deletion. Shift–Command–Z stays native redo. The application does not register fake text edits or restoration callbacks in an editor's undo manager. After deletion expiry, normal native undo can still undo genuine text edits, but cannot resurrect a deleted item/note. Deletion redo and a stack of recoverable deletions are not added.

## Executed Linux validation

Official installed Swift **6.2.1**, x86_64 Linux, actual production Swift repository/action code linked to system SQLite. Exact environment from N2:

```sh
export PATH=/workspace/desknotes/toolchains/swift-6.2.1-RELEASE-ubuntu24.04/usr/bin:$PATH
export LD_LIBRARY_PATH=/workspace/desknotes/toolchains/apt/local/usr/lib/x86_64-linux-gnu
swift --version
swift package clean
swift test -Xcc -I/workspace/desknotes/toolchains/apt/local/usr/include \
  -Xlinker -L/workspace/desknotes/toolchains/apt/local/usr/lib/x86_64-linux-gnu
```

**31 XCTest tests passed, zero failures:** 15 new action tests, all 12 persistence tests and all 4 core tests. The extra Swift Testing runner reports zero because these are XCTest tests. Coverage includes persisted CRUD binding/reopen/Unicode, optional title, insertion order, cross-note/missing/duplicate reorder rejection, partial-reorder rollback, exact item/note restoration, earlier tombstone preservation, restore-conflict rollback, latest-only recovery, failed deletion, 4.999-second success and five-second expiry, clock reversal/invalid time, text-undo routing policy, original ordering when creating during pending deletion, composition command matrix and immutable history captured both before and during deletion. Existing persistence tests continue to exercise SQL history sealing, migration and rollback. These are not Python reimplementations.

Additional actual checks: existing `python3 scripts/check-n1.py` (unchanged, 33 assertions plus shell parse), separate `bash -n scripts/build-macos.sh`, `git diff --check`, preserved authoritative-path diff, Swift manifest description, native Swift frontend syntax parsing only, and dynamic SQLite linkage inspection. Native frontend parsing is not AppKit typechecking. Logs: `/workspace/desknotes/logs/native-n3-swift-tests.log`, `native-n3-environment.log`, `native-n3-static.log`, `native-n3-review.log`. No screenshot or native binary was produced.

## Mac gates — all unexecuted

Run on macOS 14+ with selected compatible Xcode, using the actual checkout path:

```sh
xcode-select -p
xcodebuild -version
xcrun swift --version
xcrun swift test
./scripts/build-macos.sh
/usr/bin/plutil -lint build/DeskNodes.app/Contents/Info.plist
/usr/bin/codesign --verify --strict --verbose=2 build/DeskNodes.app
open build/DeskNodes.app
```

Five native XCTest sources now cover panel properties, marked-text appearance stability, structural commands/selection, binding retaining the same composed editor across check/reorder, and genuine NSTextView undo/redo availability. They are excluded by the manifest on Linux and have **not been compiled or run here**. Synthetic marked text does not replace the following hardware input gate.

1. Fresh native store: confirm empty flow and menu create work without a Dock icon. Create two notes, optional/Chinese/empty titles, several items and check/uncheck. Quit normally and relaunch; verify IDs/data/order through stable visible content. Do not delete a preexisting production database to simulate first launch; use a separate Mac test user if needed.
2. Type/select/copy/paste/undo/redo in several rows, including emoji, combining marks, long and multiline paste. Toggle completed and reorder while retaining selection. Verify gray strike-through and accurate count. Drag a row before another; verify persistence after restart. Cross-note and external drags must fail.
3. Apple's Simplified Chinese Pinyin: start composition in the middle of existing text, use candidates/arrows/Backspace/Escape, press Return to accept. There must be no extra row, accidental text split, lost candidate/selection or focus jump. A subsequent unmarked Enter must add exactly one row and focus it. Repeat after check/reorder, light/dark changes, and opening/closing the unchanged History/Settings placeholders. Test both ongoing marked state and the event where Return clears the marked range. This is a critical unresolved native gate.
4. Empty unmarked Backspace deletes just that item and focuses its neighbor. Nonempty/marked Backspace remains native. Delete items and notes via buttons; undo with toast and Command–Z before five seconds. Verify original data/completion/order, and earlier deleted children remain absent. Delete the last note, restore it with Command–Z and toast separately, then let it expire and use the empty-flow/menu new-note routes.
5. Delete then type into a surviving row/title: Command–Z must undo that typing, while the toast remains usable before expiry. Repeat with selected text/composition. At/after five seconds, deletion must not be restored via either route. Two rapid deletions restore only the latest; a restart retains deletion. Check native undo doesn't resurrect a structurally deleted row after expiry.
6. Compare real light/dark captures against prototype 03: solid paper, fine border, rounded corners, quiet controls, completion circles, stroke and text baseline. Check many rows scroll and all add/delete controls remain reachable. Enable Reduce Motion and verify insertion movement is suppressed. No native screenshot fidelity is claimed until this review.

## N4 readiness and risks

The portable action API and stable-ID editor reconciliation are available to N4. N4 must replace fixed presentation geometry, implement levels/transient raise, palette/context and hover tools, auto-height/resize/collapse and relevant native animation acceptance without rebuilding active text views. N5 docking, N6 rollover, N7 fullscreen reveal, N8 history UI and N9 settings/backup remain absent. History and Settings still explicitly say unfinished; all-topmost stays disabled, and no global shortcut/autostart is registered. No hide/tomorrow/cross-note transfer or legacy persistence has been introduced.

Highest remaining risks are uncompiled AppKit API integration, actual IME Return event sequencing, native responder-chain undo routing after last-note deletion, scroll/focus behavior and native screenshot fidelity. Linux policy tests establish portable behavior only. The supervisor owns review and committing; no commit or push was made.
