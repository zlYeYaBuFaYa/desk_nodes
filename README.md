# DeskNodes

macOS 14+ Swift/AppKit notes with native SQLite persistence (N1–N5). Optional titles, native item editing, same-note reorder, five-second deletion undo, levels, collapse and free sizing are implemented. N5 adds top/left/right docking, overflow tabs, drag reorder/detach/snap and monitor recovery. History and Settings remain unfinished placeholders; limited monitor/edge selection lives in the menu-bar docking controls.

On a Mac with compatible Xcode selected:

```sh
xcrun swift test
./scripts/build-macos.sh
open build/DeskNodes.app
```

[N5 design choices, validation and exact Mac gates](docs/native-n5.md) describes current behavior. **56 production portable XCTest tests pass** on Linux using official Swift 6.2.1 and actual system SQLite. Native frontend syntax parsing passes; AppKit typechecking/runtime, monitor hardware, Chinese IME/focus, Spaces/fullscreen, signing and screenshot fidelity remain **unexecuted Mac acceptance gates**. No Mac SDK stubs or simulated native screenshots.

Storage is native-only under `~/Library/Application Support/local.desknodes.native/DeskNodes.sqlite3`. No Tauri discovery/import/migration, hide or tomorrow features. See [N2 storage/environment](docs/native-n2.md), [N4 geometry/levels](docs/native-n4.md), [N1 build entry](docs/native-n1.md), [authoritative spec](docs/spec/macos-native/README.md) and [milestone plan](docs/macos-native-plan.md). N6 rollover and N7 fullscreen edge reveal remain pending.

N5 is an uncommitted supervisor-review patch on **LOCAL authoring HEAD `5e935c043787fab5e7fa113459fd17b2f3059deb`**. Remote integration/cherry-pick hashes differ and are not inferred here. No commit/push/rebase was performed; authoritative specs and Tauri checkout are untouched. All-topmost remains a session override preserving individual durable levels.
