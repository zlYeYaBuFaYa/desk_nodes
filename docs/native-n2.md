# N2 domain and persistence foundation

Baseline: `ff8e0797367e3bf83270f1ca99795f5988f6f02c`. Read the committed `docs/macos-native-plan.md` and `docs/spec/macos-native/requirements.md`. N2 only; no commits or pushes. N1 application sources and its in-memory preview remain unchanged. The old Tauri checkout/source/schema have not been used or modified. This document supersedes N1's tooling limitation only for portable Swift tests; it does not establish Mac acceptance.

## Files and boundary

- `Sources/DeskNodesPersistence/Models.swift`: typed UUID note/item identities, fixed singleton settings identity, note/item records, placement, levels, civil history-day identity and read-only snapshot records; optional production data-path helper.
- `SQLite.swift`: system SQLite prepared statements, explicit UTF-8 byte lengths, 64-bit integer binding, error propagation and deterministic statement/connection cleanup.
- `Schema.swift`: atomic, ordered native migrations and SQLite history sealing triggers.
- `Store.swift`: synchronous serialized CRUD, settings, soft deletion, nested transactions/savepoints, explicit snapshot capture/read, injectable clock.
- `Sources/CSQLite`: system header/module map; no bundled SQLite source/binary or external Swift package dependency.
- `Tests/DeskNodesPersistenceTests/StoreTests.swift`: isolated temporary on-disk databases using the production Swift repository, including actual close/reopen and SQL fault injection.
- `Package.swift`: separate portable library/test target. AppKit/SwiftUI executable and native tests remain inside the existing macOS manifest conditional. The app does not depend on or open the new store yet.

## Data policy

The opt-in production path is `~/Library/Application Support/local.desknodes.native/DeskNodes.sqlite3` on macOS. The helper creates its own directory with mode 0700 on creation, uses Foundation's user Application Support resolution, and never searches other products' directories. `Store(url:)` requires an explicit URL and does not create missing parent directories. Tests never call the production-path helper. There is no automatic production database opening, fixture seeding, legacy discovery, migration or import.

SQLite owns local durable storage. Use the system SQLite library; the module map uses `<sqlite3.h>` and `-lsqlite3`. Foreign keys are enabled per connection; writes use `BEGIN IMMEDIATE`, schema changes `BEGIN EXCLUSIVE`, with a 5-second busy timeout. Ordinary SQLite rollback-journal/default FULL synchronous behavior is retained, without WAL sidecars, custom durability shortcuts or destructive recovery. Connections are serialized by a recursive lock and SQLite FULLMUTEX. Do not suspend, dispatch to another thread, or wait for another thread accessing the same store inside a transaction closure. Nested closures use savepoints. Commit errors propagate and attempt rollback. Close inside a transaction is rejected; use after close throws. Repository connections must be closed before copying a database file; no backup service ships in N2.

UUIDs are generated once, typed separately for notes/items, never reused or reassigned by update. Settings identity is always `native-settings`. Titles preserve nil versus empty, text preserves Chinese, combining characters, emoji, newlines and embedded NUL bytes without normalization. Order is a nonnegative signed 64-bit value (Swift Int on supported hosts), with UUID text as deterministic tie-breaker. Duplicate positions are allowed: N3/N5 will choose contiguous positions and perform grouped reorder writes in a transaction. Items retain their parent identity; no cross-note transfer API exists.

Placement stores dock edge (top/left/right) or a free frame plus optional opaque display identifier; nil means primary-display preference. Coordinates are points, negative origins permitted, dimensions positive and finite. N2 does not clamp to screen topology or UI size limits; N4/N5 own those rules and display-disconnect behavior. Notes persist desktop/ordinary/topmost preference, collapsed state, color and order without performing window operations. Settings persist 04:00 default boundary and dock/display preference; no scheduler, registration, autostart, all-topmost behavior or settings UI is added.

The clock is an injected `() -> Date`, defaulting to `Date.init`. Nonfinite clock values are rejected. Timestamps are Unix seconds stored as REAL. This layer does not infer day/timezone from the clock and does not implement clock-reversal, DST, sleep/wake or catch-up scheduling.

