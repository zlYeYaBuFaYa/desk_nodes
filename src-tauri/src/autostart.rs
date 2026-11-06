//! The upstream Linux backend assumes ~/.config; honor XDG_CONFIG_HOME too.
#[cfg(target_os = "linux")]
use tauri::Manager;
#[cfg(not(target_os = "linux"))]
use tauri_plugin_autostart::ManagerExt;

#[cfg(target_os = "linux")]
fn desktop(app: &tauri::AppHandle) -> Result<std::path::PathBuf, String> {
    let config = std::env::var_os("XDG_CONFIG_HOME")
        .map(std::path::PathBuf::from)
        .filter(|p| p.is_absolute())
        .unwrap_or(
            app.path()
                .home_dir()
                .map_err(|e| e.to_string())?
                .join(".config"),
        );
    Ok(config.join("autostart/DeskNodes.desktop"))
}
pub fn set(app: &tauri::AppHandle, enabled: bool) -> Result<(), String> {
    #[cfg(not(target_os = "linux"))]
    {
        let manager = app.autolaunch();
        (if enabled {
            manager.enable()
        } else {
            manager.disable()
        })
        .map_err(|e| e.to_string())
    }
    #[cfg(target_os = "linux")]
    {
        let path = desktop(app)?;
        if enabled {
            // Use the plugin on its supported default path, then normalize the entry.
            if std::env::var_os("XDG_CONFIG_HOME").is_none() {
                use tauri_plugin_autostart::ManagerExt;
                app.autolaunch().enable().map_err(|e| e.to_string())?;
            }
            let executable = app
                .env()
                .appimage
                .map(std::path::PathBuf::from)
                .unwrap_or(std::env::current_exe().map_err(|e| e.to_string())?);
            let exec = executable
                .to_string_lossy()
                .replace('\\', "\\\\")
                .replace('"', "\\\"")
                .replace('`', "\\`")
                .replace('$', "\\$")
                .replace('%', "%%");
            std::fs::create_dir_all(path.parent().ok_or("Missing config directory")?)
                .map_err(|e| e.to_string())?;
            std::fs::write(path,format!("[Desktop Entry]\nType=Application\nVersion=1.0\nName=DeskNodes\nExec=\"{exec}\"\nTerminal=false\nStartupNotify=false\n")).map_err(|e|e.to_string())?;
        } else if path.exists() {
            std::fs::remove_file(path).map_err(|e| e.to_string())?;
        }
        Ok(())
    }
}
pub fn enabled(app: &tauri::AppHandle) -> Result<bool, String> {
    #[cfg(target_os = "linux")]
    {
        Ok(desktop(app)?.exists())
    }
    #[cfg(not(target_os = "linux"))]
    {
        app.autolaunch().is_enabled().map_err(|e| e.to_string())
    }
}
