# N5 docking and display geometry

Authoring baseline: **LOCAL `5e935c043787fab5e7fa113459fd17b2f3059deb`**, verified clean before work. This is a local authoring hash, not a remote integration hash. Remote cherry-pick/integration hashes are supervisor-owned and were not fetched or inferred. This patch is uncommitted for supervisor review. No commit, push, rebase or Tauri-checkout modification was performed. The authoritative plan and all committed specification/prototype bytes are unchanged. N1–N4 documents remain historical evidence; this document supersedes their pending-N5 statements only.

## Implementation and design decisions

`Sources/DeskNodesActions/Docking.swift` is portable production code: screen selection, available rectangles, strips, overflow allocation/pages, snap/retention thresholds, insertion mapping, clamping and transactional docking/detach/preferences/topology recovery. `Sources/DeskNodesApp/DockController.swift` integrates those rules with the existing AppKit panels. `Application.swift`, `NotePanel.swift` and `WindowChrome.swift` connect topology notifications, docking controls and final-only gestures. No WebView, editor substitute or platform stub is used.

Native design intent follows prototype 01's aligned solid cards and prototype 03's lifted drag and outlined slot. Cards retain the N4 palette, fine borders, 12pt corners, 14pt padding and 13pt type. A 4pt pointer movement starts a gesture. During drag, the existing card lifts to scale 1.04, with a deeper shadow; the target slot has a dashed pale outline. Other cards preview the target arrangement with 0.30s Core Animation translation springs. The original slot remains outlined while dragging away. Reduce Motion suppresses scaling and movement springs. These are implemented source/layout choices, **not verified native visual fidelity**. Reference PNG 01 was inspected alongside the committed HTML 01/03; no application screenshot was manufactured.

