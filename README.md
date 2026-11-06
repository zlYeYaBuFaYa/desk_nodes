[English](README.md) · [简体中文](README.zh-CN.md)

# DeskNodes

Quiet desktop sticky notes for everyday tasks. DeskNodes V1.0 combines independent, softly colored note windows with local task storage, tomorrow planning, and a calendar of your progress. This README describes source revision `a9b34c3`; the npm, Cargo and Tauri packaging version is **1.0.0**.

![Light notes with expanded and collapsed windows](docs/screenshots/f7-collapse-light.png)

## V1.0 features

- Independent windows with eight Morandi colors, editable titles, pinning, hiding, dragging and resizing. Positions, sizes, visibility and collapsed state persist; collapse/expand respects reduced motion.
- Today and tomorrow items: add, edit, complete, delete, reorder today's unfinished items by dragging, and move items to another note through the context menu. Delete and move offer a five-second undo. HTTP/HTTPS links open in the system browser.
- Daily rollover at a configurable local hour (00:00–06:00), with optional automatic carry-forward of unfinished tasks and accumulated carry-day badges. Tomorrow's planned items become today's items. The stored business date never moves backward when the clock does.
- A management panel for note visibility and pinning, plus a history calendar with daily details, weekly/monthly completion rates and a consecutive-day streak. The previous business day's completion can be corrected; older days are read-only. Completing a previous-day item removes its unfinished carried copy from today.
- System/light/dark appearance, 70–100% note opacity, three font sizes, configurable global shortcuts, login autostart, JSON backup export/import, and an action to open the data folder.
- Tray actions, fallback native controls, and single-instance handling: launching again opens the management panel. Display changes trigger work-area clamping, helping recover notes from a removed monitor.

Data stays in a local SQLite database; there is no cloud synchronization or account flow. The current application interface is Chinese.

## Screenshots

Existing Linux X11 captures use demonstration data, including a simulated date; they are illustrations rather than a fresh capture of this documentation change.

| History and statistics | Settings |
| --- | --- |
| ![History calendar and completion statistics](docs/screenshots/f9-stats-light.png) | ![Appearance, shortcuts and backup settings](docs/screenshots/f6-settings-light.png) |

![Dark notes and the move-to-note menu](docs/screenshots/f10-move-menu-dark.png)

The Settings screen still displays an old **V0.2** label in the current source and capture. Package metadata is **1.0.0**.

## Platform status

| Platform | Verified status |
| --- | --- |
| Debian 13 Linux, x86_64, X11 | Tested; existing validation covers native interaction, deb packaging and extracted AppImage startup. Clean-host installation acceptance remains pending. |
| macOS | Rust cross-target compilation checked only, using Darwin C stubs; no native runtime, DMG acceptance, signing or notarization completed. |
| Windows | Windows GNU Rust cross-target compilation checked only; no native runtime, MSI/NSIS acceptance or signing completed. |

See the [Linux validation record](docs/f10-validation.md) and [release acceptance checklist](docs/f10-release.md). These are historical records, not checks rerun by editing this README. Wayland and physical multi-monitor/mixed-DPI acceptance remain unverified.

## Develop and build

Use Node.js 24+ with npm, a recent Rust stable toolchain supporting edition 2024, and the platform's Tauri 2 prerequisites. On Debian 13:

```sh
sudo apt update
sudo apt install build-essential pkg-config libwebkit2gtk-4.1-dev libgtk-3-dev \
  librsvg2-dev patchelf libayatana-appindicator3-dev
npm ci
export CARGO_TARGET_DIR=/workspace/desknotes/target
npm run tauri dev
```

Run from the repository root in a graphical desktop session. For an X11 session, `GDK_BACKEND=x11 npm run tauri dev` selects GTK's X11 backend; set `DISPLAY` to your actual display when needed. `npm run dev` starts only Vite on port 1420; native features require the Tauri application.