Deletion is soft and transactional. Note deletion timestamps the note and still-live children together; previously deleted children's timestamps/content survive. Live queries exclude deleted rows by default, retained queries expose tombstones, and updates of deleted rows are rejected. No purge, cascade destruction or 5-second undo service is implemented. N3 can add explicit restoration/actions against these retained identities; deleted content is available for that work.

## Schema and history policy

`PRAGMA application_id = 0x44534B4E` identifies this native product; `user_version = 2` is current. Version 0 is accepted only for an empty, unclaimed database. Native version 1 creates notes/items/settings; version 2 adds days/snapshot notes/snapshot items and sealing triggers. Version 1 is an internal native migration baseline, not any Tauri version. Each opening migrates transactionally and checks foreign keys. Failed DDL rolls back both tables and version; future versions and unrelated/unclaimed nonempty databases are rejected without attempted conversion. Unknown/corrupt files are surfaced as errors rather than reset or replaced. Future releases must add ordered migrations, not reinterpret this schema in place.

Snapshot identity is the validated Gregorian `YYYY-MM-DD` key supplied by the caller. Capture atomically copies the entire current retained dataset: note title/color/order/deletion marker, and item identity/content/final completion/order/deletion marker. Snapshot DTO fields are immutable. Live edits, reorder and later deletion cannot rewrite the copied fields. SQL triggers also reject UPDATE/DELETE of history and insertion of children into a sealed day. Child foreign keys are deferred during capture and the day header is inserted last to seal it; rollback cannot leave a partially sealed day. There is no history editing API.

Repeated capture of a committed day returns that original snapshot, even if live state or a retry's carry argument differs. An optional strictly later civil day records `carriedTo` only for unfinished, nondeleted items in nondeleted notes. The same item ID links continuity; no clone, move, removal of completed live items, target-day snapshot or scheduled rollover occurs. N6 must atomically combine its live changes with capture using `transaction` and choose timezone/boundaries/missed-day policy. Carry destination must be known at capture; it cannot be patched afterward.

Conservative N2 capture is a caller-requested snapshot of *current* retained rows, not reconstruction of an arbitrary past day. Tombstones are retained indefinitely and included on each explicit capture, so no deletion disappears before N6 defines daily membership. Callers must not use this primitive to fabricate pre-creation or missed-day actions. N6 should define membership/catch-up policy explicitly before extending capture selection; N8 can derive later deletion badges from tombstones while preserving original snapshot fields. Later deletion deliberately does not mutate the earlier day's deletion marker.

## JSON policy

SQLite is authoritative. Only placement uses an internal Foundation Codable JSON value inside a SQLite TEXT column; its encoding is governed by the enclosing native schema version. This is not a public backup document, legacy parser or interoperable Tauri format. No import/export service, file picker, backup schema contract, arbitrary settings JSON or N9 UI exists. Reserve a separately versioned native JSON envelope for N9 (initial planned format version 1); define and validate that full-backup contract then, including IDs, settings, tombstones, history, ordering and rollback. Do not export raw SQLite internal placement strings as an accidentally frozen public contract. No compatibility with old Tauri JSON/schema is assumed.

## Executed Linux validation

