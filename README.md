# DeskNodes — native macOS

Swift + AppKit, macOS14+, Chinese UI, local system SQLite, no third-party packages. N1–N9 source implements notes/deletion undo, chrome/levels/collapse, docking/display recovery, daily rollover, fullscreen edge reveal, read-only History, lazy SwiftUI Settings, configurable Carbon new-note shortcut, first-launch login consent and full native JSON backups. N10 native acceptance/fidelity remains pending.

On a Mac with compatible Xcode selected:

```sh
xcrun swift test
./scripts/build-macos.sh
open build/DeskNodes.app
```

[N9 implementation, backup contract and focused Mac acceptance](docs/native-n9.md): **118 production portable XCTest tests pass** on Linux with preinstalled Swift6.2.1 and isolated real SQLite stores. Static/shell/native syntax/diff/spec checks pass. **Mac Carbon/SMAppService/SwiftUI/AppKit SDK typecheck/build/signing, dialogs/permissions, real IME/native undo/focus, autostart runtime and native visuals remain UNVERIFIED.** Fifteen native test methods are present but uncompiled/unrun on Linux. No OS hotkey/login registration runs on Linux.

Settings provides rollover **04:00**, valid hours0–23/minutes0–59, docking side/display, edge automatic/manual and current Dock/fallback explanation. Default shortcut is **Control+Option+N**; enter modifier names joined by `+` and a physical ANSI letter/digit/Space, then Apply. Conflicts preserve the old binding. First launch **asks** before `SMAppService.mainApp` registration; persisted decline is respected. Imported consent never changes OS registrations. Default build signing is local ad-hoc; **login-item acceptance is not guaranteed unsigned/ad-hoc**. See N9's stable bundle path, optional existing local signing identity and approval/logout-login gate.

Settings → 数据 → 导出… saves a full versioned **native** JSON backup through a native save dialog. 导入… validates all data in isolation, then requires explicit destructive confirmation before atomic replacement. It covers retained notes/items/tombstones, immutable history, order/placement/settings, archives, checkpoint, pending deletion memberships, carry and new preferences. Invalid/incompatible/cancelled import leaves data unchanged. Marked composition refuses import/export; export flushes owning committed edits. Successful import retires stale editors/native and shared undo and refreshes History. **No Tauri compatibility is assumed.** Keep a backup before replacement; imported login intent is not an OS registration.

Storage: `~/Library/Application Support/local.desknodes.native/DeskNodes.sqlite3`. Native schema7 adds preferences while preserving schema6 edge/history/rollover data. No Tauri discovery/migration, hide/tomorrow feature or cloud sync. [N6 rollover](docs/native-n6.md) and [N7 reveal/shared-editing](docs/native-n7.md) policies remain, including direct carry across skipped days and all-surface composition gating. Only the reveal panel has fullscreen auxiliary behavior. Public read-only Dock orientation is best-effort; missing/unknown → right reveal. Native Spaces/pointer/focus behavior still needs acceptance.

[History](docs/native-n8.md), [storage](docs/native-n2.md), [docking](docs/native-n5.md), [windows](docs/native-n4.md), [build entry](docs/native-n1.md), [authoritative specification](docs/spec/macos-native/README.md), [milestone plan](docs/macos-native-plan.md).

N9 is an **uncommitted supervisor-review patch on LOCAL `7a9a0e9`**. No commit/push/rebase performed. Specs, plan, prior docs and old Tauri checkout are preserved. Logs and reproducible runner: `/workspace/desknotes/logs/native-n9*`. Supervisor owns review and commits; Linux results do not establish Mac acceptance.