On macOS install Xcode Command Line Tools. On Windows install the MSVC C++ build tools and WebView2, using the native Rust MSVC toolchain for packaging. Consult the authoritative [Tauri prerequisites](https://v2.tauri.app/start/prerequisites/) for platform setup.

```sh
npm run build                              # Svelte/TypeScript checks + Vite assets
npm run tauri build -- --no-bundle          # production executable only
npm run tauri build -- --bundles deb,appimage # Linux packages
# On the native platform, select its configured bundle targets:
npm run tauri build                        # platform-supported packages
```

The checked-in [.cargo/config.toml](.cargo/config.toml) sets two build jobs and `/workspace/desknotes/target` as the target directory. On another machine, override `CARGO_TARGET_DIR` with an absolute writable directory. Production executables go under `$CARGO_TARGET_DIR/release/` and packages under `$CARGO_TARGET_DIR/release/bundle/`.

Linux supports **deb and AppImage**; the configuration also lists DMG, MSI and NSIS for native platform builds. Install a locally built deb with `sudo apt install /absolute/path/to/package.deb`, or make the built AppImage executable and launch it. AppImage may need FUSE; `--appimage-extract` offers an extraction alternative. No published release or download service is asserted here. Public macOS/Windows distribution still requires native acceptance and signing setup; macOS notarization has not been performed. The configured macOS minimum is 10.15, subject to native toolchain/WebView verification.

## Everyday use and shortcuts

The first database starts with one note and three introductory items. Double-click a title to rename it; use the color button for the palette, the pin for always-on-top, minus to hide, and the more menu to collapse or delete. Note deletion is confirmed and soft-deletes the note while preserving its items/history. Deleting the final note is allowed; create another from the management panel or tray, without reseeding examples.

Press Enter to add an item or save an edit; Escape dismisses editing and menus. Delete/Backspace removes a selected today item when focus is outside a text field. Expand “已完成” for completed items or “明天” for tomorrow planning. Right-click an item for “移动到…” (move to another note).

| Global action | Linux / Windows default | macOS default |
| --- | --- | --- |
| Toggle note visibility | Ctrl+Shift+Space | Super (Command)+Shift+Space |
| New note | Ctrl+Shift+N | Super (Command)+Shift+N |
| Open management panel | Ctrl+Shift+D | Super (Command)+Shift+D |

Change bindings in Settings by entering a shortcut and pressing Enter or leaving the field. A failed registration reports an error and preserves the previous binding. Desktop-reserved shortcuts may be unavailable.

Temporary hide-all remembers which notes were visible, so restore preserves individually hidden notes. Recover through tray “显示全部”, the management visibility switches, or the global toggle. Native controls provide a fallback when the tray host is unavailable. Closing a note hides it; use Quit in the tray/control menu to exit. Autostart defaults to enabled; Settings reports integration errors. On Linux it uses `$XDG_CONFIG_HOME/autostart/DeskNodes.desktop`, falling back to `~/.config/autostart/DeskNodes.desktop` when the config variable is absent or not absolute.

History rates divide completed item counts by total item counts, including preserved history from deleted notes and excluding future dates. Weeks run Monday–Sunday. A streak counts consecutive nonempty, fully completed days, anchored on today if complete or yesterday otherwise; a blank or incomplete day breaks it. Week and streak refer to the current business date; month rate follows the displayed month.

## Storage, backups and recovery

| OS | Product data directory |
| --- | --- |
| Linux | `$XDG_DATA_HOME/DeskNodes` when set; otherwise `~/.local/share/DeskNodes` |
| macOS | `~/Library/Application Support/DeskNodes` |
| Windows | `%APPDATA%\DeskNodes` when set; otherwise `%USERPROFILE%\AppData\Roaming\DeskNodes` |

`desknodes.sqlite3` stores notes, dated items and settings in SQLite WAL mode; `-wal` and `-shm` companions may exist. `DESKNODES_DATA_DIR=/absolute/path` overrides the entire product directory, without adding `DeskNodes`. With this override, startup skips system autostart changes; explicitly toggling autostart in Settings still changes the OS integration. Normal startup can migrate the old identifier-based Tauri data directory once, retaining the old files and never replacing an existing destination database.

Automatic snapshots are created **before a due business-day rollover**, including catch-up on launch, under `backups/` inside the data directory. The latest seven complete snapshot directories are retained, with SQLite sidecars when present. This is rollover protection, not continuous version history.

On SQLite corruption/not-a-database errors, startup attempts the latest snapshot, preserves damaged files with `.damaged-<UUID>` suffixes, and reports successful recovery in a note. Other errors propagate; missing or unusable backups can prevent startup. It does not search older snapshots after the latest fails.

Settings exports version-1 JSON containing all notes, items, history and settings, including deleted notes. Import validates in an isolated database, asks before replacing all data, applies the replacement transactionally, and restarts the app. Export current data first; canceling preserves it. For manual filesystem recovery, quit the app and preserve the whole data directory, including sidecars, before replacing files. Keep independent JSON exports outside that directory.

## Stack, layout and checks

Tauri 2 and Rust manage native windows, tray, shortcuts and OS integration. Svelte 5, TypeScript 6 and Vite 8 render the interface; `svelte-dnd-action` handles reordering. SQLite is bundled through `rusqlite`.

| Path | Purpose |
| --- | --- |
| [src/App.svelte](src/App.svelte) | Note windows and item interactions |
| [src/Management.svelte](src/Management.svelte), [src/Settings.svelte](src/Settings.svelte) | Management, history and preferences |
| [src/styles](src/styles) | Application styles and generated design tokens |
| [src-tauri/src](src-tauri/src) | Native commands, database, rollover, history, settings and storage |
| [src-tauri/tauri.conf.json](src-tauri/tauri.conf.json) | Version, bundle targets, icons and app configuration |
| [scripts](scripts) | Token generation, cross-checks and feature smoke scripts |
| [docs](docs) | Design material and historical feature/validation reports |

```sh
npm run check
npm run build
cargo test --manifest-path src-tauri/Cargo.toml
cargo clippy --manifest-path src-tauri/Cargo.toml -- -D warnings
scripts/xcheck.sh
npm run tokens                            # regenerate token CSS from design JSON
```

`xcheck.sh` needs the Windows GNU/macOS Rust targets, MinGW tools (including windres), and check-only Darwin stubs at `/workspace/aienv/darwin-stub` or `DARWIN_STUB_DIR`. It does not link or produce a runnable macOS app. Native `scripts/smoke-f*.py` checks are environment-specific X11 fixtures: inspect them before running; they use fixed paths/display values, fixture databases, and desktop automation tools such as xdotool, wmctrl and ImageMagick. They are not a portable unit-test command.

## Known limitations

- Wayland global shortcuts, tray behavior and native window placement are not accepted; Debian 13 X11 is the tested desktop environment.
- Physical monitor unplug, primary-display changes and mixed-DPI layouts still need hardware acceptance. The code polls display topology/work areas every three seconds and clamps restored windows, but this does not establish all hardware behavior.
- macOS and Windows have compilation checks only. Native installation, autostart, shortcuts, signing, notarization and clean-host behavior remain release work. No Linux package signing is configured.
- The UI is Chinese and the Settings version label is stale. Data has no built-in cloud sync; automatic backup retention is limited to seven rollover snapshots.
