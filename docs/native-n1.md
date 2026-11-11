# N1 native foundation — delivery and Mac acceptance

Source baseline: `431bce8f76a6d4f3e7948b6bd3542eb4b9ce9ec1`, branch `cursor/macos-native-desknodes`. N1 only. This delivery was written and statically checked on Linux; no Swift compiler was found on PATH or at `/usr/local/swift/usr/bin/swift` or `/opt/swift/usr/bin/swift`. No Swift manifest evaluation, Swift tests, AppKit compilation, native screenshots, signing, or app launch has been performed. No tool installation or network repair was attempted.

## Architecture and scope

- `Package.swift`: Swift tools 5.9+, macOS 14 minimum, no external dependencies. `DeskNodesCore` and its XCTest target are platform independent. The executable and its separate native XCTest target exist only when the manifest runs on macOS. There is no invented Xcode project, Linux app, WebView, or app framework shim.
- `Sources/DeskNodesCore/DesignTokens.swift`: all eight named light/dark sRGB pairs, prototype-03 paper ink roles, geometry, reduced-motion policy, and a future structural-command composition boundary. `32pt` collapsed height is a reserved token, not a shipped collapse feature.
- `Sources/DeskNodesApp/Application.swift`: explicit AppKit run loop with retained delegate, accessory activation policy, retained menu-bar item, quit, preview reopening, responder-chain editing menu, and lazy auxiliary windows. `LSUIElement` also suppresses the Dock icon from launch. New-note and all-topmost menu entries are visibly disabled and unfinished. No global shortcut registration in N1.
- `NotePanel.swift`: one borderless, key-capable NSPanel with a 240×130pt realistic prototype-03 paper card, 12pt corners, 14pt padding, quiet 1pt border, native window shadow, 13pt title/items, 26pt rows, 16pt completion circles and 9pt text gap, monospaced 11pt count. One fixed completed example and two editable examples. Checkmarks/count are static preview content, not working todo actions. No hover controls suggest unimplemented operations. Native shadow shape/intensity and baseline alignment need screenshot acceptance on Mac.
- `NoteTextView.swift`: actual plain NSTextView in native scroll containers, native input context/selection/undo. No keyDown interception, string replacement on notifications, or appearance-triggered storage rewrite. `hasMarkedText()` is checked at the future command boundary; Return, Backspace and composition are still handled entirely by AppKit. Long edited text can scroll within its row, but N1 does not implement item auto-height or structural editing. Data exists only in text storage for the current process and is discarded at exit.
- `Theme.swift`: appearance-aware NSColors, explicitly resolved under effective appearance for layer colors with implicit animations disabled. Paper ink light/dark exactly follows prototype 03. Native system font supplies SF/PingFang fallback. Other palette fills are ready for future note models; color selection is not implemented.
- Core Animation insertion spring: 0.30 seconds, 8pt translation, queried against the current system Reduce Motion setting on each presentation. With Reduce Motion there is no insertion animation. No timer/observer or repeated animation loop.
- `AuxiliaryWindows.swift`: on-demand AppKit windows hosting SwiftUI explanatory placeholders, retained for reopen and absent from the resident note view tree. Both say “尚未实现”; neither fabricates history data, settings, toggles, calendars or statistics.
- `Resources/Info.plist` and `scripts/build-macos.sh`: real app-bundle assembly using SwiftPM/Xcode tools, Chinese development language, stable local bundle identifier, macOS 14, accessory metadata, local ad-hoc signing and strict signature verification. No sandbox entitlement, provisioning profile, paid signing, notarization or distribution claim. Build runs for the host architecture only, not universal. The script replaces only the repo's `build/DeskNodes.app` artifact and cleans its staging directory.

N1 intentionally uses ordinary window level for the preview. Desktop-icon-relative stacking, temporary raise, all Spaces/fullscreen behavior, resize/collapse and docking belong to N4–N7. No SQLite/schema, persistence, history logic, daily rollover, undo-delete, autostart, backup, edge detection or memory optimization is included.

## Exact Mac build, tests and launch

Run on macOS 14+ with Xcode 15+ (Swift 5.9+ and a compatible macOS SDK), with Command Line Tools already selected for that Xcode. These commands do not change the selection. Use the actual cloned repo path if different:

```sh
cd /workspace/desknodes-macos-native
xcode-select -p
xcodebuild -version
xcrun swift --version
xcrun --sdk macosx --show-sdk-path
xcrun swift package dump-package
xcrun swift package describe
xcrun swift test --filter DeskNodesCoreTests
xcrun swift test --filter NativeFoundationTests
./scripts/build-macos.sh
/usr/bin/plutil -lint build/DeskNodes.app/Contents/Info.plist
/usr/bin/codesign --verify --strict --verbose=2 build/DeskNodes.app
/usr/bin/codesign -d --entitlements :- build/DeskNodes.app
/usr/bin/open build/DeskNodes.app
```

