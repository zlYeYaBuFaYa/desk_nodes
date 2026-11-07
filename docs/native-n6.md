# N6 daily rollover and wake catch-up

Patch baseline: **LOCAL authoring HEAD `5e9e958127a6d0c8555a065ac5b6f9696b9793c0`**, verified before editing in `/workspace/desknodes-macos-native`. This is a local authoring hash, not a claimed remote integration hash. Supervisor cherry-picks/commits can have different hashes; no remote lookup or equality claim was made. This patch is uncommitted for supervisor review/commit. No commit, push, rebase, tool installation, network repair or system-time-setting change was performed. Authoritative `docs/spec/macos-native/`, `docs/macos-native-plan.md`, and N1–N5 documents are unchanged. No old Tauri checkout/source/schema is modified or used.

## Architecture and atomic persistence

`BusinessDay.swift` adds an injectable Gregorian `BusinessCalendar` (timezone and calendar supplied explicitly), checkpoint DTO and rollover result. `Store` uses its existing injected clock; production defaults to `Date`. Persisted `Settings.rolloverHour/Minute` default to 04:00, validate 0…23 / 0…59, and are read on every rollover attempt. There is no N9 settings UI.

Ordered native migration **4 → 5** adds four tables: singleton `rollover_state(active_day, high_water)`, `item_archives(item_id, day)`, `pending_deleted_notes(note_id)` and `pending_deleted_items(item_id)`. Earlier native versions traverse the existing migrations first. The new DDL runs in the existing exclusive schema transaction; failed migration rolls back DDL/version and preserves sealed history. No prior columns, timestamps, content or snapshot rows are rewritten. Pending deletion membership is seeded from existing tombstones only if no prior snapshot already records that identity as deleted. There is no inference that a historical completed item was already archived.

`Store.rollover(using:prepareEditing:)` owns one `BEGIN IMMEDIATE` transaction (or a nested savepoint inside an existing transaction). It reads checkpoint/settings, checks the clock/day, runs the synchronous editing hook if due, inserts final snapshot children then the immutable sealing day header, inserts completed live item archive memberships, consumes pending deletion memberships and advances the checkpoint. Every effect commits together. A failed edit flush, child/header insertion, archival, membership consumption, checkpoint write or COMMIT propagates an error and rolls back. A false editing hook also rolls back any hook writes and returns `deferredEditing`. No suspension/dispatch/wait is allowed inside repository transactions.

Existing SQLite default DELETE rollback journal and FULL synchronous durability remain enabled; no unsafe journal/synchronous changes, WAL, reset, purge or partial recovery path. Reopening sees either the prior operation or the committed operation under SQLite's transaction guarantees. SQL fault injection/reopen tests were executed; destructive process-kill/power-loss testing was not executed. Primary keys enforce one day header, one item per snapshot/day, one note per snapshot/day and one archive membership per item. Separate connections serialize through SQLite's write lock; retries read the persisted checkpoint and do not duplicate capture/carry/archive rows.

The N2 history UPDATE/DELETE and sealed-child INSERT rejection triggers are preserved. Archive membership references its exact source snapshot item through a composite foreign key and also rejects SQL UPDATE/DELETE. Snapshot DTOs remain immutable. Public N2 `capture(day:carryingUnfinishedTo:)` remains an explicit caller-requested capture of all retained content; it is not the scheduler and does not consume pending deletion membership. It no longer marks archived rows as carried. The scheduler uses private daily membership selection instead. A caller sealing the active day behind an initialized scheduler causes an explicit conflict error, not silent archival against someone else's snapshot.

## Civil-day, missed-day and reversal policy

