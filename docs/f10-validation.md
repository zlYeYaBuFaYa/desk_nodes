# F10 / V1.0 Linux validation

Validated on Debian 13 trixie, X11 `DISPLAY=:3`, from base `9e68ae7`. Version 1.0.0 is consistent in npm, Tauri, Cargo and lockfiles. No commit, push, git configuration change, system package installation or live-root package install was performed.

## Checks

| Check | Result |
| --- | --- |
| `npm run build` (also run by final Tauri build) | Passed; svelte-check: 0 errors, 0 warnings |
| `cargo test --manifest-path src-tauri/Cargo.toml` | 35 passed, 0 failed; includes removed-monitor, negative-coordinate and shrinking-work-area clamp tests |
| `cargo clippy --manifest-path src-tauri/Cargo.toml -- -D warnings` | Passed |
| `scripts/xcheck.sh` | Passed for x86_64 Windows GNU and macOS Darwin; compilation only |
| `npm run tauri build` | Passed; final deb and AppImage produced |
| `python3 scripts/smoke-f10.py` | Passed: dark move menu; native tween sampling and SQLite write audit; live work-area shrink; last-note deletion; management empty state; new note without reseeding |
| deb smoke | Listed with `dpkg-deb -c`, extracted with `dpkg-deb -x` to `/tmp/desknodes-f10-deb-extract`; executable `/usr/bin/desk-nodes`, `/usr/share/applications/DeskNodes.desktop`, and icons verified; extracted binary launched for memory sample |
| AppImage smoke | Extracted under `/tmp/desknodes-f10-appimage-extract`; AppRun, desktop entry and native startup verified without FUSE or installation |

The native smoke uses `DESKNODES_DATA_DIR=/tmp/desknodes-f10-shots`, isolated config, and `DESKNODES_FAKE_NOW=2026-11-06T12:00:00`. It audits geometry-column updates with a temporary SQLite trigger. Each collapse and expansion produced exactly one final geometry write; the database retained height 440 throughout. Observed intermediate native heights included 106/86/72/64 during collapse and 392/426/434/438 during expansion. The final native heights were 58 and 440. Source content remains visible, clipped by the changing window, during collapse; expanded content appears as the window grows.

Changing the disposable X11 `_NET_WORKAREA` to 1000×800 while the app ran caused the second note to move from x=860 to x=620 (width 380), persisted in SQLite within the polling interval; both notes fit. The original property was restored in `finally`. This verifies live work-area detection; physical unplug, primary changes and mixed-DPI behavior still require real multi-monitor acceptance.

## Artifacts

Final copies are in `/workspace/desknotes/dist/`:

| File | Bytes |
| --- | ---: |
| `DeskNodes_1.0.0_amd64.deb` | 3,668,870 |
| `DeskNodes_1.0.0_amd64.AppImage` | 109,427,192 |

`f10-artifacts.json` records paths, exact sizes and SHA-256 hashes. `f10-deb-listing.txt` records package contents. The larger AppImage includes GTK/WebKit-related runtime libraries; the deb depends on system libraries. The signing status and real-platform checklist are in [f10-release.md](f10-release.md).

## Captures

- `/workspace/desknotes/shots/f10-collapse-tween.png` — after expansion; intermediate native geometry is verified by sampling rather than a precisely timed screenshot.
- `/workspace/desknotes/shots/f10-move-menu-dark.png` — dark destination swatch beside a matching destination note.
- `/workspace/desknotes/shots/f10-last-note-empty.png` — actual management panel after deleting both notes, with 新建便签.

## Memory

Final extracted deb binary, one seeded note visible, isolated data/config, 15 seconds idle: process-tree **RSS 533,516 KiB = 521.01 MiB**, **PSS 347,329 KiB = 339.19 MiB**. Includes the application, WebKitNetworkProcess and WebKitWebProcess. RSS counts shared pages multiple times; PSS apportions them. X server/GPU allocations outside the process tree are excluded. No memory optimization was attempted.

## Logs and remaining acceptance

Logs: `/workspace/desknotes/logs/f10-{package-final,test,clippy,xcheck,smoke,runtime,memory,appimage-extract,appimage-runtime}.log` and the memory script's timestamped runtime log. Nonfatal host warnings concern the absent accessibility bus, deprecated appindicator, and X11 desktop properties on sticky note windows.

Reduced-motion snapping is wired directly to `prefers-reduced-motion`; native reduced-motion appearance remains a manual platform check. The tween suppresses geometry persistence and notes broadcasts through its steps and an 80 ms configure-event settle period; duplicate final configure events are ignored. Real compositor scheduling can vary. Native Mac/Windows installer execution, autostart login cycles, real signing/notarization, SmartScreen, physical unplug and mixed-DPI behavior were not claimed as tested on this Linux box. See the unchecked acceptance items in [f10-release.md](f10-release.md).
