# DeskNodes

macOS 14+ Swift/AppKit notes with native SQLite persistence (N1–N3). Optional titles, editable/checkable items, same-note drag reorder, and five-second deletion undo are implemented. History, Settings and all-topmost remain honest unfinished placeholders.

On a Mac with Xcode 15+ selected:

```sh
xcrun swift test
./scripts/build-macos.sh
open build/DeskNodes.app
```

[N3 architecture, actual test evidence and Mac acceptance](docs/native-n3.md) describes the current behavior and remaining gates. Linux passed **31 production portable XCTest tests** with official Swift 6.2.1 and system SQLite; AppKit compilation, Chinese IME runtime, signing and native visual acceptance remain unexecuted.

Storage is native-only under `~/Library/Application Support/local.desknodes.native/DeskNodes.sqlite3`. No Tauri discovery, import, migration, hide or tomorrow features. [N2 storage policies](docs/native-n2.md), [N1 build entry](docs/native-n1.md), [authoritative spec](docs/spec/macos-native/README.md), [milestone boundaries](docs/macos-native-plan.md). N3 supersedes the old N1 temporary-preview behavior; window sizing, levels, hover chrome, palette selection and collapse await N4.
