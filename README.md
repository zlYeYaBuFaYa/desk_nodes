# DeskNodes

macOS 14+ Swift/AppKit native foundation (N1). The current note is an editable, temporary preview; it does not save data. History and Settings are explicitly unfinished SwiftUI placeholders.

On a Mac with Xcode 15+ selected:

```sh
xcrun swift test
./scripts/build-macos.sh
open build/DeskNodes.app
```

Build/signing details, portable checks, limitations and exact native acceptance steps: [N1 delivery](docs/native-n1.md). Full specification: [spec index](docs/spec/macos-native/README.md). Milestones: [native plan](docs/macos-native-plan.md).

Linux delivery has only static validation; AppKit compilation, Swift tests and native runtime acceptance have not been performed.
