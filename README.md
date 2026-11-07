# DeskNodes — native macOS

Swift + AppKit, macOS14+, Chinese UI, local system SQLite, no third-party packages. N1–N8 source implements persisted notes, deletion undo, chrome/levels/collapse, docking/monitor recovery, daily rollover, fullscreen edge reveal and a read-only SwiftUI history calendar. Settings remains unfinished; N9–N10 are pending.

On a Mac with compatible Xcode selected:

```sh
xcrun swift test
./scripts/build-macos.sh
open build/DeskNodes.app
```

[N8 implementation, data/rate semantics and focused Mac acceptance](docs/native-n8.md): **99 production portable XCTest tests pass** on Linux with Swift6.2.1 and isolated real SQLite files. Native source/test syntax parsing and static/shell/spec-preservation checks pass. **AppKit SDK typechecking/build/signing, fullscreen/Spaces/global pointer visibility/permissions, focus, real IME/native undo and native visuals remain unexecuted Mac gates.** No native app was launched on Linux and no screenshot substitute was produced.

Reveal uses a dedicated nonactivating NSPanel with fullscreen auxiliary behavior; ordinary notes/dock tabs/toast retain fullscreen exclusion. All live notes scroll vertically through shared store/actions/IDs/deletion undo. Exterior left/right middle60% triggers after 0.25s dwell; exit waits 0.4s, moving down inside never dismisses, and marked composition holds the panel open and defers rollover. Public mouse-position polling uses no taps/global key monitors or added permission requests. This is **not a tested permission-free fullscreen interaction claim**. Only read-only Dock orientation preferences are consulted: bottom/left → right, right → left, unknown → right. A persisted manual-side foundation exists; full controls remain N9.

[N6 rollover policy](docs/native-n6.md) remains: 04:00 local boundary, immutable final daily snapshots, completed archival and unfinished same-ID carry; missed days close only the last observed day, with no invented intermediate actions. N7 extends the composition gate to both surfaces and prevents passive stale editors from overwriting newer shared text.

Storage: `~/Library/Application Support/local.desknodes.native/DeskNodes.sqlite3`. Native schema6 adds automatic/left/right edge preference while preserving schema5 rollover/history. No purge, Tauri discovery/import/migration, hide or tomorrow feature. See [N2 storage](docs/native-n2.md), [N5 docking](docs/native-n5.md), [N4 windows](docs/native-n4.md), [N1 build entry](docs/native-n1.md), [authoritative specification](docs/spec/macos-native/README.md) and [milestone plan](docs/macos-native-plan.md).

N8 is an **uncommitted supervisor-review patch on LOCAL `33905b0`**. No commit/push/rebase was performed. Specs, plan, prior milestone docs and old Tauri checkout are preserved. Logs: `/workspace/desknotes/logs/native-n8*`. History uses sealed daily snapshots only, with actual carry/deleted badges, daily counts and monthly weighted completion; missing dates and zero-total rates never fabricate progress. N9 backup must include the complete schema6 state; Codable snapshot DTOs are not a backup format. Supervisor owns review and commits.
