# N4 chrome, geometry and window modes

Patch-authoring baseline: **LOCAL `02b0d762c306365f8b59223202321374cc83f0cd`**. This is a local patch-authoring hash, not a remote integration hash; supervisor cherry-picks have different hashes. N4 changes are left uncommitted for supervisor review/commit. No commit, push, rebase or force operation was performed. Authoritative `docs/macos-native-plan.md` and every file under `docs/spec/macos-native/` are unchanged. The old Tauri checkout is untouched.

## Presentation and state choices

N4 extends the N3 AppKit panels and stable-ID row reconciliation. There is no WebView or alternative editor. Chrome uses solid eight-token light/dark backgrounds, 12pt corners (10pt collapsed), a fine border with hover emphasis, system window shadow, 14pt content inset, 13pt title/item type, 26pt minimum rows and monospaced count. Idle headers show title/count; pointer hover substitutes four quiet color/pin/collapse/more controls. Row drag/delete controls and the resize corner appear on hover. The context menu has exactly eight swatches with names/accessibility labels and selected outline, three individually checked levels, collapse/expand, automatic-height reset, add item and destructive delete. Text editors retain their native text context menu. Add is also available through unmarked Return; there is no permanent footer toolbar. Native fidelity still needs real light/dark screenshots against prototype 03; the checked-in reference PNG was inspected, not represented as an app screenshot.

Pin means the **durable individual topmost choice**, not a separate independent boolean. Pin toggles topmost ↔ desktop; selecting ordinary is explicit in the context menu. The filled pin reflects the individual choice, not a temporary/global override. “全部置顶 / 全部恢复” is a **session-only presentation override**, initially off after relaunch. It never changes SQLite levels. New/restored notes participate immediately. A level selected while the override is active is saved as that note's choice and takes effect on restore. No stale snapshot of choices can overwrite subsequent user changes. Deleting/restoring a note preserves its choice and sizing state.

New UI notes are free, desktop-level, 240pt wide and automatic height. The app places them near the primary available-area top center with a small cascade; the portable creation fallback is (100,100). This is not N5 topology/clamping. Height follows the actual rows' wrapped/multiline text measurements, minimum 120pt, growing to 480pt and then scrolling internally. Manual lower-right resizing clamps expanded size to 200×120…400×600pt and disables automatic height. “随内容调整高度” re-enables it. The header background moves a free note; the title editor remains an editor. Negative origins are valid and are preserved. No display-disconnect migration or screen-edge clamp is implemented.

Collapse presents exactly 32pt with its top edge fixed and optional-title / first-item fallback (empty stays empty; no invented title). SQLite placement always contains the **expanded** frame, never 32pt. Expansion restores the manual expanded size or current automatic height. Collapse hides the existing list; it does not rebuild its NSTextViews. Recolor, levels, resize and refresh do not replace editor strings, text storage, input contexts or undo managers. Wrapped-row measurements read text and attributes without rewriting them. N3 deletion protection and sealed SQLite history remain in place.

Native Core Animation insertion/deletion and collapse/expand use 0.30s springs; deletion also fades. Reduce Motion is checked on each transition and removes movement/delay. The panel's final frame is set directly; Core Animation animates presentation-layer bounds for collapse/expand, never the durable model. Header/corner gestures update the panel interactively but call `finalGeometry` only on mouse-up. There is no move/resize notification persistence observer or animation-tick writer. Automatic-height changes persist only their computed final expanded geometry, with equality checks to avoid repeated identical writes. A process termination mid-gesture retains the previous committed frame. Native clipping/spring quality remains a screenshot/runtime gate.

`DeskNodesActions/WindowState.swift` contains portable frame bounds, collapsed projection, automatic-height cap, fallback and effective-level policy plus transactional appearance/final-geometry actions. It imports no AppKit. N4 adds native schema **3**, one checked `automatic_height` boolean column with default true. Ordered v1/v2→v3 migration preserves rows/tombstones/history and runs inside the existing schema transaction. All previous placement JSON and history formats remain unchanged; no backup/Tauri compatibility is implied. Existing N2 dock placements are retained as dock placements and shown in a temporary free-style presentation; N4 gestures never detach or overwrite them. N5 must replace this bridge.

## Public macOS policy and unresolved gates

Chosen public APIs:

