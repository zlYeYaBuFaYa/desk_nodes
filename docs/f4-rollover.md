# Feature 4: business dates, carry-over and recovery

`day.rs` supplies the pure business-date calculation and a `Clock` trait for
injected-clock SQLite rollover tests. `current_business_day` is authoritative
for all current-item reads and mutations. Startup synchronizes once; the running
app checks every five seconds, including after resume. Earlier wall dates never
move the stored date backward.

SQLite settings are `rollover_hour` (`0`–`6`, default `0`), `auto_carry` (`1`/`0`,
default `1`), and `current_business_day` (`YYYY-MM-DD`). These are persisted on
initial synchronization. The settings screen remains a later feature.

Running rollover broadcasts `rollover-prepare`. Each independent note pauses
input, drains queued item writes, saves its edit/add/title drafts and acknowledges
with `rollover_ready`. Only after all windows acknowledge does the backend back
up and transact the carry copies and new business date. Unavailable windows are
pruned; failed draft saves can retry on the next tick. `day-changed` fades the
content out for 150ms, reloads, then fades in for 150ms. This transition uses
opacity only, including with reduced motion enabled. A backward clock change
during preparation also releases paused editors without advancing the date.

Carry copies point to the immediate source id and accumulate actual calendar
days, leaving every source unchanged. A launch gap creates only the destination
day's copies. Active hidden notes participate; deleted notes and completed items
do not. Hard deletion of current items prevents subsequent carry; deleting a
copy leaves its earlier original intact. Undo preserves carry metadata and is
cleared on rollover.

Backups live in `<product-data-dir>/backups/<UTC timestamp>-<uuid>/`, each holding
`desknodes.sqlite3` plus any WAL/SHM sidecars. The app's database lock covers
snapshot copying. Completed snapshots are published by directory rename; partial
`.pending` directories are excluded from restore/rotation. The last seven
completed snapshots are retained. Startup runs SQLite `quick_check`; corruption
errors restore the newest complete snapshot, preserve damaged files alongside
the database, and send `backup-restored` for the gentle note toast. Non-corruption
errors (such as permissions) are reported without replacing data.

## Fake clock

```
DISPLAY=:3 DESKNODES_DATA_DIR=/tmp/desknodes-f4-shots \
DESKNODES_FAKE_NOW=2026-11-05T12:00:00 DESKNODES_THEME=light \
/workspace/desknotes/target/release/desk-nodes
```

ISO local timestamps use `YYYY-MM-DDTHH:MM:SS`; RFC3339 timestamps are also
accepted, using the supplied offset's wall date/time. The fake instant stays
fixed until restart; unset the variable for the normal local clock. Invalid
values fall back to the real local clock. No system clock/timezone is changed.
For a running rollover smoke test, keep the fake clock fixed and move only the
isolated test database's stored business date/items to the previous date.

## Validation

Required logs: `/workspace/desknotes/logs/f4-{build,test,clippy,xcheck}.log`.
Rust coverage includes midnight and 06:00 boundaries, multi-day gaps and carry
accumulation/idempotence, backward dates, disabled carry, completed/deleted-note
exclusion, deletion of copies and original current items, seven-snapshot rotation,
latest-snapshot recovery with uncheckpointed WAL contents, and V0.1 upgrade
inference/default settings initialization.

Windows GNU and macOS checks validate Rust compilation; macOS uses the existing
C stubs and does not establish native linking or runtime behavior. Linux runtime
checks and measurements do not establish macOS/Windows runtime performance.

## Measured results (2026-11-05)

- `npm run build`: pass, zero Svelte errors/warnings.
- `cargo test --manifest-path src-tauri/Cargo.toml`: 17 passed, zero failed;
  binary and doc-test targets also pass.
- `cargo clippy --manifest-path src-tauri/Cargo.toml -- -D warnings`: pass.
- `scripts/xcheck.sh`: Windows GNU and macOS x86_64 checks pass.
- `npm run tauri build -- --no-bundle`: packaged release binary built.
- X11 smoke: three independent notes acknowledged rollover; a pending add and
  pending edit were saved to the old day and copied to today. A subsequent tick
  created no additional copies. See `f4-runtime-smoke.log`.
- Deliberate corruption of only the isolated screenshot database restored the
  latest snapshot, including the draft saved during the prior rollover. All
  three notes opened and displayed `已从备份恢复数据`. Unit recovery testing also
  verifies the latest snapshot's uncheckpointed WAL value.

Actual 1920×1200 X11 captures:

- `/workspace/desknotes/shots/f4-carry-light.png`
- `/workspace/desknotes/shots/f4-carry-dark.png`
- `/workspace/desknotes/shots/f4-backup-notice.png`

Release memory, three visible independent note WebViews plus native controls,
15-second idle settle, default WebKit behavior, isolated app process tree:

| Appearance | RSS | PSS |
| --- | ---: | ---: |
| Light | 1,111.90 MB / 1,060.39 MiB | 559.86 MB / 533.92 MiB |
| Dark | 1,115.35 MB / 1,063.68 MiB | 561.56 MB / 535.54 MiB |

Raw process measurements: `/workspace/desknotes/logs/f4-memory-light.log` and
`f4-memory-dark.log`. RSS double-counts shared pages; PSS apportions them. These
are Linux idle snapshots, exclude the X server/compositor and external GPU
allocations, and are diagnostic only. No memory optimization was performed.

The fake clock is frozen, so the running-app smoke changed only the isolated
SQLite business date/items to trigger the five-second detector. Real OS suspend
and changes to the machine's clock were not performed. A fresh installation initializes its business date to the current computed
date. On V0.1 upgrade, the latest non-future item date among active notes is used
for the first gap detection; subsequent launches use the persisted business date. Backup recovery requires an existing
complete backup; no-backup corruption still reports a startup failure.

Final packaged rebuild (including the V0.1 initialization fix) also passed. A fresh
three-note light-theme measurement after that rebuild was **1,122.53 MB RSS /
1,070.53 MiB**, **562.33 MB PSS / 536.28 MiB**, with the same 15-second settle.
Raw output: `/workspace/desknotes/logs/f4-memory-final.log`. The measurement
terminated the app afterward. `cargo fmt -- --check` and `git diff --check` pass.
