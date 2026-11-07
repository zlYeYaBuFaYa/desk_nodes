# DeskNodes

macOS 14+ Swift/AppKit notes with native SQLite persistence (N1–N4). Optional titles, editable/checkable items, same-note drag reorder, and five-second deletion undo are implemented. N4 adds hover chrome, eight-color context palette, desktop/ordinary/topmost levels, pin, all-topmost/restore, free sizing and collapse. History and Settings remain explicit unfinished placeholders.

On a Mac with Xcode 15+ selected:

```sh
xcrun swift test
./scripts/build-macos.sh
open build/DeskNodes.app
```

[N4 design/state choices, exact tests and Mac acceptance](docs/native-n4.md) describes the current behavior and remaining gates. Linux passed **39 production portable XCTest tests** with official Swift 6.2.1 and system SQLite; AppKit compilation, Chinese IME runtime, signing and native visual acceptance remain unexecuted.

Storage is native-only under `~/Library/Application Support/local.desknodes.native/DeskNodes.sqlite3`. No Tauri discovery, import, migration, hide or tomorrow features. [N2 storage policies](docs/native-n2.md), [N1 build entry](docs/native-n1.md), [authoritative spec](docs/spec/macos-native/README.md), [milestone boundaries](docs/macos-native-plan.md). N3 supersedes the old N1 temporary-preview behavior; N4 supersedes N3’s fixed geometry. N5 docking/display topology and N7 edge reveal remain pending.

N4 is an uncommitted supervisor-review patch on LOCAL patch-authoring HEAD `02b0d762c306365f8b59223202321374cc83f0cd`; remote cherry-pick hashes differ. All-topmost is a session override preserving durable individual choices. Native window levels/Spaces/fullscreen exclusion, focus/IME, Core Animation and light/dark screenshots remain **UNVERIFIED user Mac gates**. No commit/push/rebase/force operation was performed.
