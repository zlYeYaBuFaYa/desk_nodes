# DeskNodes — native macOS

Swift + AppKit, macOS 14+, Chinese UI, local system SQLite, no third-party packages. The native app implements N1–N6: persisted note editing and five-second deletion undo, palette/chrome/levels/collapse/sizing, docking and monitor recovery, and daily rollover with wake/startup catch-up. History and Settings remain explicit unfinished placeholders; boundary settings already persist in the model, with controls reserved for N9.

On a Mac with compatible Xcode selected:

```sh
xcrun swift test
./scripts/build-macos.sh
open build/DeskNodes.app
```

[N6 architecture, policies, executed checks and exact Mac gates](docs/native-n6.md): **74 production portable XCTest tests pass** on Linux with Swift 6.2.1 and real isolated SQLite files. Default rollover is 04:00 local Gregorian time. Completed items leave live lists into sealed daily snapshots; unfinished items keep their IDs and record carry continuity. Missed days close only the last observed active day, carrying directly to today; no intermediate snapshots or invented completions. An observed empty day seals once. Deleted content is retained, with one pending deletion membership rather than repetition in all future days. Clock/date reversal holds the checkpoint. Rollover defers during marked IME composition, then flushes committed text before archival.

Native frontend syntax parsing passes. **AppKit typechecking/build/signing, timer/wake notification runtime, real Chinese IME/focus/undo and native screenshots remain unexecuted Mac gates.** No Mac SDK stubs or simulated native screenshots. The timer checks every 30 seconds with 2 seconds tolerance; wake/timezone/system-clock notifications also request catch-up.

Storage: `~/Library/Application Support/local.desknodes.native/DeskNodes.sqlite3`. Native schema 5 preserves sealed N2 history and separates rollover archival from user tombstone deletion. No purge, Tauri discovery/import/migration, hide or tomorrow features. See [N2 storage/environment](docs/native-n2.md), [N5 docking](docs/native-n5.md), [N4 geometry/levels](docs/native-n4.md), [N1 build entry](docs/native-n1.md), [authoritative spec](docs/spec/macos-native/README.md) and [milestone plan](docs/macos-native-plan.md).

N6 is an uncommitted supervisor-review patch on **LOCAL authoring HEAD `5e9e958127a6d0c8555a065ac5b6f9696b9793c0`**. Remote integration/cherry-pick hashes can differ and are not inferred or verified here. No commit/push/rebase was performed; authoritative specs, plan, prior milestone documents and old Tauri checkout are untouched. N7 can reuse the shared live store and composition gate; N7–N10 remain pending.
