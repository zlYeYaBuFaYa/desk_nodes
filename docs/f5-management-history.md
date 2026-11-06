# F5 — Management and history

The `management` webview is created on demand, with native decorations and taskbar visibility; normal close destroys it. Tray and native controls expose management, history and settings. A second process exits through `tauri-plugin-single-instance` and opens/focuses management on the notes tab. On macOS opening management promotes the app to regular activation so the Dock can expose it.

The notes tab uses existing creation and visibility paths, plus a panel command for visibility/pin updates. Notes, item and business-day broadcasts refresh the panel. Settings is an intentional F6 placeholder.

History reads all dated items, including soft-deleted notes, groups them by note, and calculates daily buckets from exact counts (empty, zero, below half, at least half, complete). Rust gates edits to the previous persisted business day. Completing that day's item and deleting its direct carried copies on the current business day share one SQLite transaction. Undoing completion does not recreate a removed copy. Earlier dates and today's date are read-only in history. The note editor remains the place to edit today's items.

The carry pill uses token secondary text at 12px, 2px/7px padding, a rounded shape, and a 5% accent blend over the note background. Calculated worst-case WCAG contrast over all eight colors: light **4.99:1**, dark **4.70:1**.

## Verification

- `npm run build`: passes, zero Svelte errors/warnings.
- `cargo test --manifest-path src-tauri/Cargo.toml`: **21 passed**, no failures.
- `cargo clippy --manifest-path src-tauri/Cargo.toml -- -D warnings`: passes.
- `scripts/xcheck.sh`: Windows GNU and macOS cfg/type checks pass (macOS C stubs; not native runtime tests).
- `cargo fmt --manifest-path src-tauri/Cargo.toml --check`, `git diff --check`: pass.
- `scripts/smoke-f5.py`: native X11 fixture and UI checks; creates a fresh `/tmp/desknodes-f5-shots` and refuses to overwrite it. Uses `DESKNODES_FAKE_NOW=2026-10-29T12:00:00`. Second launch, panel destruction/recreation, visibility/pin updates, history edit gate, carried-copy removal, and month navigation are exercised.

Logs: `/workspace/desknotes/logs/f5-{build,test,clippy,xcheck,smoke,memory}.log`.
Screenshots: `/workspace/desknotes/shots/f5-panel-notes.png`, `f5-history-light.png`, `f5-history-dark.png`, `f5-carry-badge.png`.

## Memory observation

No memory optimization was performed. Linux debug binary with embedded production frontend, one visible note, panel closed, five seconds settled: aggregate process-tree **RSS 556.81 MB / 531.02 MiB**, **PSS 369.74 MB / 352.61 MiB**. RSS double-counts shared pages; PSS apportions them. External X server/GPU allocations are excluded. This is diagnostic, not a release performance claim.

## Carry-forward review

Independent note webviews, frameless rounded note surfaces, token colors, dark/system themes, pin/visibility, resizing and geometry persistence remain in place. Management alone gets a normal taskbar window. Data-dir and fake-clock overrides remain supported. No commits, pushes, git configuration changes, machine network changes, or memory optimization work.
