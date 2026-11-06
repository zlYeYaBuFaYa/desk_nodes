//! Business dates depend on a supplied wall clock; persisted dates only advance.
use chrono::{NaiveDate, NaiveDateTime, Timelike};
use rusqlite::{Connection, OptionalExtension, params};
use std::path::Path;

pub trait Clock {
    fn now(&self) -> NaiveDateTime;
}
pub struct WallClock;
impl Clock for WallClock {
    fn now(&self) -> NaiveDateTime {
        std::env::var("DESKNODES_FAKE_NOW")
            .ok()
            .and_then(|s| {
                chrono::DateTime::parse_from_rfc3339(&s)
                    .ok()
                    .map(|d| d.naive_local())
                    .or_else(|| NaiveDateTime::parse_from_str(&s, "%Y-%m-%dT%H:%M:%S").ok())
            })
            .unwrap_or_else(|| chrono::Local::now().naive_local())
    }
}
pub fn business_day(now: NaiveDateTime, hour: u32) -> NaiveDate {
    if now.hour() < hour {
        now.date().pred_opt().unwrap()
    } else {
        now.date()
    }
}
pub fn setting(c: &Connection, key: &str) -> rusqlite::Result<Option<String>> {
    c.query_row("SELECT value FROM settings WHERE key=?1", [key], |r| {
        r.get(0)
    })
    .optional()
}
pub fn put(c: &Connection, key: &str, value: &str) -> rusqlite::Result<()> {
    c.execute("INSERT INTO settings(key,value) VALUES(?1,?2) ON CONFLICT(key) DO UPDATE SET value=excluded.value", params![key,value])?;
    Ok(())
}
pub fn target(c: &Connection, clock: &impl Clock) -> rusqlite::Result<String> {
    let h = setting(c, "rollover_hour")?
        .and_then(|s| s.parse::<u32>().ok())
        .filter(|h| *h <= 6)
        .unwrap_or(0);
    Ok(business_day(clock.now(), h).to_string())
}
pub fn current(c: &Connection) -> rusqlite::Result<String> {
    Ok(setting(c, "current_business_day")?.unwrap_or(target(c, &WallClock)?))
}
// V0.1 databases have dated items but no persisted business date yet.
fn previous(c: &Connection, to: &str) -> rusqlite::Result<Option<String>> {
    if let Some(day) = setting(c, "current_business_day")? {
        return Ok(Some(day));
    }
    c.query_row("SELECT max(i.day) FROM items i JOIN notes n ON n.id=i.note_id WHERE n.deleted_at IS NULL AND i.day<=?1", [to], |r| r.get(0))
}
pub fn due(c: &Connection, clock: &impl Clock) -> rusqlite::Result<bool> {
    let to = target(c, clock)?;
    Ok(previous(c, &to)?.is_some_and(|from| from < to))
}
pub fn sync(c: &mut Connection, clock: &impl Clock) -> rusqlite::Result<bool> {
    let to = target(c, clock)?;
    let from = previous(c, &to)?;
    let tx = c.transaction()?;
    tx.execute(
        "INSERT OR IGNORE INTO settings VALUES('rollover_hour','0'),('auto_carry','1')",
        [],
    )?;
    if let Some(from) = from {
        if to <= from {
            put(&tx, "current_business_day", &from)?;
            tx.commit()?;
            return Ok(false);
        }
        let distance = (NaiveDate::parse_from_str(&to, "%Y-%m-%d")
            .map_err(|_| rusqlite::Error::InvalidQuery)?
            - NaiveDate::parse_from_str(&from, "%Y-%m-%d")
                .map_err(|_| rusqlite::Error::InvalidQuery)?)
        .num_days();
        if setting(&tx, "auto_carry")?.as_deref() != Some("0") {
            let rows: Vec<(String,String,String,i64,i64)> = tx.prepare("SELECT i.id,i.note_id,i.content,i.sort_order,i.carry_days FROM items i JOIN notes n ON n.id=i.note_id WHERE i.day=?1 AND i.done=0 AND n.deleted_at IS NULL")?.query_map([&from], |r| Ok((r.get(0)?,r.get(1)?,r.get(2)?,r.get(3)?,r.get(4)?)))?.collect::<rusqlite::Result<_>>()?;
            for (id, note, content, order, days) in rows {
                tx.execute("INSERT INTO items(id,note_id,content,day,sort_order,created_at,carried_from,carry_days) VALUES(?1,?2,?3,?4,?5,?6,?7,?8)",params![uuid::Uuid::new_v4().to_string(),note,content,to,order,clock.now().to_string(),id,days+distance])?;
            }
        }
    } else {
        put(&tx, "current_business_day", &to)?;
        tx.commit()?;
        return Ok(false);
    }
    put(&tx, "current_business_day", &to)?;
    tx.commit()?;
    Ok(true)
}