- The business day is today's local Gregorian date at/after the configured wall time, otherwise the preceding local date. It uses calendar date arithmetic, never a fixed 24-hour subtraction for local-day calculation. A DST gap boundary resolves to the **next valid local time** (02:30 → 03:00 in the tested LA spring gap); a fold uses the **first occurrence**. The second 01:30 never closes another day. The normal 04:00 boundary follows the new offset after DST.
- First startup establishes today's business-day checkpoint and creates **no past snapshots**, even if retained items already exist. They stay live until the next observed transition. If caller-authored history already seals today or a later date, initialization reserves the day after the latest sealed date and waits; it never overwrites or fills days behind that history.
- On a forward jump, seal **only the previously observed active day**, using the last known live statuses at catch-up. Carry each unfinished live item directly to the newly observed business day. Do not enumerate skipped dates, create target-day snapshots early, clone items, assign invented completion dates or fabricate user actions. A multi-day sleep has one source snapshot and one direct carry destination per unfinished item. `capturedAt` records actual catch-up time, not a fabricated old timestamp.
- An observed day with no notes/items still seals one empty snapshot when it closes. A live empty note is included with zero items. Dates never observed as active have no snapshot. Repeated notifications and restart cannot create duplicate empty snapshots.
- Persist both the active civil day and an absolute time high-water mark. An instant earlier than that mark does not modify checkpoint/history or archive anything, even if a timezone would imply a later day. An equal instant may process a legitimate forward timezone/date shift. A nondecreasing instant with a business date behind the checkpoint updates only the absolute high-water mark and holds the active day; it cannot backdate/seal an older day. Resume only when absolute time reaches the mark and the business date moves strictly beyond the active day. Setting the clock far into the future and back can consequently delay rollover until it catches up; there is no destructive automatic correction UI.
- A forward timezone/date shift may close the active day once and skip dates; shifting back holds instead of reopening sealed history. Boundary configuration changes obey the same monotonic rule. Production resolves the current timezone per trigger; no cached UTC offset or calendar locale formatter controls identity. No system timezone or clock is changed by the implementation/tests.

## Daily membership, deletion and restoration

Snapshot daily membership includes all live notes, their unarchived live items, and pending user-deleted notes/items. A deleted parent is included when it has pending deletion membership or pending children. Pending memberships are set atomically with soft deletion, removed on restoration, and consumed only by a successful rollover. Historical tombstones without pending membership and previously archived items are omitted from subsequent automatic daily snapshots. Deleting/restoring/deleting again creates fresh pending membership for the next observed day; sealed snapshots remain unchanged. This is a conservative final-status policy, not an event log of every transient edit/delete/undo within a day.

Completed live, nondeleted items are archived only after their final snapshot has been inserted in that same transaction. Their content/identity/order/completion/original timestamps stay in `items`; `item_archives` points to the sealed source day. `Item.archivedDay` exposes this status. `deletedAt` remains nil: **rollover archive is not user deletion**. Default live item queries exclude both archived rows and tombstones; `includeDeleted: true` means all retained rows, including archives. Updates/deletion/restoration of archived items through the repository are rejected. Deleting a parent note does not retimestamp or tombstone its already archived children.

Unfinished items stay in place with the same ID, text, order and timestamps; `SnapshotItem.carriedTo` records their direct destination. No carry clones or separate mutable carry counters exist. Live edits/completions/deletions after rollover cannot change snapshots. No note is automatically deleted, no content is physically purged, and no tomorrow group or history editing is added.

N3 five-second undo remains independent: deletion just before a boundary is recorded as deleted in the sealed snapshot; a still-eligible undo after the boundary restores the original live identity/content/order without rewriting that snapshot. A completed deleted item is not archived behind the undo slot. A deleted note's archived children remain archived when the note is restored, while its ordinary children restore normally; prior tombstones stay deleted. Expired undo cannot restore anything. Restart retains data/history/checkpoint but does not invent a new in-memory undo slot.

## Native scheduler and editing gate

`Application.swift` invokes catch-up before the initial live presentation, then retains a public Foundation `Timer` on the main run loop in common modes, every **30 seconds with 2 seconds tolerance**. This is modest eventual boundary processing, not a claim of exact wall-second scheduling. It also observes public `NSWorkspace.didWakeNotification`, `NSSystemTimeZoneDidChange` and `NSSystemClockDidChange`. Observers/timer are removed/invalidated on termination. No private APIs, event taps, extra permissions, system time changes or N7 edge behavior are introduced.

When forward rollover is due, the application first checks every card's NSTextViews and each panel's first responder, including NSTextField's shared title field editor. **Any marked composition defers the whole rollover.** It never forces an IME commit/cancel, overwrites marked strings, removes the composing row or advances the checkpoint. A text-change notification after deferral retries on the next run-loop turn; the timer also retries after cancellation/end-editing without a notification. Compositions can therefore intentionally delay archival. A guard prevents reentrant rollover, and text-change retries are enabled only after a deferral, avoiding a checkpoint write per ordinary keystroke.

