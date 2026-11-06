# DeskNodes

Quiet, Morandi-colored desktop sticky notes, built with Tauri 2, Svelte 5,
TypeScript and Vite. Supported targets: macOS, Windows, and Linux (Debian 13
trixie x86_64, X11). This Feature 1 prototype opens **five independent notes**;
text is demonstration content, not an editable or persistent todo database.

## Development

Install Node.js 24+, npm, Rust stable and the platform's Tauri prerequisites.
On Debian 13:

```sh
sudo apt install build-essential pkg-config libwebkit2gtk-4.1-dev libgtk-3-dev \
  librsvg2-dev patchelf libayatana-appindicator3-dev
npm install
export CARGO_BUILD_JOBS=2
export CARGO_TARGET_DIR=/workspace/desknotes/target
DISPLAY=:3 GDK_BACKEND=x11 npm run tauri dev
```

On macOS install Xcode command line tools; on Windows install MSVC build tools
and WebView2. `npm run tauri build` creates the production app and platform
bundles; `npm run tauri build -- --no-bundle` builds only the production binary.
The checked-in `.cargo/config.toml` limits jobs to 2 and puts artifacts in
`/workspace/desknotes/target` for this workspace. Elsewhere override
`CARGO_TARGET_DIR` with a writable local directory.

Each note uses the same page with an `?id=` route. Drag the titlebar, resize the
window edges, click the pin to toggle always-on-top, the dot to cycle all eight
colors, or minus to hide. The moon/sun button overrides appearance for that note;
default appearance follows `prefers-color-scheme`. `DESKNODES_THEME=light` or
`DESKNODES_THEME=dark` overrides all notes at launch, useful for screenshots.

The tray offers **New note / Show all / Hide all / Quit**. A tiny native control
window exposes the same menu even without a working tray host. This uses Tauri's
`unstable` feature for a native window without an extra WebView. Its close button
is intentionally ignored so hiding notes never removes the recovery path.
Closing a note hides it. Quit from the tray or control menu to exit. New notes
and appearance/pin changes are in memory; restart always restores the original
five demo notes. No SQLite schema, CRUD, global shortcuts or single-instance
behavior is included yet.

The WebView data directory uses the platform data root plus `DeskNodes`:
Linux `~/.local/share/DeskNodes`, macOS `~/Library/Application Support/DeskNodes`,
Windows `%APPDATA%\DeskNodes`. The window builder explicitly joins `DeskNodes`
onto Tauri's `data_dir()` because `app_data_dir()` uses the bundle identifier.
WebKit may write cache/cookies there; F1 does not persist note content. macOS
WebKit manages its own cache store; future note persistence will use the same
product data path.

## Checks and memory

```sh
npm run build                         # includes Svelte/TypeScript checking
cargo test --manifest-path src-tauri/Cargo.toml
cargo clippy --manifest-path src-tauri/Cargo.toml -- -D warnings
scripts/xcheck.sh
scripts/measure-mem.sh | tee /workspace/desknotes/logs/memory-release.txt
```

`xcheck.sh` checks Windows GNU and macOS x86_64 Rust cfg paths; it requires
installed Rust targets, MinGW (including windres), and the check-only Darwin C
stubs in `/workspace/aienv/darwin-stub` (`DARWIN_STUB_DIR` can override this).
It does not link or validate native behavior on those systems.

`measure-mem.sh` uses an existing release binary, or builds one when absent.
Run a production build first after source changes: it intentionally does not
check binary freshness. It starts an isolated process session on `DISPLAY=:3`,
waits for five notes plus WebKit processes, settles for 15 seconds, then sums
RSS and readable PSS for the main process and all session members/descendants.
This avoids counting other apps' WebKit processes. It terminates that session
after measurement. `KEEP_APP=1` leaves it running for inspection/screenshots;
`SETTLE_SECONDS=30` changes the settling period; `DESKNODES_BINARY=/absolute/path`
selects a debug or other binary. App logs go to `/workspace/desknotes/logs/`.
Python 3 and Linux `/proc` are required for memory measurement. A missed target
is reported as FAIL but the script exits 0 after a successful measurement;
launch/readiness failures exit nonzero. See [the measured report](docs/perf-v0.1.md).

Token CSS is generated from the original design pack: `npm run tokens`.
Screenshots use ImageMagick `import` on the X11 root window.

## 中文说明

DeskNodes 是跨平台桌面便签，支持 macOS、Windows 和 Debian 13 Linux。
当前 F1 仅验证五个独立窗口、莫兰迪配色、深浅主题、置顶、托盘与内存占用。
示例内容不提供编辑或持久化；完整便签/待办功能将在后续实现。
托盘不可用时，可通过常驻原生控制窗口新建、显示、隐藏或退出。
使用 `npm install` 安装依赖，`npm run tauri dev` 开发，
`npm run tauri build` 构建；运行 `scripts/measure-mem.sh` 测量五张便签的内存。
