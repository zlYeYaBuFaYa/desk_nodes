# Feature 1: five-window prototype measurement

The product owner removed the **<200 MB acceptance target**. Memory numbers
are **diagnostic only for V0.1 F1**; there is no memory acceptance gate.
Elegance and beauty remain the first priority, with independent note windows
and the original WebKit rendering behavior. Optimization attempts were abandoned
by product decision; the original F1 implementation is restored from `071df26`.

Baseline measured **2026-11-05 at 21:54:48 PST (UTC−08:00)**.

## Environment and method

- Debian GNU/Linux 13 (trixie), x86_64; Intel Xeon, 8 virtual CPUs;
  15.6 GiB RAM, no swap.
- X11 `DISPLAY=:3`, Xvfb **1920×1200×24**, Xfwm4 and xfce4-panel.
- WebKitGTK **2.54.0**, GTK **3.24.49**; Mesa software-rendering libraries
  (`libLLVM.so.19.1`, `libgallium`) appear in process mappings.
- Rust 1.99.1, Tauri 2.12.5, Tauri runtime Wry 2.12.3, Wry 0.57.1;
  Svelte 5.57.3, Vite 8.3.6, TypeScript 6.0.3; Node 24.22.1.
- Production frontend and **release** Rust binary, optimized for size, thin LTO,
  stripped. Binary: `/workspace/desknotes/target/release/desk-nodes` (~5.5 MiB).
- Five independent, visible 280×360 WebView windows with distinct colors,
  plus a native control window **without a sixth WebView**. Each note has a
  12 px rounded card, transparent margin and CSS shadows.
- No `tauri dev`, Vite server, browser automation or debug tools in the sample.
  Build and cross-check commands had completed before this final sample.
- Default WebKit rendering, light appearance forced using `DESKNODES_THEME=light`.
  No renderer overrides or WebKit sandbox disabling in the official sample.
- `scripts/measure-mem.sh` starts a new process session, waits for WebKit and the
  five-window startup log, settles 15 seconds, verifies five X11 note windows
  using `wmctrl` when available, and reads `/proc`. The process set includes the
  app, all session members and recursively discovered descendants. Other apps'
  WebKit processes are excluded.
- RSS is `VmRSS` from `/proc/PID/status`; PSS is `Pss` from
  `/proc/PID/smaps_rollup`. Every process's PSS was readable.

Reproduce after building the latest source:

```sh
npm install
npm run tauri build -- --no-bundle
KEEP_APP=1 DESKNODES_THEME=light scripts/measure-mem.sh \
  | tee /workspace/desknotes/logs/memory-release.txt
```

`KEEP_APP=1` is only for subsequent inspection; omit it for automatic cleanup.
The restored baseline script retains a historical <200 MB PASS/FAIL output line.
That line is obsolete and is not a product acceptance result; exit 0 means the
measurement itself succeeded.

## Informational baseline release result

| Process | PID | RSS (KiB) | PSS (KiB) |
| --- | ---: | ---: | ---: |
| desk-nodes | 2723438 | 174,832 | 63,600 |
| WebKitNetworkProcess | 2723450 | 63,508 | 21,110 |
| WebKitWebProcess (note 1) | 2723491 | 263,420 | 113,490 |
| WebKitWebProcess (note 2) | 2723492 | 264,564 | 113,454 |
| WebKitWebProcess (note 3) | 2723493 | 262,500 | 112,598 |
| WebKitWebProcess (note 4) | 2723498 | 264,068 | 112,795 |
| WebKitWebProcess (note 5) | 2723503 | 264,804 | 113,619 |
| **Sum** | | **1,557,696** | **650,666** |

- **RSS: 1,595.08 MB / 1,521.19 MiB (diagnostic only).**
- **PSS: 666.28 MB / 635.42 MiB (diagnostic only).**
- MB means 1,000,000 bytes; MiB means 1,048,576 bytes.
- The five renderer rows are creation-order attribution; WebKit does not attach
  a note label to each process command line.

Raw output: `/workspace/desknotes/logs/memory-release.txt`.
App log: `/workspace/desknotes/logs/memory-app-20261105-215433.log`.

An earlier light release sample was 1,614.61 MB RSS / 683.61 MB PSS. A dark
sample was 1,585.10 MB RSS / 664.40 MB PSS. These are diagnostic variations. No debug measurement is substituted for
the release result.

## Measurement limits