- Desktop: `NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)`, intended above Finder desktop icons and below ordinary windows. No hard-coded numeric desktop constant or private API. See Apple's [CGWindowLevelKey](https://developer.apple.com/documentation/coregraphics/cgwindowlevelkey) and [desktopIconWindow](https://developer.apple.com/documentation/coregraphics/cgwindowlevelkey/desktopiconwindow).
- Ordinary: `.normal`; topmost and transient raise: `.floating`. “Topmost” means above ordinary application windows, not above system menus/security UI. Clicking a desktop panel raises it before forwarding the same event to native editing. Resigning key or application activation restores its effective individual/global level; no durable level write occurs.
- Every note uses `[.canJoinAllSpaces, .fullScreenNone]`, with no `.fullScreenAuxiliary`, `.canJoinAllApplications` or full-screen-primary behavior. Apple's [canJoinAllSpaces](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallspaces) expresses the all-Spaces intent; [fullScreenNone](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/fullscreennone) is the chosen non-fullscreen policy. No special permissions or private Space APIs are used.

**UNVERIFIED:** public flags are policy intent, not evidence that accessory NSPanel stacking is correct on a user Mac. Desktop-icon ordering, native key/activation transitions, Finder click-away, Stage Manager, Mission Control, all-Spaces behavior and exclusion from other apps' fullscreen Spaces must be tested. If ordinary note panels overlay another app's fullscreen, N4 acceptance fails and this policy needs revision. N7 alone owns the future fullscreen-compatible edge panel. No occlusion detection, edge reveal or permission claim is implemented here.

## Executed Linux validation

Actual Swift **6.2.1**, x86_64 Linux, environment already installed as documented in `native-n2.md`. No Linux app launch or simulated UI screenshot. Commands from the native checkout:

```sh
export PATH=/workspace/desknotes/toolchains/swift-6.2.1-RELEASE-ubuntu24.04/usr/bin:$PATH
export LD_LIBRARY_PATH=/workspace/desknotes/toolchains/apt/local/usr/lib/x86_64-linux-gnu
swift --version
swift package describe
swift package clean
swift test -Xcc -I/workspace/desknotes/toolchains/apt/local/usr/include \
  -Xlinker -L/workspace/desknotes/toolchains/apt/local/usr/lib/x86_64-linux-gnu
python3 scripts/check-n1.py
bash -n scripts/build-macos.sh
swiftc -frontend -parse Sources/DeskNodesApp/*.swift Tests/DeskNodesAppTests/*.swift
ldd .build/x86_64-unknown-linux-gnu/debug/DeskNodesPackageTests.xctest
git diff --check
git diff --exit-code HEAD -- docs/spec/macos-native docs/macos-native-plan.md
```

**39 XCTest tests pass, zero failures:** 22 action/state tests (15 N3 + 7 N4), 13 persistence tests (12 existing + native-v2 migration), 4 core tests. The separate Swift Testing runner's zero is not the XCTest count. Production Swift code uses real isolated SQLite files and links the host system SQLite shared library. New tests exercise bounds/nonfinite rejection/negative origins, collapsed top anchoring/expanded recovery, height cap/fallback, all-topmost/restore/transient policy, choosing levels during override, final-only durable geometry, manual/automatic state, collapse/color/level reopen, note-deletion undo and immutable history, invalid-write atomicity, existing dock preservation and v2 migration with retained history. Existing undo expiry, rollback, history-sealing and migration tests still pass.

The first exploratory run failed three assertions (two tests compared unrounded creation timestamps against SQLite round trips, and the old v1 migration test expected schema 2); fixed-clock N4 fixtures and the schema-3 expectation corrected these tests. The final clean suite passed. No production timestamp semantics were changed.

Static checker remains unchanged: 33 assertions plus its shell parse pass. Separate shell syntax, portable import separation, diff/spec preservation and native frontend syntax parse pass. **Syntax parse is NOT AppKit typechecking.** AppKit executable/native tests are excluded on Linux; six native XCTest methods are present but uncompiled/unrun. The retained-editor test now includes palette/level/geometry/collapse/expand while marked; a new native test checks level assignment and panel geometry. These are not proof of real IME or Spaces behavior.

Logs: `/workspace/desknotes/logs/native-n4-environment.log`, `native-n4-swift-tests.log`, `native-n4-static.log`, `native-n4-native-parse.log`, `native-n4-review.log`.

## Exact user Mac acceptance — all UNVERIFIED

On macOS 14+ with selected compatible Xcode, from the actual checkout:

```sh
xcode-select -p
xcodebuild -version
xcrun swift --version
xcrun swift test
./scripts/build-macos.sh
/usr/bin/plutil -lint build/DeskNodes.app/Contents/Info.plist
/usr/bin/codesign --verify --strict --verbose=2 build/DeskNodes.app
open build/DeskNodes.app
mkdir -p build/acceptance
screencapture -i build/acceptance/n4-light.png
# Switch to Dark, repeat:
screencapture -i build/acceptance/n4-dark.png
```

