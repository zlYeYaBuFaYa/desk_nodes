mod data_dir;
mod day;
mod db;
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
fn spawn(app: &tauri::AppHandle, n: &Note, fresh: bool) -> Result<()> {
    if let Some(w) = app.get_webview_window(&format!("note-{}", n.id)) {
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
    .inner_size(n.width as f64, n.height as f64)
    .position(n.x as f64, n.y as f64)
    .min_inner_size(220., 160.)
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
fn rebuild_menu(app: &tauri::AppHandle) -> Result<()> {
    let menu = Menu::new(app).map_err(err)?;
    menu.append(
        &MenuItem::with_id(app, "new", "新建便签 / New note", true, None::<&str>).map_err(err)?,
    )
    .map_err(err)?;
    for n in db::active(&*connection(&app.state::<Store>())?).map_err(err)? {
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
        ("show", "显示全部 / Show all", true),
        ("hide", "隐藏全部 / Hide all", true),
        ("history", "历史… / History…", false),
        ("settings", "设置… / Settings…", false),
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
fn update_note(
    app: tauri::AppHandle,
    window: tauri::WebviewWindow,
    store: tauri::State<Store>,
    title: String,
    color: String,
    pinned: bool,
) -> Result<()> {
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
    window.set_always_on_top(pinned).map_err(err)?;
    window
        .set_title(&format!("DeskNodes · {}", n.title))
        .map_err(err)?;
    db::save(&*connection(&store)?, &n).map_err(err)?;
    changed(&app)
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
        db::save(&*connection(&store)?, &n).map_err(err)?;
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
        "new" => create_note(app.clone(), app.state()),
        "show" | "hide" => {
            let notes = db::active(&*connection(&app.state::<Store>())?).map_err(err)?;
            for n in notes {
                set_visible(app, &format!("note-{}", n.id), id == "show")?;
            }
            Ok(())
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
        .invoke_handler(tauri::generate_handler![
            list_notes,
            today_items,
            mutate_item,
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
                        n.x = p.x;
                        n.y = p.y;
                        n.width = s.width;
                        n.height = s.height;
                        db::save(&c, &n).map_err(err)?;
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
            app.manage(Store(std::sync::Mutex::new(c)));
            app.manage(Rollover {
                path,
                waiting: std::sync::Mutex::new(None),
                recovered,
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
            if let Err(e) = action(app, event.id().as_ref()) {
                eprintln!("Action failed: {e}");
            }
        })
        .run(tauri::generate_context!())
        .expect("DeskNodes runtime failed");
}
#[cfg(test)]
mod tests {
    use super::*;
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
