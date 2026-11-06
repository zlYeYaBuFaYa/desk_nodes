# F3 item management

Each note keeps an independent window. Today's item writes use the calling note
window's identity, a SQLite transaction, and the local calendar date. Item changes
broadcast `items-changed`; note changes rebuild both native menus and broadcast
`notes-changed`. Empty edits preserve the previous text. Content is trimmed and
limited to 200 Unicode scalar values in Rust, with an HTML input limit as well.
Uncompleting appends to the unfinished list. Reorder requests must contain exactly
the current unfinished item IDs. Deletion removes today's row; the last deletion
can be restored from that window's five-second undo toast. Deleted items therefore
do not enter history. Completed items are collapsed by default.

The database now lives in `DeskNodes/desknodes.sqlite3` under the platform data
base: `$XDG_DATA_HOME` or `~/.local/share` on Linux, `~/Library/Application Support`
on macOS, and `%APPDATA%` on Windows. `DESKNODES_DATA_DIR` still takes precedence.
When using the default directory and its DB is absent, the previous Tauri
`app_data_dir()` DB is copied with its WAL/SHM files. Copies are staged, synced, and
renamed; the DB is published last. Existing destination databases are never
overwritten, and the old directory remains as a backup. An interrupted copy can
be retried. Migration should run with other DeskNodes instances closed.

The palette and more menu use solid token backgrounds above the scrolling area;
the two-row palette fits the smallest supported window. The undo toast is also
solid and elevated. Check and strike transitions last 250ms; completion moves out
of the open list after 300ms; new rows enter over 150ms. Reduced motion uses fades
and disables drag flip movement. Scrollbars become visible during scrolling.

History, settings, global shortcut registration, tomorrow items, and day rollover
remain outside this feature. macOS and Windows verification is compilation only;
the existing Darwin C stubs do not produce runnable macOS binaries.

Verification on Debian/X11: `npm run build` has zero Svelte errors or warnings;
`cargo test` passes 9 tests; strict Clippy and both targets in `scripts/xcheck.sh`
pass. `scripts/smoke-f3.py` exercises entry focus, Enter/blur editing, the content
limit, completion/uncompletion order, pointer reorder and sort values, both
removal paths, undo, empty-note focus, and native note visibility toggles.
`scripts/smoke-f2.py` remains usable with the expanded menu and passes the existing
window regression cases. `scripts/smoke-migration.py` verifies the Linux default
path and recovery of committed WAL data using an isolated XDG directory.
Command logs and memory measurements are under `/workspace/desknotes/logs/f3-*`;
the five requested screenshots are under `/workspace/desknotes/shots/f3-*`.

Final five-window release measurement after 15 seconds: RSS **1,660.08 MB /
1,583.17 MiB**, PSS **755.80 MB / 720.78 MiB**. All five WebKit web processes remain
independent. Figures are diagnostic, include shared-page double counting in RSS,
and exclude the external X server/compositor. No memory optimization was made.
