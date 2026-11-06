# V0.2 F6 — Settings and global shortcuts

Settings use individual SQLite keys. `settings-changed` broadcasts effective preferences to every webview; notes apply appearance, opacity and font size immediately. Rollover reads the same `rollover_hour` and `auto_carry` keys on its existing five-second poll. The persisted business date never moves backwards.

Global shortcuts default to Control+Shift+Space/N/D (Super+Shift+Space/N/D on macOS). Enter a shortcut string and press Enter or leave the field to save; new modifier combinations can also be captured directly. Text entry is necessary for combinations already grabbed by the desktop. Failed registrations preserve the prior binding and mark the field red. Startup failures are reported in the corresponding field, without preventing app startup.

Temporary hide-all remembers the set of visible notes. Repeated hides preserve that set; restore does not reveal notes previously hidden individually. The first hide opens the management panel with a gentle restoration notice and persists `hide_all_hint_shown`.

Backups are pretty JSON with version 1 and complete notes/items/settings tables (including deleted notes and history). Import validates version, table shapes, field types, settings, shortcut duplicates, note/item values and foreign keys in an isolated SQLite database before asking for replacement confirmation. Replacement is transactional; the app restarts to reload windows and OS integrations. Canceling either the picker or confirmation preserves current data.

Autostart uses the Tauri plugin, with a Linux adapter for its hardcoded `~/.config` assumption: an absolute `XDG_CONFIG_HOME` is honored, otherwise `~/.config/autostart/DeskNodes.desktop` is used. Executable paths are quoted; AppImage paths are supported. The desktop session must support XDG autostart. A custom `DESKNODES_DATA_DIR` skips startup-time OS autostart mutation; explicit toggle changes still apply and report errors. Test runs use an isolated XDG config directory.

Linux shortcut registration is tested on X11 (`DISPLAY=:3`). Desktop-reserved combinations can fail; Wayland support depends on the desktop/backend and is not established by this X11 run. macOS/Windows are cross-checked for compilation, not runtime-tested here.

Validation logs live in `/workspace/desknotes/logs/f6-*.log`; requested screenshots live in `/workspace/desknotes/shots/f6-*.png`. Memory measurements include the app and its WebKit descendants, exclude the display server/GPU process outside that session, and use RSS and proportional PSS. No memory optimization is part of this change.

## Measured validation

- npm run build: pass, zero Svelte diagnostics.
- cargo test --manifest-path src-tauri/Cargo.toml: 26 passed (plus empty binary/doc-test suites).
- cargo clippy --manifest-path src-tauri/Cargo.toml -- -D warnings: pass.
- scripts/xcheck.sh: Windows GNU and macOS Darwin checks pass.
- Native X11 smoke covers all three global shortcuts, duplicate edit rejection with the original binding retained, live settings, isolated XDG desktop entry, subset restore and the persistent first-hide hint.
- Native file dialogs: JSON export, import confirmation, cancellation preserving data, replacement from three notes to the backed-up two, settings restoration and process/window restart pass.
- Memory, debug binary with embedded production frontend, 15-second settle: one note RSS 530.86 MiB / PSS 352.26 MiB; five notes RSS 1614.38 MiB / PSS 722.49 MiB. These are measurements, not a release-performance claim; the five-note figure exceeds the original 200 MB aspiration. No optimization was attempted.

The native hotkey exercise also exposed a menu rebuild holding the database mutex across native menu calls. Snapshotting the notes before rebuilding avoids a UI/database deadlock. Tray and hotkey actions run on a serialized blocking worker so native dispatch remains responsive and rapid toggle requests do not overlap.

Visibility, geometry, and title/pin changes update only their respective database columns, so asynchronous native actions cannot overwrite one another with a stale note snapshot. Held hotkeys trigger once per press/release cycle.