Record macOS/Xcode/architecture, monitor/Spaces settings and pass/fail. Use an isolated Mac test user for first-launch/store tests; do not delete an existing production database.

1. **Build/native tests:** compile all AppKit source and run the six native XCTest methods, including retained marked editor across collapse/expand and genuine NSTextView undo/redo. Linux parse cannot catch SDK signatures or actor-isolation integration errors. Verify accessory/menu-bar behavior and no Dock icon.
2. **Visual:** compare native idle/hover/edit/collapsed states to prototype 03 at pt scale, both appearances, all eight swatches. Verify count/tool substitution, pin indicator, truncation, border/shadow, circular checks, 13pt font and Chinese baselines, selected swatch outline and destructive action. No controls should remain over text after pointer exit. Test right-click on header/card and native editor context menus separately.
3. **Geometry:** create 1, 3 and 30 items plus long wrapped text/multiline paste. Confirm width 240, minimum 120, growth cap 480, reachable scrolling and no editor replacement/focus jump. Resize beyond each bound: expect 200×120 and 400×600. Add/remove content after manual resize: size stays manual. Reset automatic height and check growth resumes. Drag by blank header to a secondary screen with negative origin. Quit/relaunch and confirm final origin/size/color/collapse/level. Screen topology recovery is N5, not this acceptance.
4. **Collapse:** test titled/untitled/empty notes, first completed item and multiline first item; collapsed display must use the actual first item and 32pt height. Expand repeatedly at manual 550pt height and automatic height. Top edge and expanded geometry must survive restart; no saved 32pt expanded size. Hover tools must be reachable on collapsed headers.
5. **Levels/focus:** overlap Finder icons and two ordinary apps. Desktop notes must cover icons but stay behind ordinary windows; ordinary notes must participate in normal ordering; pinned notes must float above ordinary windows. Click a partly visible desktop row and type on that first click. Click Finder desktop, another note, another app, status menu and auxiliary windows: transient raise must end on focus loss. Repeat while all-topmost is active.
6. **Restore:** create desktop/ordinary/topmost notes; toggle all-topmost, create a new note, change one individual level, delete/undo another, then restore. Every note must use its current individual choice. Repeat toggle twice and restart: global override resets off, individual choices persist. Test unpin's documented desktop default.
7. **Spaces/fullscreen:** create multiple desktop Spaces, enable/disable Stage Manager and test separate-display Spaces configurations where available. All notes should be available across desktop Spaces. Enter Safari/another app's fullscreen on each display and switch Spaces: **no note panel in any mode may overlay that fullscreen app**. No edge panel is expected until N7. Record any discrepancy as a failed native gate, not as passed based on flags.
8. **Motion/persistence:** observe 0.30s create/delete/collapse/expand springs and clipping at min/max sizes; interrupt/repeat transitions. Toggle Reduce Motion while running and repeat: no movement or deletion delay. On an isolated test database, inspect note placement before/during/after a header/corner gesture using a second SQLite connection: intermediate drag frames must not be written, only mouse-up final expanded size. Observe collapse: no 32pt placement write or animation-tick writes. Terminate mid-gesture, relaunch and verify last committed frame.
9. **Input/undo/history regression:** Apple Simplified Chinese Pinyin, candidates/Return/Backspace/Escape in the middle of text; Return accepting a candidate must not add a row. Recolor/change level/resize/reorder while composing, collapse/expand and switch appearance; confirm native composition behavior, retained selection and editor identity under debugger. Exercise native Command–Z/redo after ordinary text edits and N3's five-second deletion undo, latest-only expiry, last-note deletion, delete-then-type routing and restart. Verify existing immutable history snapshots remain unchanged. Collapsing can change native first-responder eligibility by hiding the list; actual candidate/focus behavior is a critical Mac gate.

## N5 readiness and limitations

Expanded point geometry, durable auto/manual sizing, separate effective-level policy and final-geometry action are ready for N5 to reuse. N5 must install actual strips, detach/snap, dock ordering/overflow and display identity/topology recovery; none is simulated here. Existing dock placements are preserved but their temporary card presentation is not a functional strip, and move/resize persistence intentionally does nothing for them. No hide, docking UI, rollover, edge reveal, global shortcut, autostart, backup or legacy Tauri feature was added. History/Settings remain explicit placeholders. No memory optimization or performance claim was attempted.

Unresolved delivery gates are AppKit compiler/linker/signing, native animation/screenshot fidelity, IME/native undo/focus, public window-level ordering and Spaces/fullscreen behavior. Supervisor owns review and committing; no native acceptance is claimed by the portable suite.
