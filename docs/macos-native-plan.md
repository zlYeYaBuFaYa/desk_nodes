# DeskNodes macOS native — source analysis and implementation plan

Checked-in specification paths below are relative to the repository root. This file is the task breakdown and validation boundary for later Codex feature patches. It does not record an application build, a Mac compile, or a native app run.

## 1. Inputs and baseline

Authoritative input is the 2026-11-07 requirements package (ZIP 1,033,864 bytes; 13 members; 1,495,424 uncompressed bytes). Member checks found no path traversal, absolute paths, backslashes, symlinks, or overwrites. The copies under `docs/spec/macos-native/` keep those member bytes. No application source is part of the docs commit. A separate plain-text extract of the PDF is not checked in.

Repository paths (ASCII, portable; original ZIP member in parentheses):

- `docs/spec/macos-native/requirements.md` (`DeskNodes/DeskNodes 需求文档.md`, dated 2026-11-07).
- `docs/spec/macos-native/requirements.pdf` (`DeskNodes/DeskNodes 需求文档.pdf`; same requirements).
- `docs/spec/macos-native/notes.txt` (`DeskNodes/说明.txt`): PNG/HTML correspondence, 2× PNG exports, and links to editable online artifacts. Those links are not required to implement.
- Five self-contained static HTML mockups (no scripts or external assets; styling is primarily inline, not a separate token JSON):
  1. `docs/spec/macos-native/prototypes/html/01-desktop-overview.html` (`原型/html/01-桌面总览.html`) — docked cards + free pinned/collapsed notes.
  2. `docs/spec/macos-native/prototypes/html/02-fullscreen-edge-reveal.html` (`原型/html/02-全屏边缘唤出.html`) — scrollable vertical reveal panel over fullscreen app.
  3. `docs/spec/macos-native/prototypes/html/03-note-states-menu.html` (`原型/html/03-便签状态与菜单.html`) — idle/hover/edit/collapse/dark, context menu, dock reorder, undo.
  4. `docs/spec/macos-native/prototypes/html/04-history-window.html` (`原型/html/04-历史记录窗口.html`) — month calendar, daily groups, carry/deleted badges, monthly rate.
  5. `docs/spec/macos-native/prototypes/html/05-settings-window.html` (`原型/html/05-设置窗口.html`) — general/docking/edge/hotkey/JSON controls.
- Matching PNGs with the same ASCII basenames under `docs/spec/macos-native/prototypes/png/` (`原型/png/` with the same Chinese basenames). HTML is visual specification, NOT shipped WebView implementation. Layout pt values in requirements take precedence over bitmap scaling.

Index: `docs/spec/macos-native/README.md`.

Git baseline for this native line, inspected before the docs commit and not rewritten:

