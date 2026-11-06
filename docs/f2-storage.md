# F2 local notes

SQLite is stored at Tauri `app_data_dir()/desknodes.sqlite3`. On this Linux host
that resolves to `/home/box/.local/share/com.desknodes.app/desknodes.sqlite3` (subject to
XDG_DATA_HOME). macOS uses `~/Library/Application Support/com.desknodes.app`;
Windows uses the Tauri application data directory under APPDATA. The chosen path
is printed at launch. `DESKNODES_DATA_DIR` overrides only the application database
directory, useful for isolated testing. Webviews remain independent as in F1.

Migration 001 copies the specification's three tables and index. `user_version`
tracks migration progress; SQLite uses WAL, foreign keys, a five-second busy
timeout and NORMAL synchronous mode. First-launch seeding is transactional and
only happens when the notes table has no records, including deleted records.
Business days use the machine's local date, timestamps use UTC.

All application reads and writes run through Rust. Note metadata commands identify
the caller's window; mutations broadcast `notes-changed`. Window movement and
resizing save logical geometry, including their final event. Restoring clamps the
window to a current monitor's work area and enforces size limits. Show all sets
visible=1 on all active notes, including notes hidden in earlier sessions. Hide
keeps the independent window alive; deletion retains items for future history.

The native controls menu remains the fallback when Linux has no tray host. A
`create_note` command is the global shortcut integration hook; registering an OS
global shortcut is deferred. Item editing, completion, deletion and sorting are
also deferred: today's stored items are displayed, and the item input receives
focus after naming a newly created note. The input is explicitly labelled as a
future feature to assistive technology.

Linux screenshots and runtime checks use DISPLAY=:3. Windows and macOS checks are
compile checks only; macOS uses the existing Darwin compiler stubs. No memory
optimizations are included. `scripts/measure-mem.sh` accepts
`DESKNODES_EXPECTED_NOTES` (default 1), `DESKNODES_DATA_DIR`, and `DESKNODES_BINARY`.
For comparable five-note measurement, prepare five visible notes in an isolated
store and use DESKNODES_EXPECTED_NOTES=5. RSS includes shared pages more than once;
PSS apportions them. Measurements exclude the external X server/compositor.


Verification: `npm run build` (zero errors/warnings), `cargo test` (5 passed),
`cargo clippy -- -D warnings`, `scripts/xcheck.sh` (Windows GNU and macOS x86_64),
and release `tauri build --no-bundle` passed. `python3 scripts/smoke-f2.py`
passed on X11: first launch and three seed items, title edit/cancel, palette,
pin, title drag, actual native edge resize, min/max hints, geometry persistence,
hide/show, native create with initial keyboard focus, delete confirmation/cancel,
soft deletion, hide/show all and exact restoration across restart. The smoke test
uses a fresh temporary database each run; close other DeskNodes instances first.
The snapshot/memory fixture uses five notes and sample items in
`/tmp/desknodes-f2-shots`, separate from real user data. It is test data prepared
outside the application, not additional first-launch seed content.

Required command logs: `/workspace/desknotes/logs/f2-{build,test,clippy,xcheck}.log`.
Runtime evidence: `f2-smoke.log`, `f2-smoke-app.log`, `f2-release-build.log`,
and `f2-memory.txt` in that log directory. Screenshots are
`/workspace/desknotes/shots/f2-notes-light.png`, `f2-notes-dark.png`,
`f2-palette.png`, and `f2-more-menu.png`.

Linux emits environmental AT-SPI and deprecated libayatana-appindicator warnings;
these did not prevent interaction. The native controls fallback remains available.
F1 review: independent webviews, native tray/controls, no taskbar entries, pin,
transparent rounded cards, design tokens, all-workspace visibility, and platform
compilation remain intact. The five hardcoded prototype notes were replaced by
persisted notes and the single first-launch seed required by F2.

Final release measurement (five independent WebKit web processes, 15-second
settle): RSS 1,678.89 MB / 1,601.12 MiB; PSS 734.90 MB / 700.85 MiB.
These are diagnostic figures with no memory acceptance gate. No sharing,
process tuning or destroy-on-hide changes were made.
