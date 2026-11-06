mod autostart;
mod settings;
use tauri_plugin_dialog::DialogExt;
use tauri_plugin_global_shortcut::GlobalShortcutExt;
mod data_dir;
mod day;
mod db;
mod history;
use std::collections::HashSet;
struct Rollover {
    path: std::path::PathBuf,
    waiting: std::sync::Mutex<Option<HashSet<String>>>,
    recovered: bool,
}

fn finish_rollover(app: &tauri::AppHandle) -> Result<()> {
    let state = app.state::<Rollover>();
    let store = app.state::<Store>();
    let mut c = connection(&store)?;
    if day::target(&c, &day::WallClock).map_err(err)? > day::current(&c).map_err(err)? {
        day::backup(&state.path).map_err(err)?;
        day::sync(&mut c, &day::WallClock).map_err(err)?;
    }
    // Release paused editors even if the clock moved back during preparation.
    app.emit("day-changed", ()).map_err(err)
}
#[tauri::command]
fn rollover_ready(app: tauri::AppHandle, window: tauri::WebviewWindow) -> Result<()> {
    let state = app.state::<Rollover>();
    let mut waiting = state.waiting.lock().map_err(err)?;
    if let Some(labels) = waiting.as_mut() {
        labels.remove(window.label());
        if labels.is_empty() {
            finish_rollover(&app)?;
            *waiting = None;
        }
    }
    Ok(())
}
#[tauri::command]
fn recovery_notice(app: tauri::AppHandle) -> bool {
    let recovered = app.state::<Rollover>().recovered;
    if recovered && let Err(e) = app.emit("backup-restored", ()) {
        eprintln!("Recovery notice: {e}");
    }
    recovered
}
use db::{Note, Store};
use tauri::{
    Emitter, Manager, WebviewUrl, WebviewWindowBuilder,
    menu::{CheckMenuItem, Menu, MenuItem},
    tray::TrayIconBuilder,
};
type Result<T> = std::result::Result<T, String>;
fn err(e: impl std::fmt::Display) -> String {
    e.to_string()
}
fn connection(store: &Store) -> Result<std::sync::MutexGuard<'_, rusqlite::Connection>> {
    store.0.lock().map_err(err)
}
#[derive(Default)]
struct Geometry {
    busy: std::sync::Mutex<HashSet<String>>,
}

