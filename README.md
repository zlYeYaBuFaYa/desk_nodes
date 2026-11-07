# DeskNodes

macOS 14+ Swift/AppKit native foundation (N1) with an independent SQLite domain/persistence library (N2). The current note is an editable, temporary preview; it does not save data. History and Settings are explicitly unfinished SwiftUI placeholders.

On a Mac with Xcode 15+ selected:

```sh
xcrun swift test
./scripts/build-macos.sh
open build/DeskNodes.app
```

Build/signing details, portable checks, limitations and exact native acceptance steps: [N1 delivery](docs/native-n1.md). Full specification: [spec index](docs/spec/macos-native/README.md). Milestones: [native plan](docs/macos-native-plan.md).

N2 storage policies, production Swift test evidence and exact Mac validation commands: [N2 delivery](docs/native-n2.md). Linux ran 16 portable XCTest tests successfully using an official Swift toolchain and system SQLite. AppKit compilation and macOS runtime acceptance remain unexecuted. The application preview is not yet wired to persistence (N3).