Expected output bundle: `build/DeskNodes.app`, executable `Contents/MacOS/DeskNodes`, plist `Contents/Info.plist`. The entitlements display must not contain `com.apple.security.app-sandbox=true`; an empty/no entitlement payload is expected. The script fails immediately on compilation or signing failure. A local ad-hoc signature is sufficient for this private local-build strategy; it is not a trusted distribution signature. Do not run via `swift run` for bundle/no-Dock acceptance.

Optional Xcode GUI inspection: `open Package.swift`, select the `DeskNodes` executable scheme on My Mac, then Product → Build. Xcode's package executable is useful for debugging; the bundle script above is the authoritative local `.app` entry. No checked-in `.xcodeproj` or custom Xcode scheme is required.

Portable Swift tests, on a host that already has Swift 5.9+:

```sh
swift test --filter DeskNodesCoreTests
```

On Linux the conditional manifest excludes all AppKit/SwiftUI code and native tests. Core tests do not establish native API correctness. `NativeFoundationTests` synthesizes a marked range and checks that appearance changes preserve text/selection/range, and checks panel properties without showing a window. It does not replace a real Chinese input-method test.

## Native acceptance — all pending, user-run

Record macOS/Xcode versions, host architecture, pass/fail and screenshots with each run. Do not label prototype PNGs or browser renders native screenshots.

1. Launch with `open` above. Confirm a note-text symbol appears in the menu bar and there is no DeskNodes Dock icon (also check Command–Tab). Menu must show explicit N1/no-save copy, preview, disabled unfinished actions, History, Settings and Quit. Quit must remove both panel and status item. Relaunch must reset example text.
2. Click either unfinished item text. Test caret, selection, left/right arrows, copy/paste, Command–A, Command–Z and Shift–Command–Z. Edit both rows and switch between them. Clicking elsewhere must not hide the panel. Reopening preview must retain the same panel and session text. The count remains a preview count. Return is a native newline in N1, not a new todo; empty Backspace does not delete an item.
3. Enable Apple's Simplified Chinese Pinyin input source. In the middle of a row, type `zhongwen`, move through the candidate list, commit with Return, then continue typing Chinese and emoji. Return must commit the candidate without losing existing text, splitting items or moving focus to a different row. Escape/candidate cancellation, punctuation, selection replacement and Backspace must follow native input behavior. Switch light/dark while composition is active: candidate window, marked range, selection and focus must survive. Repeat with both rows and after returning from History/Settings.
4. In System Settings → Appearance choose Light, then Dark. Capture the same card at native scale in both; compare against prototype 03 default/dark card using pt measurements, not the 2× PNG pixel size. Paper must resolve to `#F6F1E7` / `#2B2822`, title to `#1F1F1F` / `#EDEBE6`, secondary count to `#5F5A52` / `#B3ADA2`, and completed ink to `#6F6A61` / `#A39D92`. Check no opaque square around rounded corners, no frosted glass, fine border, calm shadow, 13pt text, strike-through and baseline alignment. Native screenshot fidelity remains a risk until reviewed.
5. In System Settings → Accessibility → Display enable Reduce Motion. Reopen preview from the status menu: no sliding/spring. Disable it and reopen: short, subtle 0.30s movement. Toggle while the app stays open to verify the policy is read live. Check editing focus is not stolen by reopening.
6. Open/close/reopen both History and Settings from the menu. Each must show an explicit unfinished explanation, no fake controls or data, and must not create a Dock icon or terminate the resident app. Switch focus back to the editor and repeat input checks.

Suggested capture (interactive selection of the panel):

```sh
mkdir -p build/acceptance
screencapture -i build/acceptance/n1-light.png
# Switch to Dark in System Settings, then:
screencapture -i build/acceptance/n1-dark.png
```

## Linux evidence and N2 handoff

Executed checks: `python3 scripts/check-n1.py` (33 static assertions plus shell parse), `bash -n scripts/build-macos.sh`, Python `plistlib` XML/type validation, `git diff --check`, platform/tool discovery, and the build script's Linux rejection path. The checker validates spec palette/ink/geometry, manifest declaration/layout, no external dependency declarations, core/native source separation and metadata. Text checks of the manifest are not Swift syntax/typechecking. Swift tests are provided and **unexecuted** here.

Logs are external to the repo under `/workspace/desknotes/logs/native-n1-static.log`, `native-n1-environment.log`, `native-n1-build-guard.log` and `native-n1-review.log`. No native screenshot or binary has been produced. The committed specification files are unchanged.

N2 can add domain types and a separately isolated system-SQLite persistence target without importing AppKit into the core, then inject a repository into the panel presentation layer in N3. No persistence format, migration policy, schema, storage path or stable model IDs have been prematurely chosen in N1. The sample view strings are fixtures, not seed database records. Native compilation/signing, real IME and visual acceptance remain the first Mac gates before further integration; architecture portability beyond the host is unverified.
