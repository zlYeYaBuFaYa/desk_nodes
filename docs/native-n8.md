# N8 read-only native history

Authoring baseline: **LOCAL `33905b02f6260510030841be3deaf696d340c5a1`**, clean before work, in `/workspace/desknodes-macos-native`. N8 only, left uncommitted for supervisor review/commit. No commit/push, delegation, tool installation, system-setting change, Tauri checkout change, or N9/N10 implementation. Authoritative requirements, plan, prototype04 HTML/PNG and N1–N7 documents were read; those paths remain unchanged. No quota exhaustion occurred.

## Implementation and prototype mapping

`HistoryWindow.swift` supplies the low-frequency SwiftUI view and main-actor presentation model. `AuxiliaryWindows` lazily constructs it on the first History request using the **existing shared Store**; it retains a single controller/model for close/reopen. No resident history view tree is constructed at launch, and no new timer, observer, database connection or fixture seeding is added. Reopening reloads the selected month; month navigation also reloads. A successful N6 rollover reloads History only while its window is visible. Selection stays stable across refresh/reopen; navigating a month selects its first date. Initial selection/highlight uses the current configured business day and timezone. Read failures clear stale data and offer retry; initial settings-read failure reports an alert.

The window uses native AppKit titlebar/traffic lights and an NSHostingController, at normal level with fullscreen exclusion. Content defaults to 1040×656pt (prototype04's content under its 44pt illustrated titlebar); minimum 900×656pt, resizable. The native titlebar height/style is OS-controlled, not a custom imitation. The prototype's 400pt calendar column, 28/32pt horizontal and 24pt vertical insets, 18pt section spacing, Monday-first grid, 46pt cells/4pt gaps/9pt corners, 22×3pt miniature progress lines, 20pt headings, 24pt monthly percentage, 13pt items and 11pt badges are expressed directly in SwiftUI. Selected day has contrasting ink and progress; current business day has a quiet fill. Month arrows cross years and handle six-week months. Calendar empty padding is noninteractive; no-data dates remain selectable without fabricated progress.

The detail header shows the selected date/weekday and completed/total. Frozen note groups retain color/order and title; nil/blank titles use the first nonblank frozen item, then `无标题便签`. Group headings truncate at two lines; item content wraps without a row-count cap and supports text selection/copy. Empty items display `空白事项`, without changing stored content. ScrollView/LazyVStack allow long groups/lists. Completion circles are read-only images, with Chinese accessibility labels. Frozen deleted items are gray/struck through and badged; deleted groups are badged and their items show deleted status. Carry badges sit alongside the item and use the actual recorded destination, including the year across year boundaries. Completed historical text remains unstruck unless deleted, matching prototype04 rather than the live-editor completed styling.

Solid light colors are taken from prototype04 (`FBFAF8`, `EFEDE8`, `2F2C27`, `4F7A64`, `E4E1DA`, `6B5A2E`, `F3E9C9`); appearance-aware counterparts and existing eight note colors support dark appearance. Native titlebar, glyph size, badge wrapping, grid baselines, contrast and screenshot fidelity are **unverified**, not established by source comparisons. There are no history mutations, weekly/streak statistics, settings controls, web content, new permissions or history animations.

## Real data and rate semantics

`DeskNodesPersistence/History.swift` is production portable code used directly by the view: civil month navigation/grid, date/weekday/carry labels, optional-title fallback and completion aggregation. Civil `YYYY-MM-DD` keys are never reinterpreted through a changing timezone; UTC Gregorian arithmetic is used only to enumerate their calendar labels. Runtime default selection uses the existing `BusinessCalendar`, persisted boundary and current timezone. Month navigation rejects BCE and years beyond 9999.

`Store.history(in:)` is a bounded, ordered read of **sealed** `days` and existing `snapshot(day:)` DTOs, under the store's recursive lock. It never calls capture/rollover or reads live rows. At most one calendar month's snapshots are loaded. There is no schema change: native schema remains **6**, including immutable history triggers, archive and pending-deletion membership semantics.

Each recorded snapshot item occurrence counts once in the daily/monthly denominator, including deleted items and items belonging to deleted notes. Only its immutable `completed` flag counts in the numerator. Thus a deleted unfinished item is not completed; a deleted completed item preserves its completed flag. Monthly rate is **sum(completed) / sum(total)** across recorded days, not the mean of daily percentages and not a unique-item lifetime statistic. An unfinished same-ID item carried through several observed days appears in each day's denominator. Integer display rounds to the nearest percentage (30/41 → 73%). Zero total yields an undefined rate displayed as `—`; no progress line is shown for missing or empty days. A real zero-completion nonempty snapshot still shows a zero-length fill on a visible track. Daily/monthly counts show zero for no data; explanatory text distinguishes absent snapshots from an observed empty day/group.

N6 membership is authoritative: rollover closes only the previously observed active day, archives completed live items, records unfinished direct carry to the newly observed day and consumes pending tombstones. Skipped dates remain absent. Archived rows are not deletion tombstones; subsequent daily snapshots exclude them. A deleted parent does not retroactively delete its previously archived children. This UI preserves each day's original deletion markers and never overlays a later live tombstone onto an earlier day's content/rate. Five-second deletion undo across a boundary can restore live content while the already sealed deleted status remains in history. Explicit N2 `capture` snapshots retain their own all-retained membership; History displays exactly what was sealed rather than recomputing it under today's rollover policy.

History DTOs (`DailySnapshot`, `SnapshotNote`, `SnapshotItem`), `HistoryDay` and palette now conform to Codable. Fields remain immutable, including identities, completion, deletion timestamps and carry keys. HistoryDay decodes through its validating civil-date initializer (single string), rejecting invalid leap/date keys. Production snapshot round-trip tests include Unicode, nil title, completion, tombstone and carry data. **This is not an N9 backup envelope/importer or a promised public JSON format.** No decoded DTO is written to SQLite. N9 must still define versioning, validation, transactional import and complete native backup coverage (settings, live rows, tombstones, sealed snapshots, checkpoint, archives, pending memberships, geometry and schema6 preference).

## Executed Linux validation

Pre-existing Swift **6.2.1**, x86_64 Linux and host system SQLite; no installation. **99 production portable XCTest tests pass, zero failures**: 52 actions + 43 persistence + 4 core. N8 adds 10 history tests; all 89 earlier tests pass. They use actual Swift production APIs and temporary on-disk databases, not Python replicas or the production path.

New coverage: December/January and lower/upper-year navigation; leap years including 2000/2100; Monday-first/six-week grids; LA/Tokyo business-day selection across a month boundary without shifting stored keys; missing/observed-empty days and read-without-capture; weighted aggregation with deleted unfinished rows and actual direct carry; real N6 archive/deleted-group/month/year jump behavior, no fabricated skipped days, later live edits/deletion and close/reopen immutability; Codable round-trip and invalid decoded civil days; title fallback; actual leap-day/cross-year carry labels; 30 groups/600 long Unicode items with stable ordering and adjacent-month exclusion. Existing SQL sealing, migration, rollback, IME policy, shared editing, deletion undo and rollover tests remain intact.

Early validation caught missing palette Codable conformance at compilation, then a year-1 navigation failure: Foundation's positive BCE year needed an explicit era guard. Both were corrected; full clean validation passes. No assertions were weakened. Linux emits the existing missing-pkg-config warning; explicit pre-existing header/linker paths supply SQLite development files.

Reproduce:

```sh
export PATH=/workspace/desknotes/toolchains/swift-6.2.1-RELEASE-ubuntu24.04/usr/bin:$PATH
export LD_LIBRARY_PATH=/workspace/desknotes/toolchains/apt/local/usr/lib/x86_64-linux-gnu
swift package clean
swift test -Xcc -I/workspace/desknotes/toolchains/apt/local/usr/include \
  -Xlinker -L/workspace/desknotes/toolchains/apt/local/usr/lib/x86_64-linux-gnu
python3 scripts/check-n1.py
python3 scripts/check-n7.py
python3 scripts/check-n8.py
bash -n scripts/build-macos.sh
swiftc -frontend -parse Sources/DeskNodesApp/*.swift Tests/DeskNodesAppTests/*.swift
git diff --check
git diff --exit-code HEAD -- docs/spec/macos-native docs/macos-native-plan.md \
  docs/native-n1.md docs/native-n2.md docs/native-n3.md docs/native-n4.md \
  docs/native-n5.md docs/native-n6.md docs/native-n7.md
```

N1 static checker: 33 assertions plus shell parse. N7: 82 source contracts (additional app files increase its per-file checks); N8: 53 source/prototype contracts. Manifest description and actual SQLite dynamic linkage are recorded. Native frontend parsing covers all app/native test source, including one new presentation navigation/reload/error test; **parsing is not SDK typechecking**. Twelve native XCTest methods are present and uncompiled/unrun on Linux.

External evidence: `/workspace/desknotes/logs/native-n8-checks.sh`, `native-n8-tests.log`, `native-n8-static.log`, `native-n8-environment.log`, `native-n8-native-parse.log`, `native-n8-review.log`. No native binary, native screenshot or browser screenshot substitute was produced.

## Focused Mac acceptance — all unverified

Use macOS14+ and compatible already-selected Xcode, an isolated test user/database, preserving existing production data. Do not alter system clock/settings to manufacture evidence. Fixed-clock portable tests cover deterministic date/boundary cases; native runtime rollover can wait for the configured real boundary.

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
screencapture -i build/acceptance/n8-history-light.png
screencapture -i build/acceptance/n8-history-dark.png
```

Record OS/Xcode/architecture, actual pass/fail and capture paths. These commands, **SwiftUI/AppKit SDK typecheck/build, signing, launch/runtime and screenshots have not run here**.

1. Build/run all tests including the new native HistoryPresentation test. Confirm accessory/no Dock icon and status menu lifecycle. Open History repeatedly: one retained window, stable month/selection and fresh data. Close/minimize/reopen, close all auxiliary windows, and confirm note windows/menu remain operational. Quit/relaunch retains sealed data. History must not float over another app's fullscreen; N7 reveal alone owns that behavior.
2. Compare real light/dark captures with prototype04 at point scale: native titlebar, two columns, month grid/selected/current date, tiny progress tracks, monthly weighted rate, colored note headings, circular completion marks, inline carry/deleted badges and daily counts. Check empty days/months, captured empty notes, 0% versus undefined rate, December/January, leap February and six-row months. Test keyboard Tab/Space activation, VoiceOver day/count and completion labels, and readable dark selection/badges.
3. Use test-fixture snapshots through the real repository on an isolated Mac store: mixed completion, unfinished carry over a skipped date/year, deleted unfinished/completed items, deleted note, archived completed item followed by parent deletion, nil/blank/long titles and multiline Chinese/emoji. Verify frozen title/color/order/status/carry dates and weighted numerator/denominator. No row can be toggled/edited/deleted; selection/copy must not modify history. Later live completion/deletion/undo must leave earlier history unchanged.
4. Open 30+ groups/600+ long rows, scroll through the final item, select/copy multiline text, resize down to minimum and enlarge. No missing groups, overlapping badges, truncated item content, unreachable calendar stats or accidental history mutation. Check native layout responsiveness; no performance threshold is claimed by the portable volume test.
5. Keep History open across actual rollover and wake catch-up: a newly sealed source day appears once, skipped dates stay empty, current live day remains without a snapshot, and selected older day stays selected. Close History during rollover and reopen: selected month reloads. Inject a closed/failing test store in the native presentation test: old contents clear and retry is offered; live store is never reset.
6. Repeat N6/N7 gates around History focus changes: real Apple Pinyin candidates in ordinary and reveal item/title editors, commit/cancel/Return/Backspace, switch to/from History, preserve final text/selection/native undo, no passive stale overwrite. At rollover, marked composition still defers the whole operation; History must not flush/force IME or synthesize capture. Verify five-second latest deletion undo, archived-editor removal, dock/free/collapsed notes, all-topmost/restore and reveal/fullscreen/Spaces behavior remain unchanged. Native focus and IME acceptance remain required even though those implementation files were not rewritten.

## Review risks and N9 readiness

New files: production History.swift and HistoryWindow.swift, portable HistoryTests, native HistoryPresentationTests, check-n8.py and this document. Updated: snapshot/palette Codable declarations, bounded Store history read, auxiliary history hosting, two AppDelegate history refresh/open hooks, README. No persistence migration or live editor/action/docking/reveal policy change.

Main risks are uncompiled SwiftUI/AppKit signatures/actor isolation, native layout and accessibility, long-label wrapping, retained-window activation and real IME focus transitions. A single month's large snapshots load synchronously on the main actor; the 600-item production test verifies correctness, not UI latency or memory. No paging cache/performance project is added. Today highlighting refreshes on open/navigation/rollover, not through a separate midnight timer.

N9 can consume these immutable Codable DTOs and the existing schema6 repository, but must implement its own complete versioned backup/import validation and settings/hotkey/autostart workflows. All N1–N8 Mac gates remain outstanding; this patch establishes source/portable-test readiness for supervisor review, not native acceptance. Supervisor alone reviews and commits.