Once all editors are unmarked, `NoteCardView.flushRolloverEdits()` persists differences in committed title/item text inside the rollover transaction, without invoking refresh callbacks or altering deletion-undo state. It breaks text undo coalescing. Only successful archival invokes the existing stable-ID refresh: completed archived rows leave, count/untitled fallback/automatic height/dock layout update, and unfinished editors retain their instances/text storage/selection. A focused disappearing editor relinquishes first responder before removal; its target undo actions are removed. No archival code rebuilds surviving editors or reloads their strings. Actual AppKit first-responder/undo and real IME event ordering are **native acceptance gates**, not established by portable callback tests or syntax parsing.

## Executed Linux validation

Official already-installed **Swift 6.2.1**, x86_64 Linux, production persistence/action code and host system SQLite. All test stores use isolated on-disk temporary SQLite files and injected clocks; none uses the production path helper. No Python substitute for business logic or SQLite testing.

```sh
cd /workspace/desknodes-macos-native
export PATH=/workspace/desknotes/toolchains/swift-6.2.1-RELEASE-ubuntu24.04/usr/bin:$PATH
export LD_LIBRARY_PATH=/workspace/desknotes/toolchains/apt/local/usr/lib/x86_64-linux-gnu
swift --version
swift package clean
swift test -Xcc -I/workspace/desknotes/toolchains/apt/local/usr/include \
  -Xlinker -L/workspace/desknotes/toolchains/apt/local/usr/lib/x86_64-linux-gnu
swift package describe
ldd .build/x86_64-unknown-linux-gnu/debug/DeskNodesPackageTests.xctest
python3 scripts/check-n1.py
bash -n scripts/build-macos.sh
swiftc -frontend -parse Sources/DeskNodesApp/*.swift Tests/DeskNodesAppTests/*.swift
git diff --check
git diff --exit-code HEAD -- docs/spec/macos-native docs/macos-native-plan.md \
  docs/native-n1.md docs/native-n2.md docs/native-n3.md docs/native-n4.md docs/native-n5.md
```

**74 XCTest tests pass, zero failures**: 16 new production persistence rollover tests + 2 new action/undo compatibility tests + 56 prior tests. Suite totals: 31 persistence (15 existing + 16 rollover), 39 actions/state/docking (37 existing + 2 rollover compatibility), 4 core. The separate Swift Testing runner reports zero because these are XCTest tests. SQLite linkage is verified with `ldd`; test SQL uses the actual production SQLite bridge.

Coverage: 03:59/04:00, persisted nondefault 05:30 and reopen, repeat/restart/two connections, multi-day sleep/direct carry/no intervening rows, first startup/no invented past, observed empty day, LA DST gap/fold/default 04:00, forward/back timezone/date shift, absolute reversal and restart, boundary changes, immutable archive vs deletion/carry, nonrepeated tombstones, retained content, existing caller snapshots, v4→v5 migration and failed-DDL rollback, and failure injection at snapshot item/header, archive insert, both pending-membership deletes and checkpoint update. Each fault verifies rollback of edit flush/live rows/checkpoint/history/archive/pending state, then reopens/retries and checks foreign keys/integrity/default durable journal settings. Editing hook deferral (including rollback of hook writes), thrown save failure and final committed text are tested in production Swift. Deletion tests cover item/note undo across boundaries, archived children, expired undo and unchanged history.

The first incremental run after changing `Item` layout produced six malformed-ID assertions; a clean SwiftPM rebuild passed all 56 prior tests. The final suite runs after clean rebuilding. No production ID generation workaround or altered assertions masked those failures. The existing v1/v2/v3 migration expectations now require schema 5; the v3 fixture drops the newly added N6 tables when reconstructing a genuine pre-N6 database.

Static checks: unchanged N1 checker (33 assertions plus shell parse), independent shell syntax, manifest target description, native source/test frontend syntax parse, diff whitespace and unchanged authoritative/plan/prior-doc paths all pass. **Frontend parsing is not AppKit SDK typechecking.** Linux excludes AppKit and native XCTest targets. There are eight native XCTest methods, including a new rollover test with synthetic marked completed text, deferred capture, committed flush and retained unfinished editor/selection. They are uncompiled/unrun here and do not replace real IME acceptance.

Logs are external at `/workspace/desknotes/logs/native-n6-tests.log`, `native-n6-environment.log`, `native-n6-static.log`, `native-n6-native-parse.log`, `native-n6-review.log`; reproducible static/environment runner `native-n6-checks.sh`. Exploratory logs `native-n6-first-tests.log` and `native-n6-clean-baseline.log` retain the initial incremental failure and clean prior-suite success. No native binary or screenshot was produced.

## Exact Mac acceptance — all unexecuted