struct Preferences {
    actions: std::sync::Mutex<()>,
    hidden: std::sync::Mutex<settings::Hidden>,
    status: std::sync::Mutex<std::collections::BTreeMap<String, String>>,
}
#[tauri::command]
fn get_settings(app: tauri::AppHandle) -> Result<std::collections::BTreeMap<String, String>> {
    let mut values = settings::load(&*connection(&app.state::<Store>())?)?;
    values.extend(
        app.state::<Preferences>()
            .status
            .lock()
            .map_err(err)?
            .clone(),
    );
    Ok(values)
}
fn dispatch_action(app: &tauri::AppHandle, id: String) {
    let app = app.clone();
    // Serialize native actions without blocking the UI or hotkey callback.
    tauri::async_runtime::spawn_blocking(move || {
        let prefs = app.state::<Preferences>();
        let result = (|| -> Result<()> {
            let _serial = prefs.actions.lock().map_err(err)?;
            action(&app, &id)
        })();
        if let Err(e) = result {
            eprintln!("Action: {e}");
        }
    });
}
fn register_binding(app: &tauri::AppHandle, key: &str, value: &str) -> Result<()> {
    let action_id = match key {
        "shortcut_toggle_all" => "toggle",
        "shortcut_new_note" => "new",
        _ => "management",
    }
    .to_owned();
    let shortcut = value
        .parse::<tauri_plugin_global_shortcut::Shortcut>()
        .map_err(err)?;
    let down = std::sync::atomic::AtomicBool::new(false);
    app.global_shortcut()
        .on_shortcut(shortcut, move |app, _, event| {
            let pressed = event.state == tauri_plugin_global_shortcut::ShortcutState::Pressed;
            if !down.swap(pressed, std::sync::atomic::Ordering::SeqCst) && pressed {
                dispatch_action(app, action_id.clone());
            }
        })
        .map_err(|e| format!("快捷键不可用或已被占用：{e}"))
}
#[tauri::command]
fn update_setting(app: tauri::AppHandle, key: String, value: String) -> Result<()> {
    settings::validate(&key, &value)?;
    let store = app.state::<Store>();
    let old = settings::load(&*connection(&store)?)?[&key].clone();
    if key.starts_with("shortcut_") {
        let candidate = value
            .parse::<tauri_plugin_global_shortcut::Shortcut>()
            .map_err(err)?;
        let previous = old
            .parse::<tauri_plugin_global_shortcut::Shortcut>()
            .map_err(err)?;
        if candidate != previous {
            if app.global_shortcut().is_registered(candidate) {
                return Err("此快捷键已用于其他操作".into());
            }
            register_binding(&app, &key, &value)?;
            if let Err(e) = app.global_shortcut().unregister(previous) {
                let _ = app.global_shortcut().unregister(candidate);
                return Err(err(e));
            }
        } else if !app.global_shortcut().is_registered(previous) {
            register_binding(&app, &key, &value)?;
        }
    }
    if key == "autostart" {
        autostart::set(&app, value == "1")?;
    }
    settings::save(&*connection(&store)?, &key, &value)?;
    app.state::<Preferences>()
        .status
        .lock()
        .map_err(err)?
        .remove(&format!("{key}_status"));
    if key == "autostart" {
        app.state::<Preferences>()
            .status
            .lock()
            .map_err(err)?
            .insert(
                "autostart_status".into(),
                if value == "1" {
                    "已启用"
                } else {
                    "未启用"
                }
                .into(),
            );
    }
    app.emit("settings-changed", get_settings(app.clone())?)
        .map_err(err)
}
#[tauri::command]
async fn backup_data(app: tauri::AppHandle, import: bool) -> Result<()> {
    tauri::async_runtime::spawn_blocking(move || -> Result<()> {
        let dialog = app.dialog().file().add_filter("DeskNodes JSON", &["json"]);
        let path = if import {
            dialog.blocking_pick_file()
        } else {
            dialog
                .set_file_name("DeskNodes-backup.json")
                .blocking_save_file()
        };
        let Some(path) = path else { return Ok(()) };
        let path = path.into_path().map_err(err)?;
        if import {
            let json = std::fs::read_to_string(path).map_err(err)?;
            // Validate in an isolated database before offering replacement.
            let mut check = db::open(std::path::Path::new(":memory:")).map_err(err)?;
            settings::import(&mut check, &json)?;
            if !app
                .dialog()
                .message("将替换全部便签、历史与设置。建议先导出当前数据。继续吗？")
                .title("导入备份")
                .buttons(tauri_plugin_dialog::MessageDialogButtons::OkCancel)
                .blocking_show()
            {
                return Ok(());
            }
            settings::import(&mut *connection(&app.state::<Store>())?, &json)?;
            app.restart();
        } else {
            std::fs::write(
                path,
                settings::export(&*connection(&app.state::<Store>())?)?,
            )
            .map_err(err)?;
        }
        Ok(())
    })
    .await
    .map_err(err)?
}
#[tauri::command]
fn open_data_dir(app: tauri::AppHandle) -> Result<()> {
    let path = app
        .state::<Rollover>()
        .path
        .parent()
        .ok_or("Missing directory")?
        .to_path_buf();
    #[cfg(target_os = "linux")]
    let mut command = std::process::Command::new("xdg-open");
    #[cfg(target_os = "macos")]
    let mut command = std::process::Command::new("open");
    #[cfg(target_os = "windows")]
    let mut command = std::process::Command::new("explorer");
    command.arg(path).spawn().map_err(err)?;
    Ok(())
}
fn all_visibility(app: &tauri::AppHandle, hide: bool) -> Result<()> {
    let notes = db::active(&*connection(&app.state::<Store>())?).map_err(err)?;
    let prefs = app.state::<Preferences>();
    let mut hidden = prefs.hidden.lock().map_err(err)?;
    let ids = if hide {
        hidden.hide(&notes);
        notes
            .iter()
            .filter(|n| n.visible)
            .map(|n| n.id.clone())
            .collect::<HashSet<_>>()
    } else {
        hidden.restore()
    };
    drop(hidden);
    for id in ids {
        set_visible(app, &format!("note-{id}"), !hide)?;
    }
    if hide && settings::load(&*connection(&app.state::<Store>())?)?["hide_all_hint_shown"] == "0" {
        settings::save(
            &*connection(&app.state::<Store>())?,
            "hide_all_hint_shown",
            "1",
        )?;
        open_management(app, "notes")?;
        // Send after the panel has mounted; the persisted flag prevents repetition.
        let handle = app.clone();
        std::thread::spawn(move || {
            std::thread::sleep(std::time::Duration::from_millis(800));
            let _ = handle.emit("hide-all-hint", ());
        });
    }
    Ok(())
}
#[derive(Clone, Copy, Debug, PartialEq)]
struct Rect {
    x: i32,
    y: i32,
    w: i32,
    h: i32,
}
fn clamp(r: Rect, area: Rect) -> Rect {
    let w = r.w.clamp(220, 600).min(area.w);
    let h = r.h.clamp(160, 900).min(area.h);
    Rect {
        x: r.x.clamp(area.x, area.x + area.w - w),
        y: r.y.clamp(area.y, area.y + area.h - h),
        w,
        h,
    }
}
fn place(app: &tauri::AppHandle, n: &mut Note, fresh: bool) -> Result<()> {
    let monitors = app.available_monitors().map_err(err)?;
    let primary = app.primary_monitor().map_err(err)?;
    let chosen = if fresh {
        app.cursor_position().ok().and_then(|p| {
            monitors.iter().find(|m| {
                let a = m.work_area();
                p.x >= f64::from(a.position.x)
                    && p.y >= f64::from(a.position.y)
                    && p.x < f64::from(a.position.x) + f64::from(a.size.width)
                    && p.y < f64::from(a.position.y) + f64::from(a.size.height)
            })
        })
    } else {
        monitors.iter().find(|m| {
            let a = tauri::LogicalRect {
                position: m.work_area().position.to_logical::<i32>(m.scale_factor()),
                size: m.work_area().size.to_logical::<i32>(m.scale_factor()),
            };
            n.x >= a.position.x
                && n.y >= a.position.y
                && n.x < a.position.x + a.size.width
                && n.y < a.position.y + a.size.height
        })
    }
    .or(primary.as_ref())
    .or(monitors.first());
    if let Some(m) = chosen {
        let a = tauri::LogicalRect {
            position: m.work_area().position.to_logical::<i32>(m.scale_factor()),
            size: m.work_area().size.to_logical::<i32>(m.scale_factor()),
        };
        let area = Rect {
            x: a.position.x,
            y: a.position.y,
            w: a.size.width,
            h: a.size.height,
        };
        if fresh {
            n.x = area.x + area.w * 3 / 5 - n.width / 2;
            n.y = area.y + (area.h - n.height) / 2;
        }
        let r = clamp(
            Rect {
                x: n.x,
                y: n.y,
                w: n.width,
                h: n.height,
            },
            area,
        );
        n.x = r.x;
        n.y = r.y;
        n.width = r.w;
        n.height = r.h;
    }
    Ok(())
}
// Tauri 2 exposes window scale events, but no portable display topology event.
// Include primary identity, scale and work areas (panels/docks), not just resolution.
fn monitor_fingerprint(app: &tauri::AppHandle) -> Result<String> {
    let mut entries = app
        .available_monitors()
        .map_err(err)?
        .iter()
        .map(|m| {
            format!(
                "{:?}:{:?}:{:?}:{}",
                m.name(),
                m.position(),
                m.work_area(),
                m.scale_factor()
            )
        })
        .collect::<Vec<_>>();
    entries.sort();
    Ok(format!(
        "{:?}:{entries:?}",
        app.primary_monitor().map_err(err)?
    ))
}
fn reclamp_visible(app: &tauri::AppHandle) -> Result<bool> {
    let prefs = app.state::<Preferences>();
    let _serial = prefs.actions.lock().map_err(err)?;
    let geometry = app.state::<Geometry>();
    let mut busy = geometry.busy.lock().map_err(err)?;
    if !busy.is_empty() {
        return Ok(false);
    }
    let notes = db::active(&*connection(&app.state::<Store>())?).map_err(err)?;
    let labels = notes
        .iter()
        .filter(|n| n.visible)
        .map(|n| format!("note-{}", n.id))
        .collect::<Vec<_>>();
    busy.extend(labels.iter().cloned());
    drop(busy);
    let result = (|| -> Result<()> {
        for mut n in notes.into_iter().filter(|n| n.visible) {
            if let Some(w) = app.get_webview_window(&format!("note-{}", n.id)) {
                place(app, &mut n, false)?;
                w.set_position(tauri::LogicalPosition::new(n.x, n.y))
                    .map_err(err)?;
                w.set_size(tauri::LogicalSize::new(
                    n.width,
                    if n.collapsed { 58 } else { n.height },
                ))
                .map_err(err)?;
                std::thread::sleep(std::time::Duration::from_millis(80));
                let scale = w.scale_factor().map_err(err)?;
                let p = w.outer_position().map_err(err)?.to_logical::<i32>(scale);
                let size = w.inner_size().map_err(err)?.to_logical::<i32>(scale);
                n.x = p.x;
                n.y = p.y;
                n.width = size.width;
                if !n.collapsed {
                    n.height = size.height;
                }
                db::save(&*connection(&app.state::<Store>())?, &n).map_err(err)?;
            }
        }
        Ok(())
    })();
    let mut busy = geometry.busy.lock().map_err(err)?;
    for label in labels {
        busy.remove(&label);
    }
    drop(busy);
    result?;
    changed(app)?;
    Ok(true)
}
fn spawn(app: &tauri::AppHandle, n: &Note, fresh: bool) -> Result<()> {
    if let Some(w) = app.get_webview_window(&format!("note-{}", n.id)) {
        let mut placed = n.clone();
        place(app, &mut placed, fresh)?;
        w.set_position(tauri::LogicalPosition::new(placed.x, placed.y)).map_err(err)?;
        w.set_size(tauri::LogicalSize::new(placed.width, if placed.collapsed {58} else {placed.height})).map_err(err)?;
        db::save(&*connection(&app.state::<Store>())?, &placed).map_err(err)?;
        w.show().map_err(err)?;
        return Ok(());
    }
    if let Some(labels) = app
        .state::<Rollover>()
        .waiting
        .lock()
        .map_err(err)?
        .as_mut()
    {
        labels.insert(format!("note-{}", n.id));
    }
    let theme = std::env::var("DESKNODES_THEME").unwrap_or("system".into());
    let window = WebviewWindowBuilder::new(
        app,
        format!("note-{}", n.id),
        WebviewUrl::App(format!("index.html?id={}&theme={theme}&new={fresh}", n.id).into()),
    )
    .title(format!("DeskNodes · {}", n.title))
    .inner_size(
        n.width as f64,
        if n.collapsed { 58. } else { n.height as f64 },
    )
    .position(n.x as f64, n.y as f64)
    .min_inner_size(220., if n.collapsed { 58. } else { 160. })
    .max_inner_size(600., 900.)
    .always_on_top(n.pinned)
    .decorations(false)
    .transparent(true)
    .shadow(false)
    .skip_taskbar(true)
    .visible_on_all_workspaces(true)
    .build()
    .map_err(err)?;
    // Apply once mapped: some X11 window managers offset the initial builder
    // position by their decoration metrics even for undecorated windows.
    window
        .set_position(tauri::LogicalPosition::new(n.x, n.y))
        .map_err(err)?;
    Ok(())
}
fn changed(app: &tauri::AppHandle) -> Result<()> {
    rebuild_menu(app)?;
    app.emit("notes-changed", ()).map_err(err)
}
#[tauri::command]
fn list_notes(store: tauri::State<Store>) -> Result<Vec<Note>> {
    db::active(&*connection(&store)?).map_err(err)
}
#[tauri::command]
fn today_items(store: tauri::State<Store>, id: String) -> Result<Vec<db::Item>> {
    db::today(&*connection(&store)?, &id).map_err(err)
}
#[tauri::command]
fn tomorrow_items(store: tauri::State<Store>, id: String) -> Result<Vec<db::Item>> {
    let c = connection(&store)?;
    db::items_on(&c, &id, &day::tomorrow(&c).map_err(err)?).map_err(err)
}
#[tauri::command]
fn open_url(url: String) -> Result<()> {
    let parsed = tauri::Url::parse(&url).map_err(err)?;
    if !matches!(parsed.scheme(), "http" | "https") || parsed.host_str().is_none() {
        return Err("Invalid web URL".into());
    }
    #[cfg(target_os = "linux")]
    let mut command = std::process::Command::new("xdg-open");
    #[cfg(target_os = "macos")]
    let mut command = std::process::Command::new("open");
    #[cfg(target_os = "windows")]
    let mut command = std::process::Command::new("rundll32.exe");
    #[cfg(target_os = "windows")]
    command.arg("url.dll,FileProtocolHandler");
    command.arg(parsed.as_str()).spawn().map_err(err)?;
    Ok(())
}
#[tauri::command]
fn mutate_item(
    app: tauri::AppHandle,
    window: tauri::WebviewWindow,
    store: tauri::State<Store>,
    op: String,
    item: db::Item,
    order: Vec<String>,
) -> Result<()> {
    let id = window
        .label()
        .strip_prefix("note-")
        .ok_or("Invalid window")?;
    db::item_mutation(&mut *connection(&store)?, id, &op, &item, &order).map_err(err)?;
    app.emit("items-changed", id).map_err(err)
}
#[tauri::command]
fn move_item(
    app: tauri::AppHandle,
    window: tauri::WebviewWindow,
    store: tauri::State<Store>,
    item_id: String,
    target: String,
    source: Option<String>,
) -> Result<()> {
    let home = window
        .label()
        .strip_prefix("note-")
        .ok_or("Invalid window")?;
    // A source override only allows undo back to this window's own note.
    let from = source.as_deref().unwrap_or(home);
    if source.is_some() && target != home {
        return Err("Invalid move undo".into());
    }
    db::move_item(&mut *connection(&store)?, from, &target, &item_id).map_err(err)?;
    app.emit("items-changed", ()).map_err(err)
}
fn open_management(app: &tauri::AppHandle, tab: &str) -> Result<()> {
    #[cfg(target_os = "macos")]
    app.set_activation_policy(tauri::ActivationPolicy::Regular)
        .map_err(err)?;
    if let Some(w) = app.get_webview_window("management") {
        w.unminimize().map_err(err)?;
        w.show().map_err(err)?;
        w.set_focus().map_err(err)?;
        w.emit("panel-tab", tab).map_err(err)?;
    } else {
        let theme = std::env::var("DESKNODES_THEME").unwrap_or("system".into());
        WebviewWindowBuilder::new(
            app,
            "management",
            WebviewUrl::App(format!("index.html?panel=1&tab={tab}&theme={theme}").into()),
        )
        .title("DeskNodes")
        .inner_size(1040., 680.)
        .min_inner_size(900., 560.)
        .center()
        .build()
        .map_err(err)?;
    }
    Ok(())
}
#[tauri::command]
fn panel_note(
    app: tauri::AppHandle,
    id: String,
    visible: Option<bool>,
    pinned: Option<bool>,
) -> Result<()> {
    if let Some(visible) = visible {
        set_visible(&app, &format!("note-{id}"), visible)?;
    }
    if let Some(pinned) = pinned {
        let store = app.state::<Store>();
        let mut n = db::active(&*connection(&store)?)
            .map_err(err)?
            .into_iter()
            .find(|n| n.id == id)
            .ok_or("Note unavailable")?;
        n.pinned = pinned;
        if let Some(w) = app.get_webview_window(&format!("note-{id}")) {
            w.set_always_on_top(pinned).map_err(err)?;
        }
        connection(&store)?
            .execute(
                "UPDATE notes SET pinned=?2 WHERE id=?1 AND deleted_at IS NULL",
                rusqlite::params![n.id, pinned],
            )
            .map_err(err)?;
        changed(&app)?;
    }
    Ok(())
}
#[tauri::command]
fn history_month(store: tauri::State<Store>, month: String) -> Result<Vec<history::Rate>> {
    history::month(&*connection(&store)?, &month).map_err(err)
}
#[tauri::command]
fn history_stats(store: tauri::State<Store>, month: Option<String>) -> Result<history::Stats> {
    history::stats(&*connection(&store)?, month.as_deref()).map_err(err)
}
#[tauri::command]
fn history_detail(store: tauri::State<Store>, date: String) -> Result<history::Detail> {
    history::detail(&*connection(&store)?, &date).map_err(err)
}
#[tauri::command]
fn business_date(store: tauri::State<Store>) -> Result<String> {
    day::current(&*connection(&store)?).map_err(err)
}
#[tauri::command]
fn history_toggle(
    app: tauri::AppHandle,
    store: tauri::State<Store>,
    date: String,
    id: String,
    done: bool,
) -> Result<()> {
    history::toggle(&mut *connection(&store)?, &date, &id, done).map_err(err)?;
    app.emit("items-changed", ()).map_err(err)
}
fn rebuild_menu(app: &tauri::AppHandle) -> Result<()> {
    let menu = Menu::new(app).map_err(err)?;
    menu.append(
        &MenuItem::with_id(app, "new", "新建便签 / New note", true, None::<&str>).map_err(err)?,
    )
    .map_err(err)?;
    // Release the database before native menu calls, which dispatch to the UI thread.
    let notes = db::active(&*connection(&app.state::<Store>())?).map_err(err)?;
    for n in notes {
        menu.append(
            &CheckMenuItem::with_id(
                app,
                format!("note-{}", n.id),
                &n.title,
                true,
                n.visible,
                None::<&str>,
            )
            .map_err(err)?,
        )
        .map_err(err)?;
    }
    for (id, label, enabled) in [
        ("management", "管理面板…", true),
        ("show", "显示全部 / Show all", true),
        ("hide", "隐藏全部 / Hide all", true),
        ("history", "历史… / History…", true),
        ("settings", "设置… / Settings…", true),
        ("quit", "退出 / Quit", true),
    ] {
        menu.append(&MenuItem::with_id(app, id, label, enabled, None::<&str>).map_err(err)?)
            .map_err(err)?;
    }
    if let Some(tray) = app.tray_by_id("desknodes") {
        tray.set_menu(Some(menu.clone())).map_err(err)?;
    }
    if let Some(control) = app.get_window("controls") {
        let sub = tauri::menu::Submenu::new(app, "DeskNodes", true).map_err(err)?;
        for item in menu.items().map_err(err)? {
            sub.append(&item).map_err(err)?;
        }
        control
            .set_menu(Menu::with_items(app, &[&sub]).map_err(err)?)
            .map_err(err)?;
    }
    Ok(())
}
// Entry point reserved for the global shortcut integration.
#[tauri::command]
fn create_note(app: tauri::AppHandle, store: tauri::State<Store>) -> Result<()> {
    let mut n = db::create(&*connection(&store)?).map_err(err)?;
    place(&app, &mut n, true)?;
    db::save(&*connection(&store)?, &n).map_err(err)?;
    spawn(&app, &n, true)?;
    changed(&app)
}
#[tauri::command]
async fn update_note(
    app: tauri::AppHandle,
    window: tauri::WebviewWindow,
    title: String,
    color: String,
    pinned: bool,
    collapsed: bool,
    reduced_motion: bool,
) -> Result<()> {
    tauri::async_runtime::spawn_blocking(move || {
        let prefs = app.state::<Preferences>();
        let _serial = prefs.actions.lock().map_err(err)?;
        let store = app.state::<Store>();
        if !db::COLORS.contains(&color.as_str()) {
            return Err("Unknown color".into());
        }
        let id = window
            .label()
            .strip_prefix("note-")
            .ok_or("Invalid window")?;
        let mut n = db::active(&*connection(&store)?)
            .map_err(err)?
            .into_iter()
            .find(|n| n.id == id)
            .ok_or("Note unavailable")?;
        n.title = title.trim().chars().take(200).collect();
        if n.title.is_empty() {
            n.title = "待办".into();
        }
        n.color = color;
        n.pinned = pinned;
        let resized = n.collapsed != collapsed;
        n.collapsed = collapsed;
        window.set_always_on_top(pinned).map_err(err)?;
        window
            .set_title(&format!("DeskNodes · {}", n.title))
            .map_err(err)?;
        connection(&store)?
            .execute(
                "UPDATE notes SET title=?2,color=?3,pinned=?4,collapsed=?5 WHERE id=?1 AND deleted_at IS NULL",
                rusqlite::params![n.id, n.title, n.color, n.pinned, n.collapsed],
            )
            .map_err(err)?;
        if resized {
            let geometry = app.state::<Geometry>();
            geometry.busy.lock().map_err(err)?.insert(window.label().into());
            let result = (|| -> Result<()> {
                window.set_min_size(Some(tauri::LogicalSize::new(220., 58.))).map_err(err)?;
                let start = if collapsed { n.height.max(160) } else { 58 };
                let end = if collapsed { 58 } else { n.height.max(160) };
                let steps = if reduced_motion { 1 } else { 12 };
                for step in 1..=steps {
                    let t = f64::from(step) / f64::from(steps);
                    let eased = 1. - (1. - t).powi(3);
                    let height = (f64::from(start) + f64::from(end - start) * eased).round();
                    window.set_size(tauri::LogicalSize::new(n.width.max(220) as f64, height)).map_err(err)?;
                    if !reduced_motion { std::thread::sleep(std::time::Duration::from_millis(16)); }
                }
                window.set_min_size(Some(tauri::LogicalSize::new(220., if collapsed {58.} else {160.}))).map_err(err)?;
                // Drain native configure events before releasing the guard. Only the final
                // geometry is stored; collapsed notes retain their expanded height.
                std::thread::sleep(std::time::Duration::from_millis(80));
                let scale = window.scale_factor().map_err(err)?;
                let pos = window.outer_position().map_err(err)?.to_logical::<i32>(scale);
                let size = window.inner_size().map_err(err)?.to_logical::<i32>(scale);
                n.x = pos.x; n.y = pos.y; n.width = size.width;
                if !collapsed { n.height = size.height; }
                db::save(&*connection(&store)?, &n).map_err(err)?;
                Ok(())
            })();
            geometry.busy.lock().map_err(err)?.remove(window.label());
            result?;
        }
        changed(&app)
    }).await.map_err(err)?
}

