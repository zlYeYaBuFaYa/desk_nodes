use std::path::{Path, PathBuf};

pub fn product_dir(platform: &str, home: &Path, base: Option<PathBuf>) -> PathBuf {
    base.unwrap_or_else(|| match platform {
        "macos" => home.join("Library/Application Support"),
        "windows" => home.join("AppData/Roaming"),
        _ => home.join(".local/share"),
    })
    .join("DeskNodes")
}

// Publish the database last, so an interrupted copy can safely be retried.
// Never replace an existing destination database. The old copy remains a backup.
pub fn migrate(old: &Path, new: &Path) -> std::io::Result<bool> {
    std::fs::create_dir_all(new)?;
    let name = "desknodes.sqlite3";
    if new.join(name).exists() || !old.join(name).is_file() || old == new {
        return Ok(false);
    }
    for suffix in ["-wal", "-shm", ""] {
        let file = format!("{name}{suffix}");
        let source = old.join(&file);
        if source.exists() {
            let staged = new.join(format!("{file}.migrating"));
            std::fs::copy(source, &staged)?;
            std::fs::File::open(&staged)?.sync_all()?;
            std::fs::rename(staged, new.join(file))?;
        }
    }
    Ok(true)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn paths() {
        assert_eq!(
            product_dir("linux", Path::new("/home/a"), None),
            PathBuf::from("/home/a/.local/share/DeskNodes")
        );
        assert_eq!(
            product_dir("macos", Path::new("/Users/a"), None),
            PathBuf::from("/Users/a/Library/Application Support/DeskNodes")
        );
        assert_eq!(
            product_dir("windows", Path::new("home"), None),
            PathBuf::from("home/AppData/Roaming/DeskNodes")
        );
        assert_eq!(
            product_dir("linux", Path::new("/ignored"), Some("/xdg".into())),
            PathBuf::from("/xdg/DeskNodes")
        );
    }
    #[test]
    fn migration_once_with_companions() {
        let root = tempfile::tempdir().unwrap();
        let old = root.path().join("old");
        let new = root.path().join("new");
        std::fs::create_dir(&old).unwrap();
        assert!(!migrate(&old, &new).unwrap());
        for suffix in ["", "-wal", "-shm"] {
            std::fs::write(
                old.join(format!("desknodes.sqlite3{suffix}")),
                suffix.as_bytes(),
            )
            .unwrap();
        }
        assert!(migrate(&old, &new).unwrap());
        assert_eq!(
            std::fs::read(new.join("desknodes.sqlite3-wal")).unwrap(),
            b"-wal"
        );
        std::fs::write(old.join("desknodes.sqlite3"), b"changed").unwrap();
        assert!(!migrate(&old, &new).unwrap());
        assert_eq!(std::fs::read(new.join("desknodes.sqlite3")).unwrap(), b"");
    }
}