On macOS 14+ with compatible selected Xcode, record OS/Xcode/architecture and actual results:

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

Use a separate Mac test user/database; never delete/replace an existing production database. Do not change system time/timezone to manufacture passing evidence. Run fixed-clock calendar tests above on Mac for reversal/DST/date jumps; physical runtime tests may wait for the real configured boundary. Boundary controls remain N9; the default app boundary is 04:00 unless a test fixture sets persisted settings.

1. **Build/native tests:** compile AppKit/SwiftUI/scheduler APIs and run the complete suite including all eight native XCTest methods. Check startup accessory menu/no Dock icon, database migration from a copy of native schema 4 and retained history. Linux parse cannot establish SDK signatures, actor isolation, linking or signing.
2. **Live day change:** before real 04:00 create completed and unfinished rows in free/docked/collapsed notes, including a completed focused editor. Stay active through the boundary. Within timer tolerance, completed rows disappear once, count/fallback/height/dock overflow refresh, unfinished content/order/caret/selection remain; no hidden first responder accepts typing into an archived row. Command–Z/redo must not resurrect an archived item or apply edits to a detached editor. The app must still support ordinary text undo in surviving rows and adding new items to an empty note.
3. **Critical Chinese IME gate:** with Apple Simplified Chinese Pinyin, start marked text in a completed row before the boundary, keep candidates active past it, and repeat with an unfinished row and the optional title field. Candidate window, marked range, text, selection and focus must survive timer/wake/time notifications. No row removal or checkpoint advance until composition commits/cancels. Return accepts a candidate without splitting/adding a row. After commit, rollover should capture the committed text once; after cancellation it should capture final surviving text. Repeat appearance changes, dock/resize/reorder and no-text-change cancellation; the latter may wait for the timer. Test multiple cards with a marked editor on a nonkey panel. A failure blocks native acceptance even if Linux tests pass.
4. **Sleep/wake/startup:** leave completed and unfinished rows, sleep across the real boundary and wake. Confirm one catch-up, unfinished continuity, no repeated archival on subsequent wakes/timer events. Quit before a boundary and relaunch after it; checkpoint/history persist. Multi-day sleep/restart must follow the direct-carry policy, without invented intermediate snapshots. The injected-clock suite provides deterministic long-gap evidence; actual wake notification delivery remains a physical Mac test.
5. **Deletion/undo:** delete an item or note within five seconds before rollover; restore by toast and Command–Z after it while still eligible. Original live identity/order/content returns; sealed deleted status remains. Repeat with a note containing earlier tombstones and archived children; only ordinary children restore. Let undo expire and restart: deleted content stays retained, no live resurrection. Delete all notes, cross a boundary, use menu/empty-flow create. No repeated historical tombstones on later automatic captures.
6. **Notifications/errors:** exercise public notification handling in a debug test harness without changing system settings; verify timezone resolution is refreshed and common-mode timers do not stop permanently during menus/drag. Fault the isolated test store, confirm errors surface and rollback preserves rows/checkpoint; restore access and retry without duplicates. Automatic clock-reversal recovery and unexpected composition/event timing must be recorded as unverified until actually exercised.
7. **Regression/visual:** re-run N3–N5 editor/undo/docking/monitor/Spaces acceptance and compare real light/dark native captures to prototype 03. No ordinary note should appear over other apps' fullscreen. There is still no N7 reveal panel. No native screenshot fidelity is claimed by this patch.

## N7 readiness and remaining risks

N7 can read the same live store (archives already filtered), retain stable item editors, and reuse the composition/flush discipline. It must extend the rollover editing check to **every new reveal-panel editor/field editor** before enabling another shared editing surface; N6 knows only current note panels. Duplicate view refresh/focus/undo between note and reveal windows remains N7's responsibility. Do not use the explicit all-retained N2 capture API as a scheduler or use retained rows as a live reveal list.

N7 edge/topology/dwell/fullscreen behavior, N8 read-only history UI, N9 boundary controls/backup/hotkey/autostart and N10 final native acceptance remain unimplemented. Future complete backup must include schema-5 checkpoint, archive and pending-membership state alongside existing data/history/settings. Risks: uncompiled AppKit API integration, real title/item IME/undo focus sequencing, timer/wake notification delivery and native geometry/visual acceptance. A far-future bad clock can hold rollover conservatively for a long time. SQLite transactions protect crash consistency; actual process-kill/power-loss testing has not been performed. No quota fallback or supervisor substitute coding was used; supervisor owns review and commit.