#[tauri::command]
fn hide_note(app: tauri::AppHandle, window: tauri::WebviewWindow) -> Result<()> {
    set_visible(&app, window.label(), false)
}
#[tauri::command]
fn delete_note(
    app: tauri::AppHandle,
    window: tauri::WebviewWindow,
    store: tauri::State<Store>,
) -> Result<()> {
    let id = window
        .label()
        .strip_prefix("note-")
        .ok_or("Invalid window")?;
    db::delete(&*connection(&store)?, id).map_err(err)?;
    window.destroy().map_err(err)?;
    changed(&app)
}
fn set_visible(app: &tauri::AppHandle, label: &str, visible: bool) -> Result<()> {
    let store = app.state::<Store>();
    let notes = db::active(&*connection(&store)?).map_err(err)?;
    if let Some(mut n) = notes
        .into_iter()
        .find(|n| format!("note-{}", n.id) == label)
    {
        n.visible = visible;
        connection(&store)?
            .execute(
                "UPDATE notes SET visible=?2 WHERE id=?1 AND deleted_at IS NULL",
                rusqlite::params![n.id, visible],
            )
            .map_err(err)?;
        if visible {
            spawn(app, &n, false)?;
        } else if let Some(w) = app.get_webview_window(label) {
            w.hide().map_err(err)?;
        }
    }
    changed(app)
}
fn action(app: &tauri::AppHandle, id: &str) -> Result<()> {
    match id {
        "history" | "settings" => open_management(app, id),
        "management" => open_management(app, "notes"),
        "new" => create_note(app.clone(), app.state()),
        "show" | "hide" => all_visibility(app, id == "hide"),
        "toggle" => {
            let hidden = app
                .state::<Preferences>()
                .hidden
                .lock()
                .map_err(err)?
                .0
                .is_some();
            all_visibility(app, !hidden)
        }
        "quit" => {
            app.exit(0);
            Ok(())
        }
        label if label.starts_with("note-") => {
            let notes = db::active(&*connection(&app.state::<Store>())?).map_err(err)?;
            if let Some(n) = notes.iter().find(|n| format!("note-{}", n.id) == label) {
                set_visible(app, label, !n.visible)?;
            }
            Ok(())
        }
        _ => Ok(()),
    }
}
#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(
            tauri_plugin_autostart::Builder::new()
                .app_name("DeskNodes")
                .build(),
        )
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_single_instance::init(|app, _, _| {
            if let Err(e) = open_management(app, "notes") {
                eprintln!("Management: {e}");
            }
        }))
        .invoke_handler(tauri::generate_handler![
            get_settings,
            update_setting,
            backup_data,
            open_data_dir,
            panel_note,
            history_month,
            history_stats,
            history_detail,
            history_toggle,
            business_date,
            list_notes,
            today_items,
            tomorrow_items,
            open_url,
            mutate_item,
            move_item,
            create_note,
            update_note,
            hide_note,
            delete_note,
            rollover_ready,
            recovery_notice
        ])
        .on_window_event(|window, event| {
            if !window.label().starts_with("note-") {
                return;
            }
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                if let Err(e) = set_visible(window.app_handle(), window.label(), false) {
                    eprintln!("{e}");
                }
            }
            if window.state::<Geometry>().busy.lock().map(|busy| busy.contains(window.label())).unwrap_or(true) { return; }
            if matches!(
                event,
                tauri::WindowEvent::Moved(_) | tauri::WindowEvent::Resized(_)
            ) {
                let store = window.state::<Store>();
                let result = (|| -> Result<()> {
                    let c = connection(&store)?;
                    if let Some(mut n) = db::active(&c)
                        .map_err(err)?
                        .into_iter()
                        .find(|n| format!("note-{}", n.id) == window.label())
                    {
                        let scale = window.scale_factor().map_err(err)?;
                        let p = window
                            .outer_position()
                            .map_err(err)?
                            .to_logical::<i32>(scale);
                        let s = window.inner_size().map_err(err)?.to_logical::<i32>(scale);
                        if n.x == p.x && n.y == p.y && n.width == s.width && (n.collapsed || n.height == s.height.max(160)) { return Ok(()); }
                        n.x = p.x;
                        n.y = p.y;
                        n.width = s.width;
                        if !n.collapsed { n.height = s.height.max(160); }
                        c.execute("UPDATE notes SET x=?2,y=?3,width=?4,height=?5 WHERE id=?1 AND deleted_at IS NULL",rusqlite::params![n.id,n.x,n.y,n.width,n.height]).map_err(err)?;
                        drop(c);
                        changed(window.app_handle())?;
                    }
                    Ok(())
                })();
                if let Err(e) = result {
                    eprintln!("Save geometry: {e}");
                }
            }
        })
        .setup(|app| {
            app.manage(Geometry::default());
            #[cfg(target_os = "macos")]
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);
            let override_dir = std::env::var_os("DESKNODES_DATA_DIR");
            let dir = if let Some(dir) = override_dir {
                std::path::PathBuf::from(dir)
            } else {
                let base = if cfg!(target_os = "windows") {
                    std::env::var_os("APPDATA")
                } else if cfg!(target_os = "linux") {
                    std::env::var_os("XDG_DATA_HOME")
                } else {
                    None
                };
                let dir = data_dir::product_dir(
                    std::env::consts::OS,
                    &app.path().home_dir()?,
                    base.map(Into::into),
                );
                data_dir::migrate(&app.path().app_data_dir()?, &dir)?;
                dir
            };
            std::fs::create_dir_all(&dir)?;
            eprintln!(
                "DeskNodes database: {}",
                dir.join("desknodes.sqlite3").display()
            );
            let path = dir.join("desknodes.sqlite3");
            let (mut c, recovered) =
                day::open_recover(&path).map_err(|e| std::io::Error::other(e.to_string()))?;
            if day::due(&c, &day::WallClock)? {
                day::backup(&path)?;
            }
            day::sync(&mut c, &day::WallClock)?;
            db::seed(&mut c)?;
            settings::initialize(&c).map_err(std::io::Error::other)?;
            app.manage(Store(std::sync::Mutex::new(c)));
            app.manage(Preferences {
                actions: Default::default(),
                hidden: Default::default(),
                status: Default::default(),
            });
            let values =
                settings::load(&*connection(&app.state::<Store>()).map_err(std::io::Error::other)?)
                    .map_err(std::io::Error::other)?;
            for (key, value) in &values {
                let result = if key.starts_with("shortcut_") {
                    register_binding(app.handle(), key, value)
                } else if key == "autostart" && std::env::var_os("DESKNODES_DATA_DIR").is_none() {
                    autostart::set(app.handle(), value == "1")
                } else {
                    Ok(())
                };
                if let Err(e) = result {
                    app.state::<Preferences>()
                        .status
                        .lock()
                        .unwrap()
                        .insert(format!("{key}_status"), e);
                }
            }
            let status = if std::env::var_os("DESKNODES_DATA_DIR").is_some() {
                "隔离数据模式：未修改系统自启".into()
            } else {
                match autostart::enabled(app.handle()) {
                    Ok(true) => "已启用".into(),
                    Ok(false) => "未启用".into(),
                    Err(e) => err(e),
                }
            };
            app.state::<Preferences>()
                .status
                .lock()
                .unwrap()
                .entry("autostart_status".into())
                .or_insert(status);
            app.manage(Rollover {
                path,
                waiting: std::sync::Mutex::new(None),
                recovered,
            });
            let display_handle = app.handle().clone();
            std::thread::spawn(move || {
                let mut previous = monitor_fingerprint(&display_handle).ok();
                loop {
                    std::thread::sleep(std::time::Duration::from_secs(3));
                    let result = (|| -> Result<()> {
                        let next = monitor_fingerprint(&display_handle)?;
                        if previous.as_ref() != Some(&next) && reclamp_visible(&display_handle)? {
                            previous = Some(next);
                        }
                        Ok(())
                    })();
                    if let Err(e) = result { eprintln!("Display change: {e}"); }
                }
            });
            let handle = app.handle().clone();
            std::thread::spawn(move || {
                loop {
                    std::thread::sleep(std::time::Duration::from_secs(5));
                    let result = (|| -> Result<()> {
                        let state = handle.state::<Rollover>();
                        let mut waiting = state.waiting.lock().map_err(err)?;
                        if let Some(labels) = waiting.as_mut() {
                            labels.retain(|label| handle.get_webview_window(label).is_some());
                            if labels.is_empty() {
                                finish_rollover(&handle)?;
                                *waiting = None;
                            } else {
                                handle.emit("rollover-prepare", ()).map_err(err)?;
                            }
                            return Ok(());
                        }
                        let store = handle.state::<Store>();
                        let c = connection(&store)?;
                        let due = day::target(&c, &day::WallClock).map_err(err)?
                            > day::current(&c).map_err(err)?;
                        drop(c);
                        if due {
                            let labels: HashSet<String> = handle
                                .webview_windows()
                                .keys()
                                .filter(|s| s.starts_with("note-"))
                                .cloned()
                                .collect();
                            if labels.is_empty() {
                                finish_rollover(&handle)?;
                            } else {
                                *waiting = Some(labels);
                                handle.emit("rollover-prepare", ()).map_err(err)?;
                            }
                        }
                        Ok(())
                    })();
                    if let Err(e) = result {
                        eprintln!("Rollover: {e}");
                    }
                }
            });
            let control = tauri::WindowBuilder::new(app, "controls")
                .title("DeskNodes controls")
                .inner_size(360., 50.)
                .position(160., 80.)
                .resizable(false)
                .build()?;
            let items = [
                MenuItem::with_id(app, "new", "新建便签 / New note", true, None::<&str>)?,
                MenuItem::with_id(app, "show", "显示全部 / Show all", true, None::<&str>)?,
                MenuItem::with_id(app, "hide", "隐藏全部 / Hide all", true, None::<&str>)?,
                MenuItem::with_id(app, "quit", "退出 / Quit", true, None::<&str>)?,
            ];
            let refs: Vec<&dyn tauri::menu::IsMenuItem<_>> = items
                .iter()
                .map(|i| i as &dyn tauri::menu::IsMenuItem<_>)
                .collect();
            let menu = Menu::with_items(app, &refs)?;
            let submenu = tauri::menu::Submenu::with_items(app, "DeskNodes", true, &refs)?;
            control.set_menu(Menu::with_items(app, &[&submenu])?)?;
            let icon = tauri::image::Image::from_bytes(include_bytes!("../icons/32x32.png"))?;
            if let Err(e) = TrayIconBuilder::with_id("desknodes")
                .tooltip("DeskNodes")
                .icon(icon)
                .menu(&menu)
                .build(app)
            {
                eprintln!("Tray unavailable: {e}; use native controls");
            }
            let store = app.state::<Store>();
            let notes = db::active(&*connection(&store).map_err(std::io::Error::other)?)?;
            for mut n in notes.into_iter().filter(|n| n.visible) {
                place(app.handle(), &mut n, false).map_err(std::io::Error::other)?;
                db::save(&*connection(&store).map_err(std::io::Error::other)?, &n)?;
                spawn(app.handle(), &n, false).map_err(std::io::Error::other)?;
            }
            rebuild_menu(app.handle()).map_err(std::io::Error::other)?;
            eprintln!("DeskNodes: persistent notes ready");
            Ok(())
        })
        .on_menu_event(|app, event| {
            dispatch_action(app, event.id().as_ref().to_owned());
        })
        .run(tauri::generate_context!())
        .expect("DeskNodes runtime failed");
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn clamp_work_area_shrink_is_stable() {
        let area = Rect { x: 0, y: 32, w: 1024, h: 700 };
        let result = clamp(Rect { x: 1800, y: 950, w: 400, h: 850 }, area);
        assert_eq!(result, Rect { x: 624, y: 32, w: 400, h: 700 });
        assert_eq!(clamp(result, area), result);
        let tiny = Rect { x: -100, y: 40, w: 180, h: 120 };
        assert_eq!(clamp(result, tiny), tiny);
    }
    #[test]
    fn clamp_removed_monitor() {
        let a = Rect {
            x: 0,
            y: 0,
            w: 1920,
            h: 1080,
        };
        assert_eq!(
            clamp(
                Rect {
                    x: 3000,
                    y: -500,
                    w: 280,
                    h: 360
                },
                a
            ),
            Rect {
                x: 1640,
                y: 0,
                w: 280,
                h: 360
            }
        );
    }
    #[test]
    fn clamp_negative_monitor_and_sizes() {
        let a = Rect {
            x: -1200,
            y: 0,
            w: 1200,
            h: 800,
        };
        assert_eq!(
            clamp(
                Rect {
                    x: -1500,
                    y: 900,
                    w: 700,
                    h: 1000
                },
                a
            ),
            Rect {
                x: -1200,
                y: 0,
                w: 600,
                h: 800
            }
        );
        assert_eq!(
            clamp(
                Rect {
                    x: -800,
                    y: 20,
                    w: 1,
                    h: 1
                },
                a
            ),
            Rect {
                x: -800,
                y: 20,
                w: 220,
                h: 160
            }
        );
    }
}