Host: Debian 13, x86_64. No Swift on PATH initially; system `libsqlite3.so.0` existed, headers and unversioned linker name did not. The official [Swift Linux installation index](https://www.swift.org/install/linux/debian/13/) was inspected and saved externally. An official released Swift 6.2.1 Ubuntu 24.04 x86_64 tarball was successfully downloaded over HTTPS from:

`https://download.swift.org/swift-6.2.1-release/ubuntu2404/swift-6.2.1-RELEASE/swift-6.2.1-RELEASE-ubuntu24.04.tar.gz`

It was extracted only under `/workspace/desknotes/toolchains`; it runs on this host with locally extracted Debian `libncurses6`. `apt-get download libsqlite3-dev` initially failed due absent package indexes. An isolated apt index attempt failed with HTTP 500 on the configured Debian HTTP repositories. No trust checks were disabled or system package installed. The regular Debian HTTPS package index and `libncurses6`/`libsqlite3-dev` packages were then downloaded and extracted into the same tools directory. The extracted unversioned SQLite linker symlink resolves to the host's existing `/usr/lib/x86_64-linux-gnu/libsqlite3.so.0.8.6`. There are no Mac API stubs, credential accesses, app launches, proxy changes or repository vendored dependencies.

Exact successful final test commands (run from this repository):

```sh
export PATH=/workspace/desknotes/toolchains/swift-6.2.1-RELEASE-ubuntu24.04/usr/bin:$PATH
export LD_LIBRARY_PATH=/workspace/desknotes/toolchains/apt/local/usr/lib/x86_64-linux-gnu
swift --version
swift package clean
swift test -Xcc -I/workspace/desknotes/toolchains/apt/local/usr/include \
  -Xlinker -L/workspace/desknotes/toolchains/apt/local/usr/lib/x86_64-linux-gnu
ldd .build/x86_64-unknown-linux-gnu/debug/DeskNodesPackageTests.xctest
```

Result: **16 XCTest tests passed, zero failures** (12 production persistence tests + 4 existing core tests). Swift 6.2.1, target `x86_64-unknown-linux-gnu`. The XCTest binary dynamically links the system `libsqlite3.so.0`. App/native test targets were excluded on Linux. The separate Swift Testing runner reports zero tests because these tests use XCTest; the 16-test XCTest summary is the evidence.

Coverage: CRUD/reopen, Unicode/NUL, optional title, settings/defaults, free/dock placement/levels/order, full-width integer order, injected/invalid clock, retained deletion, isolation, closed store, nested rollback across live data/settings/history, capture failure after partial children with successful retry, native v1→v2 migration with retained rows, migration DDL/version rollback, rejection of future/foreign databases, SQL-level immutable/sealed history, final content/title/color/order/completion preservation after edits/deletion/reopen, unfinished-only carry, and idempotency across two real connections. These are production Swift tests, not a Python logic reimplementation.

Additional executed checks: `swift package describe` (portable targets only on Linux), `python3 scripts/check-n1.py`, `bash -n scripts/build-macos.sh`, `git diff --check`, and an unchanged-path diff against HEAD for N1 source/tests and authoritative specifications. SwiftPM emitted pkg-config lookup warnings because pkg-config is absent here; the explicit header/linker flags above supplied the missing development search paths and compilation/linking succeeded. No installer or dependencies were added to the repository.

External evidence lives in `/workspace/desknotes/logs/native-n2*`: install attempts, official index, Swift version, final Swift test output and review/environment checks. The first exploratory 14-test build used the extracted Debian SQLite static archive; the final clean 16-test build above uses the host shared library. No macOS compilation or runtime result is claimed.

## Exact user Mac checks (unexecuted here)

On macOS 14+ with selected Xcode 15+/Swift 5.9+ and its SDK/system SQLite headers, from the actual checkout path:

```sh
cd /workspace/desknodes-macos-native
xcode-select -p
xcodebuild -version
xcrun swift --version
xcrun swift package dump-package
xcrun swift test --filter DeskNodesPersistenceTests
xcrun swift test --filter DeskNodesCoreTests
xcrun swift test --filter NativeFoundationTests
./scripts/build-macos.sh
```

All commands above remain **unexecuted on Mac**. SwiftPM may build native targets on Mac even with a test filter; Linux excludes them at manifest evaluation. Mac system SQLite module/linking, AppKit compile/signing, real IME, window behavior and N1 screenshot acceptance remain user-Mac gates per `docs/native-n1.md`. No app launch was performed on this host.

N3 readiness: the independent store can now be injected into the panel presentation layer without changing the N1 preview in this patch. N3 still owns UI binding, structural NSTextView editing, undo actions/expiry and last-note creation. N6 owns day scheduling/live archival and the explicit membership policy above. No N3–N10 feature is claimed complete.