RSS counts shared library pages once per process, so its sum substantially
double-counts shared memory. PSS apportions shared pages. Neither sum includes the
pre-existing X server, compositor/panel, kernel
allocations, or GPU/driver allocations outside the measured process set. This
is one idle snapshot after initial display, not peak memory or a long-term leak
test. WebKit/GTK shared-library residency, per-window renderer heaps and the
Xvfb/Mesa rendering environment materially affect results. These Linux numbers
must not be presented as measured macOS or Windows performance. There is no
memory acceptance threshold for this feature.

## Runtime verification and Linux caveats

- Frameless cards, rounded corners, transparent outer margins and soft shadows
  render on this display; the desktop is visible around the cards. This does
  not establish transparent rendering on every Linux compositor.
- Xfwm4 reports `_NET_WM_STATE_SKIP_TASKBAR`, `_NET_WM_STATE_SKIP_PAGER`, and
  `_NET_WM_STATE_STICKY` for notes. Only the recovery control window appears in
  the panel's task list. Pinning toggles `_NET_WM_STATE_ABOVE`.
- Custom titlebar dragging, minimum-size enforcement, hide, Show all and Hide
  all were exercised with X11 input. New note and Quit were also checked.
- Ayatana tray registration succeeds, but no DeskNodes tray icon was visible in
  this xfce4-panel configuration. The persistent native **DeskNodes controls →
  DeskNodes** menu is the verified recovery path and exposes all four actions.
  This distinguishes registration success from an actually usable tray host.
- Runtime logs contain a missing AT-SPI accessibility-bus warning and an Ayatana
  deprecation warning. They do not prevent launch or native fallback actions.
- Notes are intentionally in memory. Restart seeds the same five examples;
  custom colors, pins, new notes and geometry are not persisted in F1.

Screenshots (actual root-window captures, five notes each):

- `/workspace/desknotes/shots/f1-notes-light.png`
- `/workspace/desknotes/shots/f1-notes-dark.png`

## Quality checks

The baseline checks below completed successfully before optimization attempts.
The removed smoke helper is not required by the restored implementation; its
interaction results and screenshots above are historical baseline evidence.

| Command | Result | Log under `/workspace/desknotes/logs/` |
| --- | --- | --- |
| `npm run build` | 0 errors, 0 warnings; production assets emitted | `frontend-build.log` and `tauri-release.log` |
| `cargo test --manifest-path src-tauri/Cargo.toml` | 1 passed, 0 failed; binary/doc targets also pass | `cargo-test.log` |
| `cargo clippy --manifest-path src-tauri/Cargo.toml -- -D warnings` | Finished, no warnings | `clippy.log` |
| `npm run tauri build -- --no-bundle` | Finished release; native binary built | `tauri-release.log` |
| `scripts/xcheck.sh` | Windows GNU and macOS x86_64 both Finished | `xcheck.log` |
| X11 interaction checks | Five notes, pin/unpin, drag, size, hide/recovery, new/quit | `smoke-x11.log`, `runtime-final.log` (historical baseline logs) |
| `scripts/measure-mem.sh` | Exit 0, five windows counted; diagnostic only | `memory-release.txt` |

All Cargo invocations use two jobs and `/workspace/desknotes/target` (also set
in `.cargo/config.toml`). Darwin checking uses the supplied `fakecc`/`fakear`;
it validates Rust cfg/types only, not real C compilation, native linking,
installation, signing or runtime behavior. Windows GNU is also a compile check,
not a Windows runtime test. Platform packaging was not tested in F1; the release
application binary was built with `--no-bundle`.

## Restored F1 verification — 2026-11-05

After restoring the four implementation/measurement files exactly to `071df26`,
`npm run build`, `cargo test` (1 passed), `cargo clippy -- -D warnings`,
`scripts/xcheck.sh` (Windows GNU and macOS x86_64), and the release build with
`--no-bundle` all passed. Cargo used two jobs and
`CARGO_TARGET_DIR=/workspace/desknotes/target`. The release build retained the
existing warning about the `.app` suffix in the macOS bundle identifier.

A fresh release launch on `DISPLAY=:3`, light theme, after 15 seconds confirmed
**five X11 note windows and five independent WebKitWebProcess processes**:
**RSS 1,576.50 MB / 1,503.46 MiB; PSS 686.41 MB / 654.62 MiB**.
These are diagnostic figures only. Raw output:
`/workspace/desknotes/logs/f1-restored-memory.txt`. The measurement script
terminated the app afterward. Existing baseline screenshots were retained.
