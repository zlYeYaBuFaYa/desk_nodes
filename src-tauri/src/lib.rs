use std::sync::atomic::{AtomicUsize, Ordering};
use tauri::{
    Manager, WebviewUrl, WebviewWindowBuilder,
    menu::{Menu, MenuItem},
    tray::TrayIconBuilder,
};

static NEXT_NOTE: AtomicUsize = AtomicUsize::new(0);
const COLORS: [&str; 8] = [
    "mist", "sage", "apricot", "lilac", "butter", "blush", "celadon", "stone",
];

fn note_url(id: usize) -> String {
    let theme = match std::env::var("DESKNODES_THEME").as_deref() {
        Ok("dark") => "dark",
        Ok("light") => "light",
        _ => "system",
    };
    format!(
        "index.html?id={id}&color={}&theme={theme}",
        COLORS[id % COLORS.len()]
    )
}

fn new_note(app: &tauri::AppHandle) -> tauri::Result<()> {
    let id = NEXT_NOTE.fetch_add(1, Ordering::Relaxed);
    let data_dir = app.path().data_dir()?.join("DeskNodes");
    WebviewWindowBuilder::new(
        app,
        format!("note-{id}"),
        WebviewUrl::App(note_url(id).into()),
    )
    .data_directory(data_dir)
    .title(format!("DeskNodes · Note {}", id + 1))
    .inner_size(280.0, 360.0)
    .min_inner_size(220.0, 160.0)
    .max_inner_size(600.0, 900.0)
    .position(
        160.0 + (id % 5) as f64 * 300.0,
        180.0 + (id % 3) as f64 * 100.0,
    )
    .decorations(false)
    .transparent(true)
    .shadow(false)
    .skip_taskbar(true)
    .visible_on_all_workspaces(true)
    .build()?;
    Ok(())
}

fn action(app: &tauri::AppHandle, id: &str) -> tauri::Result<()> {
    eprintln!("DeskNodes action: {id}");
    match id {
        "new" => new_note(app)?,
        "show" | "hide" => {
            for (label, window) in app.webview_windows() {
                if label.starts_with("note-") {
                    if id == "show" {
                        window.show()?;
                    } else {
                        window.hide()?;
                    }
                }
            }
        }
        "quit" => app.exit(0),
        _ => (),
    }
    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                if window.label().starts_with("note-")
                    && let Err(error) = window.hide()
                {
                    eprintln!("Hide note: {error}");
                }
            }
        })
        .setup(|app| {
            #[cfg(target_os = "macos")]
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);

            // Native, non-WebView utility window survives hiding every note, even
            // if the tray host accepts an icon but never displays it.
            let control = tauri::WindowBuilder::new(app, "controls")
                .title("DeskNodes controls")
                .inner_size(360.0, 50.0)
                .position(160.0, 80.0)
                .resizable(false)
                .build()?;
            let items = [
                MenuItem::with_id(app, "new", "New note", true, None::<&str>)?,
                MenuItem::with_id(app, "show", "Show all", true, None::<&str>)?,
                MenuItem::with_id(app, "hide", "Hide all", true, None::<&str>)?,
                MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?,
            ];
            let menu = Menu::with_items(app, &[&items[0], &items[1], &items[2], &items[3]])?;
            let submenu = tauri::menu::Submenu::with_items(
                app,
                "DeskNodes",
                true,
                &[&items[0], &items[1], &items[2], &items[3]],
            )?;
            control.set_menu(Menu::with_items(app, &[&submenu])?)?;
            let icon = tauri::image::Image::from_bytes(include_bytes!("../icons/32x32.png"))?;
            match TrayIconBuilder::with_id("desknodes")
                .tooltip("DeskNodes")
                .icon(icon)
                .menu(&menu)
                .build(app)
            {
                Ok(_) => eprintln!(
                    "DeskNodes: tray registered; native controls remain available as fallback"
                ),
                Err(error) => {
                    eprintln!("DeskNodes: tray unavailable ({error}); use native controls")
                }
            }
            for _ in 0..5 {
                new_note(app.handle())?;
            }
            eprintln!("DeskNodes: five note windows ready (in-memory prototype)");
            Ok(())
        })
        .on_menu_event(|app, event| {
            if let Err(error) = action(app, event.id().as_ref()) {
                eprintln!("DeskNodes action failed: {error}");
            }
        })
        .run(tauri::generate_context!())
        .expect("DeskNodes runtime failed");
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn note_routes_are_distinct_and_cycle_all_eight_colors() {
        let urls: std::collections::HashSet<_> = (0..5).map(note_url).collect();
        assert_eq!(urls.len(), 5);
        for id in 0..16 {
            assert!(note_url(id).contains(&format!("id={id}&color={}", COLORS[id % 8])));
        }
    }
}