// Each backup is a directory, so WAL sidecars are rotated with their database.
pub fn backup(path: &Path) -> std::io::Result<()> {
    let root = path.parent().unwrap().join("backups");
    std::fs::create_dir_all(&root)?;
    let dir = root.join(format!(
        "{}-{}",
        chrono::Utc::now().format("%Y%m%dT%H%M%S%9f"),
        uuid::Uuid::new_v4()
    ));
    let staging = dir.with_extension("pending");
    std::fs::create_dir(&staging)?;
    for suffix in ["", "-wal", "-shm"] {
        let name = format!("desknodes.sqlite3{suffix}");
        let source = path.with_file_name(&name);
        if source.exists() {
            std::fs::copy(source, staging.join(name))?;
        }
    }
    std::fs::rename(staging, &dir)?;
    let mut dirs = snapshots(&root)?;
    dirs.sort_by_key(|e| e.file_name());
    let excess = dirs.len().saturating_sub(7);
    for d in dirs.into_iter().take(excess) {
        std::fs::remove_dir_all(d.path())?;
    }
    Ok(())
}
fn snapshots(root: &Path) -> std::io::Result<Vec<std::fs::DirEntry>> {
    Ok(std::fs::read_dir(root)?
        .collect::<std::io::Result<Vec<_>>>()?
        .into_iter()
        .filter(|e| e.path().extension().is_none() && e.path().join("desknodes.sqlite3").is_file())
        .collect())
}
pub fn open_recover(path: &Path) -> Result<(Connection, bool), Box<dyn std::error::Error>> {
    match crate::db::open(path) {
        Ok(c) => Ok((c, false)),
        Err(original) => {
            if !matches!(original,rusqlite::Error::SqliteFailure(ref e,_) if matches!(e.code,rusqlite::ErrorCode::DatabaseCorrupt|rusqlite::ErrorCode::NotADatabase))
            {
                return Err(original.into());
            }
            let mut dirs = snapshots(&path.parent().unwrap().join("backups"))?;
            dirs.sort_by_key(|e| e.file_name());
            let latest = dirs.last().ok_or(original)?;
            // Preserve damaged files for inspection before installing the snapshot.
            for suffix in ["", "-wal", "-shm"] {
                let name = format!("desknodes.sqlite3{suffix}");
                let dest = path.with_file_name(&name);
                if dest.exists() {
                    std::fs::rename(
                        &dest,
                        path.with_file_name(format!("{name}.damaged-{}", uuid::Uuid::new_v4())),
                    )?;
                }
                let source = latest.path().join(name);
                if source.exists() {
                    std::fs::copy(source, dest)?;
                }
            }
            Ok((crate::db::open(path)?, true))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    struct Fixed(&'static str);
    impl Clock for Fixed {
        fn now(&self) -> NaiveDateTime {
            NaiveDateTime::parse_from_str(self.0, "%Y-%m-%dT%H:%M:%S").unwrap()
        }
    }
    fn db() -> Connection {
        crate::db::open(Path::new(":memory:")).unwrap()
    }
    fn setup() -> (Connection, String) {
        let mut c = db();
        sync(&mut c, &Fixed("2026-01-01T12:00:00")).unwrap();
        let n = crate::db::create(&c).unwrap();
        c.execute("INSERT INTO items(id,note_id,content,day,sort_order,created_at) VALUES('original',?1,'待办','2026-01-01',0,'now')",[&n.id]).unwrap();
        (c, n.id)
    }
    #[test]
    fn legacy_startup_infers_previous_date_and_carries_gap() {
        let (mut c, n) = setup();
        c.execute("DELETE FROM settings", []).unwrap();
        assert!(due(&c, &Fixed("2026-01-04T12:00:00")).unwrap());
        assert!(sync(&mut c, &Fixed("2026-01-04T12:00:00")).unwrap());
        assert_eq!(crate::db::today(&c, &n).unwrap()[0].carry_days, 3);
        assert_eq!(setting(&c, "rollover_hour").unwrap().as_deref(), Some("0"));
        assert_eq!(setting(&c, "auto_carry").unwrap().as_deref(), Some("1"));
        let mut empty = db();
        assert!(!due(&empty, &Fixed("2026-01-04T12:00:00")).unwrap());
        assert!(!sync(&mut empty, &Fixed("2026-01-04T12:00:00")).unwrap());
        assert_eq!(current(&empty).unwrap(), "2026-01-04");
    }
    #[test]
    fn boundaries() {
        for (now, h, expected) in [
            ("2026-01-01T23:59:00", 0, "2026-01-01"),
            ("2026-01-02T00:00:00", 0, "2026-01-02"),
            ("2026-01-02T05:59:00", 6, "2026-01-01"),
            ("2026-01-02T06:00:00", 6, "2026-01-02"),
        ] {
            assert_eq!(business_day(Fixed(now).now(), h).to_string(), expected);
        }
    }
    #[test]
    fn gap_and_accumulated_carry_are_single_and_idempotent() {
        let (mut c, n) = setup();
        assert!(sync(&mut c, &Fixed("2026-01-04T12:00:00")).unwrap());
        assert!(!sync(&mut c, &Fixed("2026-01-04T12:00:00")).unwrap());
        let copy = crate::db::today(&c, &n).unwrap().remove(0);
        assert_eq!(copy.carry_days, 3);
        assert_eq!(copy.carried_from.as_deref(), Some("original"));
        assert_ne!(copy.id, "original");
        assert_eq!(
            c.query_row("SELECT count(DISTINCT day) FROM items", [], |r| r
                .get::<_, i64>(0))
                .unwrap(),
            2
        );
        assert_eq!(
            c.query_row("SELECT done FROM items WHERE id='original'", [], |r| r
                .get::<_, i64>(0))
                .unwrap(),
            0
        );
        sync(&mut c, &Fixed("2026-01-06T12:00:00")).unwrap();
        assert_eq!(crate::db::today(&c, &n).unwrap()[0].carry_days, 5);
    }
    #[test]
    fn backward_clock_keeps_date_and_items() {
        let (mut c, n) = setup();
        assert!(!sync(&mut c, &Fixed("2025-12-30T12:00:00")).unwrap());
        assert_eq!(current(&c).unwrap(), "2026-01-01");
        assert_eq!(crate::db::today(&c, &n).unwrap().len(), 1);
    }
    #[test]
    fn disabled_and_inactive_and_completed_do_not_carry() {
        let (mut c, _) = setup();
        put(&c, "auto_carry", "0").unwrap();
        sync(&mut c, &Fixed("2026-01-04T12:00:00")).unwrap();
        assert_eq!(
            c.query_row("SELECT count(*) FROM items", [], |r| r.get::<_, i64>(0))
                .unwrap(),
            1
        );
        let (mut c, n) = setup();
        crate::db::delete(&c, &n).unwrap();
        sync(&mut c, &Fixed("2026-01-04T12:00:00")).unwrap();
        assert_eq!(
            c.query_row("SELECT count(*) FROM items", [], |r| r.get::<_, i64>(0))
                .unwrap(),
            1
        );
        let (mut c, _) = setup();
        c.execute("UPDATE items SET done=1", []).unwrap();
        sync(&mut c, &Fixed("2026-01-04T12:00:00")).unwrap();
        assert_eq!(
            c.query_row("SELECT count(*) FROM items", [], |r| r.get::<_, i64>(0))
                .unwrap(),
            1
        );
    }
    #[test]
    fn deleted_copy_preserves_history_without_resurrection() {
        let (mut c, n) = setup();
        sync(&mut c, &Fixed("2026-01-02T12:00:00")).unwrap();
        let copy = crate::db::today(&c, &n).unwrap().remove(0);
        crate::db::item_mutation(&mut c, &n, "delete", &copy, &[]).unwrap();
        sync(&mut c, &Fixed("2026-01-03T12:00:00")).unwrap();
        assert!(crate::db::today(&c, &n).unwrap().is_empty());
        assert_eq!(
            c.query_row(
                "SELECT count(*) FROM items WHERE id='original' AND done=0",
                [],
                |r| r.get::<_, i64>(0)
            )
            .unwrap(),
            1
        );
        let (mut c, n) = setup();
        let original = crate::db::today(&c, &n).unwrap().remove(0);
        crate::db::item_mutation(&mut c, &n, "delete", &original, &[]).unwrap();
        sync(&mut c, &Fixed("2026-01-03T12:00:00")).unwrap();
        assert_eq!(
            c.query_row("SELECT count(*) FROM items", [], |r| r.get::<_, i64>(0))
                .unwrap(),
            0
        );
    }
    #[test]
    fn rotation_keeps_seven_complete_snapshots() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("desknodes.sqlite3");
        std::fs::write(&path, b"snapshot").unwrap();
        std::fs::write(path.with_file_name("desknodes.sqlite3-wal"), b"wal").unwrap();
        for _ in 0..10 {
            backup(&path).unwrap();
        }
        let dirs: Vec<_> = std::fs::read_dir(dir.path().join("backups"))
            .unwrap()
            .collect();
        assert_eq!(dirs.len(), 7);
        for d in dirs {
            assert!(d.unwrap().path().join("desknodes.sqlite3-wal").exists());
        }
    }
    #[test]
    fn corrupt_database_restores_latest_snapshot() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("desknodes.sqlite3");
        {
            let c = crate::db::open(&path).unwrap();
            put(&c, "marker", "older").unwrap();
            c.execute_batch("PRAGMA wal_checkpoint(TRUNCATE)").unwrap();
            backup(&path).unwrap();
        }
        {
            let c = crate::db::open(&path).unwrap();
            put(&c, "marker", "latest").unwrap();
            // Latest value exists only in WAL when the snapshot is taken.
            backup(&path).unwrap();
        }
        std::fs::write(&path, b"deliberately corrupt database").unwrap();
        let (c, recovered) = open_recover(&path).unwrap();
        assert!(recovered);
        assert_eq!(setting(&c, "marker").unwrap().as_deref(), Some("latest"));
    }
}
