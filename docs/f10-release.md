# DeskNodes 1.0 release acceptance

## Implementation

Live display recovery uses a three-second topology poll: Tauri 2 has no portable monitor-change event, and window scale changes alone miss Linux work-area changes. The fingerprint includes primary monitor, monitor positions, scale factors and work areas; stable configurations do no geometry writes. A change reuses `place` for each visible note, falls back to the primary monitor, clamps into its work area, and stores the final native geometry once. Hidden notes still clamp on restore. Display recovery and transitions are serialized. Existing unit coverage includes a removed monitor and negative coordinates. Physical multi-monitor unplug and mixed-DPI acceptance remain required on real hardware.

Collapse/expand uses twelve native height steps over approximately 192 ms with cubic ease-out, on a blocking worker so the UI thread stays responsive. Reduced motion snaps in one step. A per-window guard suppresses resize/move persistence and `notes-changed` throughout the transition and native event settling; one final save and broadcast follows. Duplicate configure events are ignored. Collapsed notes retain their expanded database height. Content stays visible during collapse and appears immediately on expansion, clipped by the changing native window. Collapsed popovers temporarily enlarge the native surface as before.

Move-menu dots use destination `--light-bg` / `--dark-bg` design tokens, including explicit and system dark modes. Deleting the last note is allowed: the management empty state and tray continue to offer 新建便签.

## Platform packaging and signing

All platforms share identifier `com.desknodes.app`, version 1.0.0 and the PNG/ICNS/ICO icon set in `src-tauri/icons`. Run `npm ci`, then `npm run tauri build` on the platform being packaged. Tauri selects supported targets from deb, appimage, dmg, msi and nsis. Cross-target `cargo check` on Linux is only a compilation check, not an installer or runtime test.

- Linux: `.deb` and AppImage. Smoke with `dpkg-deb -c` and `dpkg-deb -x package.deb /tmp/desknodes-f10-deb-extract`; never install into the build machine's root. Verify `/usr/bin/desk-nodes`, the desktop entry and icon. AppImage needs FUSE on some hosts; `--appimage-extract` is an alternative. No Linux signing is configured.
- macOS: build DMG on a Mac with Xcode tools. For distribution, supply an Apple Developer ID Application identity via `APPLE_SIGNING_IDENTITY`; notarization uses `APPLE_ID`, `APPLE_PASSWORD` (app-specific) and `APPLE_TEAM_ID`, or the Apple API-key credentials supported by the Tauri bundler. Keep credentials outside source control. Verify with `codesign --verify --deep --strict`, `spctl --assess --type execute`, and `xcrun stapler validate`; test the downloaded DMG on a clean Mac. No real signing or notarization was performed here. Minimum configured macOS version is 10.15; verify against current WebView/toolchain requirements on the release Mac.
- Windows: build MSI (WiX) and NSIS EXE on Windows with the MSVC toolchain and required bundler tools; verify WebView2 bootstrap/install behavior offline and online. Configure the Tauri Windows signing certificate/thumbprint or CI signing command and timestamp service before public distribution. Check Authenticode with `Get-AuthenticodeSignature`. Unsigned builds may trigger SmartScreen; even a signed new publisher may need reputation. No real Windows signing was performed here.

## Acceptance checklist

- [ ] Linux clean-host install/uninstall; desktop launcher, correct icon and version; preserve user data.
- [ ] macOS DMG install, launch, Gatekeeper/notarization validation and uninstall on a real Mac.
- [ ] Windows MSI and NSIS install/uninstall, WebView2, Authenticode and SmartScreen on a real PC.
- [ ] Enable/disable autostart; log out/in; confirm one instance and preference persistence (isolated data mode intentionally skips system autostart).
- [ ] Hide all, recover from tray and global shortcut; recover management panel with second launch; tray-unavailable fallback controls.
- [ ] Delete the final note, see 新建便签 in management and tray, create another without reseeding.
- [ ] Unplug secondary monitor while running; notes return to primary work area within three seconds; change primary, resolution, scale and dock/panel work area; restart and verify stored positions.
- [ ] Collapse/expand repeatedly; preserved expanded height, one final geometry save, no intermediate refresh; reduced-motion snap.
- [ ] Dark move menu dots match destination backgrounds; move/undo preserves date and completion.
- [ ] First-run examples, empty focus, internal scrolling, rollover with editing, backward clock, backup recovery, shortcut conflicts (covered by prior feature tests/smokes; repeat on release hosts).

Linux automated results, screenshots, artifacts and measured memory are recorded in `f10-validation.md`. Unchecked real-platform checks are release follow-ups, not claims of completion.