Coordinates remain bottom-left AppKit **points**, including negative origins. Production reads public `NSScreen.visibleFrame` freshly, then insets it 8pt on each side. Menus/Dock are excluded according to the region supplied by macOS; no private Dock preferences, occlusion detection, Accessibility or Input Monitoring APIs are used. Apple documents the primary screen at index zero of [`NSScreen.screens`](https://developer.apple.com/documentation/appkit/nsscreen/screens), distinct from the key-window screen returned by `main`. Creation now also uses that primary screen. Layout uses [`visibleFrame`](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe), not backing pixels or a guessed menu-bar height. Changes are handled through `NSApplication.didChangeScreenParametersNotification`; an empty topology causes no recovery writes.

Top cards are 220×260pt. A conservative **visible height below 700pt** selects 200pt height. Side cards are 240pt wide, use actual row-height measurements and N4's 120…480pt automatic content-height policy, with internal scrolling after the cap. Dock dimensions are presentation geometry; manual free dimensions and the automatic/manual flag survive docking. Collapsed cards take a 32pt slot and retain their expanded state. Normal gaps are 12pt. Multiple edge groups on one monitor share space: side strips start below a top strip, with a 12pt gap. Opposing side strips split a display narrower than 508pt, retaining the gap.

Screens too small for nominal dimensions fit the available rectangle, allowing a presentation narrower than 200pt or shorter than 120pt rather than placing unreachable controls beyond it. Insets shrink only when needed to leave a positive region. Under 32pt available height even a collapsed header is clipped to fit. These pathological regions cannot provide a useful full editor; selecting a tab opens the retained note panel fitted over the strip. On ordinary short displays, cards remain 200pt high and scroll internally. Pure tests exercise extreme regions down to 1×1pt; those arithmetic results are not claims that macOS offers usable physical displays at those sizes.

Overflow reserves a **96pt rail along the strip axis** only when necessary. Cards form a contiguous prefix; the rest become compact tabs in stable durable order. Tabs are 32pt high, spaced 12pt, with a 32pt “更多” menu reserved at the rail bottom. Wheel movement pages the tabs, and the menu always lists every overflow note. A rail too short to allocate a tab uses the menu alone. Each tab has its own lightweight panel at the represented note's effective individual level; the menu control uses desktop level (or floating under all-topmost). The retained editor panel remains alive while represented by a tab. No durable hidden state or hide command exists.

Selecting a tab promotes that note to the first full-card slot for the session, displacing the trailing card into overflow without writing order. Promotion occurs only for overflow notes; focusing an ordinary visible card does not reorder the strip. An active overflow editor remains promoted during content refresh. Full-group insertion maps visible slot midpoints back to durable order, including overflow and promoted tabs. Dragging a promoted card commits an explicit order on release. Persistent order is the existing integer order with UUID tie-break; the complete destination strip is renumbered contiguously in one transaction. Other free notes retain their placement and order; source-strip gaps are harmless until its next reorder.

Header-background dragging preserves text input handling on the title and item editors. Within an existing strip, its edge anchor may move **48pt** away before detaching. A free card snaps only when released with the pointer within **24pt** of a top/left/right available edge and within its span; closest edge wins, with top first on exact corner ties. There is no bottom docking. Slot insertion uses horizontal centers for top and vertical centers for sides. The narrow snap band and wider retention band are conservative, documented defaults rather than spec-mandated constants.

Drag previews contain no repository mutation. `NoteGestureView` calls the final action only after mouse-up; an event-stream interruption cancels the preview. Destination placement, saved free placement and all target orders commit in one SQLite transaction. A failure rolls the whole operation back and refreshes the prior presentation. There are no window-move, resize-notification or animation-tick persistence observers. Native process termination mid-gesture must leave the last committed geometry/order. Docked resize grips are disabled; detaching restores free resize behavior. N4 free resizing remains final-only and maintains its auto/manual rules.

Context menus add top/left/right docking and “移出停靠条”. Context detach restores the saved free origin/dimensions, then reconciles it against current topology. Drag detach uses the release location while recovering the previous free width/height; automatic-height notes then remeasure current content. A note with no saved free placement uses a 240pt free-width fallback. `freeRestore` is refreshed whenever a free note enters a strip. No code transfers items across notes.

The menu-bar **停靠 → 主屏幕（默认） / display name → 顶部 / 左侧 / 右侧** is the deliberately limited preference entry. Selecting it saves the chosen display/edge and moves current docked notes together to that preference, preserving their stable sequence and individual appearance. Free notes do not move. New notes remain free as in N4, and can be docked with their context menu or drag. Full prototype-05 Settings remains unfinished N9 work; no shortcut/autostart/backup/settings expansion is claimed.

## Monitor identity, recovery and persistence

The public ColorSync [`CGDisplayCreateUUIDFromDisplayID`](https://developer.apple.com/documentation/colorsync/cgdisplaycreateuuidfromdisplayid(_:)) converts the current `NSScreenNumber` to an OS-supplied UUID string. The transient numeric display ID, localized display name, screen index and resolution are **not durable identities**. UUIDs are opaque preferences, not a promise of lifetime physical identity: adapters, virtual displays and hardware changes may invalidate them. Duplicate or unavailable UUIDs use session-only identifiers for geometry; these identifiers are never saved and ambiguous displays are omitted from durable monitor choices. The safe durable fallback is nil/primary. The implementation explicitly imports public ColorSync. Apple API declaration lookup is recorded in `native-n5-public-api.log`; that is reference evidence, not SDK compilation.

Nil dock display means follow the chosen display preference, or primary if none is selected. If the preference is unavailable, it stays saved, layout falls back to primary, and the docking menu shows an unavailable-display explanation. Reconnecting that preferred display makes preference-following docks use it again. Explicit per-note display identities that disappear are migrated to the current primary identity and clamped; reconnect does **not** silently send those migrated notes back. Free notes retain their actual containing monitor when possible; legacy nil free identities are resolved by frame center, then primary. Saved free restore placements undergo the same disconnect recovery. No migration runs on a transient empty screen list.

Native schema **4** adds nullable `notes.free_restore` using the existing internal versioned placement JSON encoding. Existing rows default to nil. Ordered v1/v2/v3 migrations remain transactional. Updates reject a dock-valued or invalid/nonfinite restore frame. Close/reopen and note-deletion undo preserve this field, individual levels, collapse and automatic/manual sizing. History schema and sealing triggers are unchanged. No backup-format or Tauri compatibility is implied.

Topology recovery clamps frames to the available inset region. Oversized manual frames can shrink during that explicit recovery; automatic sizing can remeasure afterward. Ordinary presentation fitting and dock preview never overwrite manual free geometry. Free frames on exceptionally small screens can keep N4's durable minimum sizing after an explicit resize while their presentation fits the available region. No return-to-disconnected-screen queue or hidden parallel geometry history is introduced.

Existing `NotePanel`, `NoteCardView`, `ItemRow`, NSTextView, text storage, input context and undo manager identities are retained. Refresh does not replace strings, selection or marked text. Overflow swaps window presentation, not editor ownership. The inherited `ItemRow(..., userInfo: nil)` call did not match its initializer; this patch removes that extra argument. AppKit compiler/runtime acceptance remains required despite this static fix.

## Executed validation

Official Swift **6.2.1**, x86_64 Linux, with the pre-existing isolated environment in [native-n2.md](native-n2.md). No toolchain/system package/network configuration changes were made. All tests use production Swift and actual isolated SQLite files; no Python geometry substitute or Mac SDK stub.

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

**56 portable XCTest tests passed, zero failures:** 37 action/state tests (15 N3, 7 N4, 15 N5), 15 persistence tests, 4 core tests. N5 adds 17 portable methods: negative-origin/multimonitor selection, inset/short/top/side/content/collapse bounds, overflow order/promotion/full allocation, tab pages/menu-only fallback, combined-strip separation, conservative snap/detach thresholds, full-order insertion, resolved nil/explicit monitor grouping, no gesture-preview writes, rollback after an actual first-row write, free-frame restore/reopen, individual state/deletion undo/history regressions, disconnect/reconnect/empty topology/UUID-unavailable fallback, v3 migration preserving tombstones/manual state/history and invalid-restore rejection. All existing expiry, cross-note rejection, SQL sealing, migration rollback and persistence tests pass. The separate Swift Testing runner's zero is not the XCTest count.

Exploratory output is retained: the initial 47-test run had two assertions in one side-height fixture whose total exceeded the available region by 2pt; the taller fixture corrected its non-overflow premise. Subsequent 54- and 56-test iterations passed. Final clean output is separate. Static checker has 33 assertions plus shell parsing. Native frontend syntax parse passes; **it does not import/typecheck AppKit or run native tests**. Seven native XCTest methods now exist, including a new marked-editor identity/manual-frame test across dock/side/detach. They are all unexecuted here. The test executable links the host SQLite shared library. Logs live only under `/workspace/desknotes/logs/native-n5*`.

## Exact Mac acceptance gates — all unexecuted

On macOS 14+ with selected compatible Xcode, use the actual checkout path and an isolated test user/database. Preserve existing production data.

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
screencapture -i build/acceptance/n5-light-top.png
screencapture -i build/acceptance/n5-light-reorder.png
# Switch to Dark; capture side, overflow and detached/collapsed states:
screencapture -i build/acceptance/n5-dark-side-overflow.png
```

Record OS/Xcode/architecture, monitor names/layout/scales, primary display, Dock position/auto-hide, separate-display Spaces and Reduce Motion, plus each result:

1. **SDK/build:** compile/link public ColorSync/AppKit, run all portable and seven native tests, sign/launch the accessory app with no Dock icon. Linux syntax parsing cannot establish SDK signatures or actor-isolation correctness.
2. **Visual:** compare actual native top cards/free notes to prototype 01 and lift/slot/menu/collapse to prototype 03, both appearances/all eight colors. Check 220×260/200 top, 240 side, 8pt inset/12pt gaps, subtle border/shadow, legible truncation, hover controls, 32pt tabs, wheel pages/menu access and calm 0.30s motion. Inspect clipped content during spring/lift and Reduce Motion. Capture native screenshots; do not substitute HTML captures.
3. **Monitor selection:** set secondary as keyboard-focus screen while primary remains elsewhere; default docking must stay primary. Choose each monitor/edge through docking controls, restart, check persistence. Test negative x/y origins, rotated/short displays, menu bar and Dock on bottom/left/right, auto-hide and resolution changes. Compare frames to `NSScreen.visibleFrame` in points on Retina/non-Retina mixed DPI. Record UUID availability/ambiguity; unavailable preference must explain primary fallback.
4. **Drag/order:** arrange at least four dock notes and enough for overflow. Drag first→last, last→first, before/after slot midpoints and between different edge groups/screens. Inspect lifted card, source/target slot and neighboring motion. Select/wheel through every overflow tab, including untitled/empty notes; promotion alone must not change durable order. Drag promoted notes and confirm final order survives restart. Verify tabs for desktop/ordinary/topmost notes have those levels, including all-topmost/restore.
5. **Detach/snap/geometry:** move beyond 48pt retention, release away from edges and verify a free note. Release within/outside the 24pt band at top/left/right/corners; no bottom snap. Context detach must recover prior free origin/manual size; drag detach must recover dimensions at the release location. Repeat at 320×550 manual, auto-height, collapsed, long/wrapped text and after restart. Test simultaneous top/left/right groups, narrow opposing sides and severe height reductions; all tabs remain accessible through their menu.
6. **Atomic writes:** on the isolated Mac database, use a second SQLite connection to inspect placement/order/free_restore before, during and after an extended native drag. No intermediate writes; mouse-up commits target placement/permutation together. Terminate the app during a gesture, relaunch and confirm previous final state. Exercise an interrupted event stream/failure and verify prior presentation returns. Repeat free resizing and Reduce Motion.
7. **Disconnect:** place free/manual/collapsed/dock notes on secondary, unplug it and confirm primary migration/clamping without content/level/sizing-mode loss. Unplug the preferred monitor, reconnect, swap primary, sleep/wake and change resolution/scale repeatedly. Distinguish preference-following return from explicit-note permanent migration. No data should vanish during transient zero-screen notifications.
8. **Input/history/undo:** compose Chinese Pinyin mid-item/title with candidates open; resize, dock, reorder, detach, promote overflow, recolor/collapse/expand and switch appearance. Confirm marked text, selected range, first responder, undo manager identity and native text undo/redo. Candidate Return must not create an item. Test same-note item dragging; another note must reject it. Delete/undo a docked/overflow/free note and item within five seconds, expiry, delete-then-type routing and last-note flow; history remains immutable. Real IME/focus behavior during tab window ordering is a critical gate, not established by retained-object assertions.
9. **Levels/Spaces:** repeat N4 Finder-icon/ordinary/topmost/transient-raise/all-topmost tests with dock cards and overflow tabs. Across desktop Spaces, Stage Manager and other-app fullscreen on both displays, no ordinary note/tab/control/placeholder may overlay fullscreen. Only N7 will own fullscreen reveal. `canJoinAllSpaces`/`fullScreenNone` remain policy intent pending runtime verification.

## Review status and N6 readiness

N5 source and portable tests are ready for supervisor review/commit, with Mac acceptance explicitly outstanding. Native drag smoothness, panel/tab key behavior, AppKit SDK typechecking, signing, monitor UUID behavior, actual menu-bar/Dock exclusion, physical unplug/mixed DPI, IME/undo/focus, Spaces/fullscreen and screenshots have **not** been executed on Linux. No native layout/beauty/runtime pass is claimed.

N6 can use the unchanged immutable-history and synchronous transaction foundation with retained note/item identities. It still must define daily membership/missed-day/timezone/DST/clock-reversal policy and implement rollover/wake scheduling. This patch adds no rollover, fullscreen reveal, hide feature, N9 Settings completion, shortcut, autostart, backup or unrelated functionality. Supervisor owns committing and remote integration.