- Repository `https://github.com/zlYeYaBuFaYa/desk_nodes`.
- `cursor/macos-native-desknodes` is created from `main`.
- `main` at branch creation: `4cedf910173cf40d927f1d7db9fc12dfd5f469ab` (initial commit; only `README.md`). Remote `main` had not moved past this SHA.
- Existing Tauri branches stay as they were and are not parents of this work:
  - `cursor/v0.1-desknodes` `09a70e405ec78ada2265a8af41e23f2b9ecb62de` (PR #1, open).
  - `cursor/v0.2-desknodes` `f486c12e14ed67203a19672eeb746f43eccbc8e6` (PR #2, open).
  - `cursor/v1.0-desknodes` `f4e633e4353bf9d87206e64975a7ca28421a1c2e` (PR #3, open).
- Old V1.0 work is NOT merged into `main`. Do not import its source or SQLite schema without an explicit migration decision.

Later Codex per-feature patches should be based on the docs commit on `cursor/macos-native-desknodes`, not on a Tauri branch and not on an older checkout. Apply those patches while preserving their author. This plan does not claim a Mac build.

## 2. Actual native stack and scope

Requirements explicitly select **Swift + AppKit backbone**, not a SwiftUI-only app:
- macOS **14+**, Chinese UI only; private personal use, no distribution, no sandbox, local Xcode signing. Paid Developer ID/notarization unnecessary for this scope.
- AppKit application lifecycle + menu-bar status item; **no Dock icon**.
- AppKit **NSPanel** note windows for levels, Spaces, docking.
- AppKit **NSTextView** item editing, especially Chinese IME correctness.
- **Core Animation** short springs for resident UI transitions.
- SwiftUI only for low-frequency **Settings and History** windows.
- System **SQLite**, local-only, **no third-party libraries**.
- Carbon **RegisterEventHotKey** for one configurable global shortcut (default Control–Option–N); no Accessibility permission requirement for that shortcut.
- CPU architecture is NOT specified. Recommend native-host builds first and validate arm64/x86_64 with Mac SDK when available; do not claim a universal target is required or supported before building it.
- No fixed memory threshold. Lightweight resident AppKit approach is specified; elegance first, no speculative memory optimization project.

### Differences from the previous Tauri product
This is a new macOS-native product, not a wrapper/port with feature parity assumed:
- No per-note hide, no global hide/show, no Touch ID, no idle/screen-share hiding; all absent by design.
- One global new-note shortcut only; no old toggle-all/management hotkeys.
- Optional titles; collapsed untitled note shows first item.
- Default desktop level (above desktop icons, below ordinary windows), plus ordinary/topmost; transient raise on click and restore on focus loss; all-topmost/restore switch.
- Docking strip (top/left/right), free notes, snap/detach, overflow tabs, fullscreen edge panel are NEW priorities.
- Default rollover **04:00**, configurable; completed items leave live list into immutable daily history; unfinished remain live and carry forward. No tomorrow group specified.
- New palette and 13pt/32pt sizing, not old Tauri tokens.
- History is calendar/day details and prototype monthly rate. No requirement for old weekly/streak stats or previous-day history editing.
- Cross-note item transfer, URL auto-links, opacity/font settings, old JSON import compatibility and Tauri migration are NOT requirements; do not invent them.
- No Windows/Linux native app, Markdown, reminders/deadlines or iCloud sync.

## 3. Design/interaction acceptance baseline

Match reviewed prototypes, then verify native screenshot fidelity in both system appearances:
- Solid low-saturation fills (not frosted glass). Fine border, subtle shadow, rounded 12pt corners, 14pt padding.
- Palette light / dark: 宣纸 `#F6F1E7/#2B2822` (default); 柠黄 `#FAF0C8/#35301A`; 杏 `#FBE7D6/#3A2A20`; 樱 `#F7E1E4/#3A2328`; 薰衣草 `#ECE6F5/#2A2536`; 雾蓝 `#E3ECF5/#1F2A36`; 薄荷 `#E2F0E8/#1E2E26`; 石墨 `#E8E8EA/#2A2A2D`.
- SF Pro/PingFang, title 13pt semibold, item 13pt regular, ~26pt row height; monospaced numerals. HTML reference text uses #1F1F1F; paper secondary/completed ~#5F5A52/#6F6A61. Use semantic dark text with equivalent readability.
- Free note default width 240pt; auto-height until 480pt then internal scroll; resize range 200×120 to 400×600pt. Collapsed 32pt.
- Top docking: 220×260pt per note, short screens 200pt height. Side docking width 240pt, content-driven height. Note spacing 12pt, available-screen inset 8pt.
- Hover-only quiet tools, color/context menu with desktop/ordinary/topmost selection, collapse, detach, destructive delete. Completed text gray + strike-through; small done/total count; dock overflow tabs. Untitled collapsed shows first item, not invented title.
- Native spring motion 0.25–0.35 sec for create/delete/snap/reorder/collapse/edge reveal; honor Reduce Motion. Dragged card modestly lifted/enlarged with deeper shadow and a placeholder slot (prototype 03).
- Undo toast enters from bottom, lives 5s, fades out; supports button and Command–Z. Both note and item deletion must preserve recoverability and history.
- Edge reveal always available (do not detect occlusion), left/right only, middle ~60% of edge; 0.25s dwell, 0.4s exit delay. Moving DOWN within panel must never dismiss it. All notes vertically scrollable; no duplicates, state shared with note windows.
- Dock bottom/left => reveal right; Dock right => reveal left. User override left/right; internal touching monitor edges never trigger. Note panels join all Spaces while ordinary live notes do not float over other apps' fullscreen; ONLY reveal panel exposes notes there.

## 4. Cohesive commit plan (Codex implements/tests, coordinator verifies)

One commit per row, sequential dependency unless noted; no coding yet. Every feature commit includes its tests and applicable source-linked acceptance evidence. Parent/cloud agent owns branch/remote sync. Pause/report on Codex quota; do not substitute assistant-written implementation.

| Commit | Feature / dependencies | Tests and acceptance |
|---|---|---|
| N1 | **Native skeleton + design system + documented Mac build entry.** From main; AppKit accessory/menu-bar app, macOS14 deployment, local nonsandboxed .app build entry, test target; shared eight-color tokens and one realistic NSPanel preview. No third-party dependencies. | Mac build/test via documented Xcode scheme; no Dock icon, status menu/quit functional, light/dark prototype-03 card screenshots. Provide documented native build commands for user execution. Model/token validation can run portably when tooling exists; AppKit build is explicitly deferred to user Mac acceptance, not a delivery blocker. |
| N2 | **SQLite domain/persistence foundation.** Stable IDs, notes/items/settings, dock/free placement and levels/order, daily snapshot/tombstone/carry data, transactions/versioned schema; isolated test store + injectable clock. | CRUD/reopen, Unicode, rollback/schema tests, separate test database; history snapshots cannot be mutated by live edits/deletion. Document native storage location chosen (spec does not prescribe one). |
| N3 | **Daily note editing and deletion protection.** Wire NSPanel to store; optional title, add/edit/check/delete, NSTextView Enter/empty-Backspace, same-note drag order, completed strike-through; item/note undo 5s + Command–Z, last-note creation path. | Mac IME marked text: Return accepts composition without splitting; focus/selection intact; restart persistence, no cross-note drag, undo expiry/order/history retention. Pure action/undo tests plus actual Chinese IME manual gate. |
| N4 | **Window chrome, sizing, levels and collapse.** Context palette, hover toolbar, pinned state, desktop/ordinary/topmost, all-topmost/restore preserving individual choices; transient raise then restore; resize/auto-height/scroll/collapse and Core Animation. | Layout bounds, restore state, no intermediate persisted animation frames; native overlaps/activation tests, untitled fallback, reduced-motion, color/light/dark screenshots. Desktop-icon-relative level and fullscreen behavior require real Mac acceptance. |
| N5 | **Docking and display geometry.** Top/left/right strip, chosen/default primary display, availableFrame insets, dock drag reorder + slot/lift, overflow tabs, drag detach and edge snap; screen disconnect migration to primary. | Pure geometry tests (negative origins, multiple screens, small heights, overflow, resize bounds); native main/secondary display, menu bar/Dock exclusion, unplug/reconnect/mixed DPI. Persist stable order/placement. |
| N6 | **Daily rollover and wake catch-up.** Default4am configurable boundary, completed archive and unfinished continuation, daily snapshot of final statuses, sleep/wake/startup catch-up with idempotency. | Fixed-clock boundary3:59/4:00, repeated triggers, restart/sleep multi-day gap, timezone/DST cases, no duplicates/loss; deleted notes/items retain marked history. Define missed-day policy explicitly rather than fabricate actions. Clock reversal must not corrupt snapshots (defensive behavior, not new UI feature). |
| N7 | **Fullscreen edge reveal.** Shared notes presentation in scroll panel; outer-edge topology/Dock auto-side detection/manual override; dwell/exit timers, all Spaces/ fullscreen-compatible reveal only. | Pure hit-region/topology/timer tests; native fullscreen app/Space switches, touching monitor seams/corners, move pointer down to checkbox, IME editing/focus and repeated open-close; no Accessibility/Input Monitoring permission claim until tested. Highest-risk native spike may run after N1 to retire uncertainty, production integration follows N3–N5. |
| N8 | **History SwiftUI window.** Calendar navigation, daily per-note lists, done/total, carried-to-date and deleted badges, monthly weighted completion + miniature calendar progress lines per prototype04; read-only snapshots unless revised spec. | Month/year/leap-day, no-data and deleted-note history, weighted rate and carry labels, long lists and dark screenshot; opening/closing low-frequency window must not break resident app. Depends N2/N6. |
| N9 | **Settings, shortcut/autostart, JSON round trip.** Prototype05 grouping; 4am picker, docking side/display, edge auto/manual with current-Dock explanation, Carbon configurable Ctrl–Option–N/conflict hint; first-launch autostart ASK using system integration; JSON full backup import/export incl history/settings. | Registration/conflict lifecycle and excluded-system combos, import schema/Unicode/tombstone/order/rollback on invalid/cancel; first-launch decline respected, toggle/relaunch; .app signing identity/autostart testing on native Mac. No fabricated native privacy entitlement/permissions. Depends N5–N8. |
| N10 | **Final native fidelity and acceptance hardening.** Cross-feature QA, native icon/local-run docs, record known limitations, backup instructions, Chinese copy/accessibility and light/dark/Reduce Motion polish against all five prototypes. No paid signing/distribution work. | Full Mac build + unit/UI tests, physical monitor/Space/fullscreen/wake/IME/autostart/manual matrix; screenshots for all5 scenarios and sizes; no app sandbox/Dock icon; restart with data intact. Only claim hardware actually tested. No memory threshold gate. |

### Execution checkpoints
- User clarified delivery is native macOS source from a Linux cloud environment. N1 supplies a coherent local Mac build/run entry; native build/runtime acceptance is deferred to the user. A Mac worker/Xcode is NOT required to proceed or deliver. Do not call unexecuted Mac commands tested.
- N7 needs especially careful public-API/requirements review for pointer tracking, all-Spaces/fullscreen panels and permissions. Supply focused user-Mac acceptance steps; do not claim this was demonstrated on Linux. Surface any architectural permission-model deviation before adding it.
- Inspect and test public API feasibility for Dock location and screen topology; do not rely on private APIs without surfacing risk. Topmost/desktop stacking vs fullscreen is separate from reveal-panel collectionBehavior.
- Native import data format is new unless explicitly agreed; do not claim automatic Tauri migration.

## 5. Validation capabilities and requirements

**Mac required:** macOS14+ machine, compatible Xcode/macOS SDK + selected Command Line Tools; Swift compiler/system SQLite3 module; local .app signing (no paid identity), unsandboxed config, permissions dialogs under real user session. Use Xcode scheme/test target or an equivalent native project that Codex selects and documents; no third-party project generator is mandated. Real monitor/fullscreen/Spaces/Dock/hotkey/IME/autostart/accessory-app acceptance cannot be simulated credibly on Linux. If architecture support is expanded, build/test each promised architecture on a Mac toolchain. Sleep/wake and Reduce Motion have manual/system integration gates.

**Linux legitimate:** archive integrity/path checks, read HTML/CSS/assets, compare tokens/text/schema/JSON and docs; pure Swift Foundation/domain logic can compile/test ONLY if a Swift toolchain and compatible SQLite module are actually available and isolated from AppKit/SwiftUI/Carbon. SQLite queries/JSON fixtures can be tested here but are not evidence Swift bridge or AppKit runtime compiles. No fake Darwin stubs as native acceptance, no Linux browser screenshot presented as native UI. Do not alter system settings to manufacture success.

Per commit record actual commands/results, source SHA, screenshot paths and untested platform behavior. Final quality prioritizes faithful, calm visual hierarchy and stable input/focus over speculative optimizations.

## 6. Decisions and genuine open points

Not blocking document planning: requirement's final eight unchecked bullets are explicitly *recommended defaults pending prior review*, not omitted scope. Proceed per the written defaults (carry/completed archive,4am,all-note vertical reveal,transient raise,in-note reorder,optional title,deleted-history retention,JSON import/export) and tell parent they remain revisable; no need to ask eight redundant questions now.

Not specified: CPU architectures, precise allowed rollover-hour range, native data directory/JSON version, historical title/color snapshot policy, missed-day empty snapshot behavior, thresholds for dock snap/overflow and ordering within reveal. Codex should make/document conservative testable defaults, flag consequential persistence semantics rather than silently copying old Tauri behavior.

Native verification limitation, NOT a delivery blocker: user explicitly accepts Linux cloud delivery and will build/run locally on Mac. Implement complete native macOS code using Codex, validate requirements/prototype consistency plus portable tests actually runnable on Linux, document all unexecuted Mac gates, and have parent/cloud agent push the separate native branch. Do not reinterpret colloquial “iOS” as an iOS app. CLI on box is available (`codex-cli 0.166.0`, authenticated using ChatGPT); remaining generation quota is not verified by login status. No coding session started in this phase.

## User acceptance-boundary clarification

As clarified during this analysis: no Mac worker is required. Deliver native macOS implementation, not a Linux app or a web mockup; Linux validation covers only what actually runs there. Native Xcode build, signed local launch, input/focus/Spaces/fullscreen/physical hardware validation are explicit user-run follow-ups. Final report must distinguish passed portable tests, static source/visual checks, and unexecuted Mac tests. Parent/cloud agent owns remote push; executor never pushes directly.
