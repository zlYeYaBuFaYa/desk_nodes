# F8 — Move items between notes

Right-click any open, completed, or tomorrow item and expand 「移动到…」. The inset target list uses the existing menu surface, with a small note-color dot and ellipsized titles. It includes active notes (including hidden notes), excludes the current note, scrolls when necessary, and shows muted 「没有其他便签」 when empty. Escape and outside clicks dismiss it. Ordinary text editing, URL activation, and drag handles retain their existing handlers.

The transactional Rust operation validates both active notes and the source item, changes only `note_id` and `sort_order`, and appends after all items on the target's matching day. ID, content, day, done/done_at, creation time, and carry metadata survive. Missing/deleted targets and stale source IDs fail without removing the item. Global `items-changed` refreshes both windows and management. Moves join the mutation queue used by rollover.

A five-second 「已移动 / 撤销」 toast reverses the move using the same operation. Undo appends to the source day's list rather than overwriting any intervening reorder. If the destination item or original note has since disappeared, undo fails safely without recreating or duplicating data. Rollover clears the toast.

Collapse polish is skipped. Native resize events immediately persist expanded geometry and broadcast `notes-changed`; stepping the native size would persist intermediate heights and trigger repeated frontend refreshes. The existing collapsed-popover size effect also controls that same window. A clean tween needs coordinated geometry/event suppression, so F7's reliable snap remains unchanged. No collapse-motion screenshot is produced.

Validation logs: `/workspace/desknotes/logs/f8-{build,test,clippy,xcheck,native-build,smoke,memory}.log`. The native binary uses embedded production assets (`cargo build --features tauri/custom-protocol`). Rust has 30 passing tests, including two new move tests covering today open/completed, tomorrow, identity/metadata/order, and unavailable targets/wrong source. Windows GNU and macOS stub checks verify Rust types/cfg; they do not verify platform runtime or packaging.

F1 regression review: independent note webviews, frameless rounded surfaces, palette/theme tokens, pin/visibility, native resize/geometry persistence, tray behavior, data-dir override, and fake clock remain intact. No memory optimization, commits, pushes, git configuration changes, or machine configuration changes.

Native F8 smoke passed today/completed/tomorrow moves, undo, ID/day/done checks, Escape workflow, and light/dark captures. F7 regression smoke passed collapse/expand geometry and persistence, URL launcher versus text editing, and tomorrow addition.

Five visible independent notes, empty lists, Linux debug binary with embedded production frontend, five seconds settled: aggregate process-tree **RSS 1693.12 MB (1614.68 MiB), PSS 764.51 MB (729.09 MiB)**. This diagnostic snapshot exceeds the specification's 200 MB goal and is not release-build acceptance evidence. RSS double-counts shared pages; PSS apportions them. External display server/GPU allocations are excluded. No optimization was performed. Raw evidence: `/workspace/desknotes/logs/f8-memory.log`.

Requested captures: `/workspace/desknotes/shots/f8-move-menu-light.png`, `/workspace/desknotes/shots/f8-move-menu-dark.png`, `/workspace/desknotes/shots/f8-moved-light.png`.
