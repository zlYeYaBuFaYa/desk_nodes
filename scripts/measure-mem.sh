#!/usr/bin/env bash
# An isolated session prevents counting other applications' WebKit processes.
set -euo pipefail
cd "$(dirname "$0")/.."
export CARGO_BUILD_JOBS=2
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/workspace/desknotes/target}"
export DISPLAY="${DISPLAY:-:3}"
export GDK_BACKEND=x11
binary="${DESKNODES_BINARY:-$CARGO_TARGET_DIR/release/desk-nodes}"
if [[ ! -x "$binary" ]]; then
  npm run tauri build -- --no-bundle
fi
export DESKNODES_BINARY="$binary"
exec python3 - <<'PY'
import os, pathlib, signal, subprocess, time
logs = pathlib.Path('/workspace/desknotes/logs')
logs.mkdir(parents=True, exist_ok=True)
log_path = logs / ('memory-app-' + time.strftime('%Y%m%d-%H%M%S') + '.log')
log = log_path.open('w')
app = subprocess.Popen([os.environ['DESKNODES_BINARY']], stdout=log, stderr=log, start_new_session=True)
sid = app.pid
succeeded = False
expected = int(os.getenv('DESKNODES_EXPECTED_NOTES', '1'))

def processes():
    entries = {}
    for d in pathlib.Path('/proc').iterdir():
        if not d.name.isdigit(): continue
        try:
            stat = (d / 'stat').read_text().rsplit(')', 1)[1].split()
            entries[int(d.name)] = (int(stat[1]), int(stat[3]), d)
        except (OSError, ValueError, IndexError): pass
    owned = {sid}
    while True:
        more = {pid for pid, (ppid, session, _) in entries.items() if ppid in owned or session == sid}
        if more <= owned: break
        owned |= more
    return [(pid, entries[pid][2]) for pid in sorted(owned) if pid in entries]

try:
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        if app.poll() is not None: raise RuntimeError(f'App exited {app.returncode}; see {log_path}')
        rows = processes()
        names = [str((d/'comm').read_text()).strip() for _, d in rows]
        if any('WebKitWeb' in n for n in names) and 'persistent notes ready' in log_path.read_text(): break
        time.sleep(.5)
    else: raise RuntimeError('Timed out waiting for notes and WebKit children')
    time.sleep(float(os.getenv('SETTLE_SECONDS', '15')))
    print(f'DeskNodes memory measurement — {time.strftime("%Y-%m-%d %H:%M:%S %z")}')
    print(f'Binary: {os.environ["DESKNODES_BINARY"]}; DISPLAY={os.environ["DISPLAY"]}; session={sid}')
    print(f'App log: {log_path}; {expected} notes expected; settled {os.getenv("SETTLE_SECONDS", "15")}s')
    if subprocess.run(['sh', '-c', 'command -v wmctrl >/dev/null'], check=False).returncode == 0:
        windows = subprocess.check_output(['wmctrl', '-l'], text=True)
        count = sum('DeskNodes · ' in line for line in windows.splitlines())
        if count != expected: raise RuntimeError(f'Expected {expected} X11 note windows, found {count}')
        print(f'X11 window count: {count}')
    print('PID       RSS KiB    PSS KiB  COMMAND')
    rss_total = pss_total = 0
    pss_complete = True
    web_count = 0
    for pid, d in processes():
        try:
            status = dict(line.split(':', 1) for line in (d/'status').read_text().splitlines() if ':' in line)
            rss = int(status.get('VmRSS', '0 kB').split()[0])
            cmd = (d/'cmdline').read_bytes().replace(b'\0', b' ').decode(errors='replace').strip()
            if not cmd: continue
            web_count += 'WebKitWebProcess' in cmd
            try:
                roll = dict(line.split(':', 1) for line in (d/'smaps_rollup').read_text().splitlines() if ':' in line)
                pss = int(roll['Pss'].split()[0])
                pss_total += pss
            except (OSError, KeyError):
                pss = None
                pss_complete = False
            rss_total += rss
            print(f'{pid:<8} {rss:>9} {str(pss) if pss is not None else "N/A":>10}  {cmd}')
        except (OSError, ValueError): raise RuntimeError('Process changed during measurement; rerun for a stable snapshot')
    if not web_count: raise RuntimeError('No live WebKitWebProcess at measurement')
    print(f'RSS sum: {rss_total} KiB = {rss_total*1024/1e6:.2f} MB = {rss_total/1024:.2f} MiB')
    print(f'PSS sum: {pss_total} KiB = {pss_total*1024/1e6:.2f} MB = {pss_total/1024:.2f} MiB' if pss_complete else 'PSS sum: unavailable (some processes unreadable)')
    print('RSS double-counts shared pages; PSS apportions them. GPU/server memory outside this session is excluded.')
    succeeded = True
    if os.getenv('KEEP_APP') == '1': print(f'App left running for screenshots; stop with: kill -- -{sid}')
finally:
    if not succeeded or os.getenv('KEEP_APP') != '1' or app.poll() is not None:
        try: os.killpg(sid, signal.SIGTERM)
        except ProcessLookupError: pass
    log.close()
PY
