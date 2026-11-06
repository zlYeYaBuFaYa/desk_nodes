use crate::{day, db};
use rusqlite::Connection;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashSet};

pub fn defaults() -> BTreeMap<String, String> {
    let modifier = if cfg!(target_os = "macos") {
        "Super"
    } else {
        "Control"
    };
    [
        ("autostart", "1".into()),
        ("rollover_hour", "0".into()),
        ("auto_carry", "1".into()),
        ("appearance", "system".into()),
        ("note_opacity", "100".into()),
        ("font_size", "medium".into()),
        ("hide_all_hint_shown", "0".into()),
        ("shortcut_toggle_all", format!("{modifier}+Shift+Space")),
        ("shortcut_new_note", format!("{modifier}+Shift+N")),
        ("shortcut_open_panel", format!("{modifier}+Shift+D")),
    ]
    .into_iter()
    .map(|(k, v)| (k.into(), v))
    .collect()
}
pub fn validate(key: &str, value: &str) -> Result<(), String> {
    let valid = match key {
        "autostart" | "auto_carry" | "hide_all_hint_shown" => ["0", "1"].contains(&value),
        "rollover_hour" => value.parse::<u8>().is_ok_and(|v| v <= 6),
        "note_opacity" => value.parse::<u8>().is_ok_and(|v| (70..=100).contains(&v)),
        "appearance" => ["system", "light", "dark"].contains(&value),
        "font_size" => ["small", "medium", "large"].contains(&value),
        k if k.starts_with("shortcut_") && defaults().contains_key(k) => value
            .parse::<tauri_plugin_global_shortcut::Shortcut>()
            .is_ok(),
        _ => false,
    };
    if valid {
        Ok(())
    } else {
        Err(format!("无效的设置：{key}"))
    }
}
pub fn initialize(c: &Connection) -> Result<(), String> {
    for (key, value) in defaults() {
        c.execute(
            "INSERT OR IGNORE INTO settings(key,value) VALUES(?1,?2)",
            rusqlite::params![key, value],
        )
        .map_err(|e| e.to_string())?;
    }
    Ok(())
}
pub fn load(c: &Connection) -> Result<BTreeMap<String, String>, String> {
    let mut values = defaults();
    for (k, v) in values.iter_mut() {
        if let Some(saved) = day::setting(c, k).map_err(|e| e.to_string())? {
            *v = saved;
        }
    }
    Ok(values)
}
pub fn save(c: &Connection, key: &str, value: &str) -> Result<(), String> {
    validate(key, value)?;
    day::put(c, key, value).map_err(|e| e.to_string())
}
#[derive(Default)]
pub struct Hidden(pub Option<HashSet<String>>);
impl Hidden {
    pub fn hide(&mut self, notes: &[db::Note]) {
        if self.0.is_none() {
            self.0 = Some(
                notes
                    .iter()
                    .filter(|n| n.visible)
                    .map(|n| n.id.clone())
                    .collect(),
            );
        }
    }
    pub fn restore(&mut self) -> HashSet<String> {
        self.0.take().unwrap_or_default()
    }
}
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Backup {
    version: u32,
    tables: BTreeMap<String, Vec<Vec<serde_json::Value>>>,
}
const TABLES: [(&str, usize); 3] = [("notes", 13), ("items", 10), ("settings", 2)];
pub fn export(c: &Connection) -> Result<String, String> {
    let mut tables = BTreeMap::new();
    for (name, _) in TABLES {
        let mut q = c
            .prepare(&format!("SELECT * FROM {name}"))
            .map_err(|e| e.to_string())?;
        let count = q.column_count();
        let rows = q
            .query_map([], |r| {
                (0..count)
                    .map(|i| {
                        Ok(match r.get_ref(i)? {
                            rusqlite::types::ValueRef::Null => serde_json::Value::Null,
                            rusqlite::types::ValueRef::Integer(v) => v.into(),
                            rusqlite::types::ValueRef::Text(v) => {
                                String::from_utf8_lossy(v).to_string().into()
                            }
                            _ => return Err(rusqlite::Error::InvalidQuery),
                        })
                    })
                    .collect::<rusqlite::Result<Vec<_>>>()
            })
            .map_err(|e| e.to_string())?
            .collect::<rusqlite::Result<Vec<_>>>()
            .map_err(|e| e.to_string())?;
        tables.insert(name.into(), rows);
    }
    serde_json::to_string_pretty(&Backup { version: 1, tables }).map_err(|e| e.to_string())
}
pub fn import(c: &mut Connection, json: &str) -> Result<(), String> {
    let backup: Backup = serde_json::from_str(json).map_err(|e| e.to_string())?;
    if backup.version != 1 || backup.tables.len() != 3 {
        return Err("不支持的备份版本或结构".into());
    }
    let tx = c.transaction().map_err(|e| e.to_string())?;
    tx.execute_batch("DELETE FROM items; DELETE FROM notes; DELETE FROM settings;")
        .map_err(|e| e.to_string())?;
    for (name, count) in TABLES {
        let rows = backup.tables.get(name).ok_or("备份缺少数据表")?;
        for row in rows {
            if row.len() != count {
                return Err("备份字段不完整".into());
            }
            // SQLite affinity is permissive: check JSON types before inserting.
            let (texts, integers, nullable): (&[usize], &[usize], &[usize]) = match name {
                "notes" => (
                    &[0, 1, 2, 11, 12],
                    &[3, 4, 5, 6, 7, 8, 9, 10],
                    &[3, 4, 5, 6, 12],
                ),
                "items" => (&[0, 1, 2, 3, 5, 6, 9], &[4, 7, 8], &[5, 6]),
                _ => (&[0, 1], &[], &[]),
            };
            for &i in texts {
                if !(row[i].is_string() || (row[i].is_null() && nullable.contains(&i))) {
                    return Err("备份文本字段类型错误".into());
                }
            }
            for &i in integers {
                if !(row[i].as_i64().is_some() || (row[i].is_null() && nullable.contains(&i))) {
                    return Err("备份数字字段类型错误".into());
                }
            }
            let values = row
                .iter()
                .map(|v| match v {
                    serde_json::Value::Null => Ok(rusqlite::types::Value::Null),
                    serde_json::Value::String(s) => Ok(s.clone().into()),
                    serde_json::Value::Number(n) => n.as_i64().map(Into::into).ok_or("无效数字"),
                    _ => Err("无效字段"),
                })
                .collect::<Result<Vec<_>, _>>()?;
            if name == "settings" {
                let k = row[0].as_str().ok_or("无效设置")?;
                let v = row[1].as_str().ok_or("无效设置")?;
                if defaults().contains_key(k) {
                    validate(k, v)?;
                } else if k != "current_business_day" {
                    return Err("未知设置".into());
                } else if chrono::NaiveDate::parse_from_str(v, "%Y-%m-%d").is_err() {
                    return Err("无效日期".into());
                }
            }
            let marks = vec!["?"; count].join(",");
            tx.execute(
                &format!("INSERT INTO {name} VALUES({marks})"),
                rusqlite::params_from_iter(values),
            )
            .map_err(|e| e.to_string())?;
        }
    }
    for n in db::active(&tx).map_err(|e| e.to_string())? {
        if !db::COLORS.contains(&n.color.as_str())
            || n.title.is_empty()
            || !(220..=600).contains(&n.width)
            || !(160..=900).contains(&n.height)
        {
            return Err("无效便签".into());
        }
    }
    let invalid_notes:i64=tx.query_row("SELECT count(*) FROM notes WHERE id='' OR length(title)>200 OR trim(title)='' OR color NOT IN ('mist','sage','apricot','lilac','butter','blush','celadon','stone') OR visible NOT IN (0,1) OR pinned NOT IN(0,1) OR collapsed NOT IN(0,1)",[],|r|r.get(0)).map_err(|e|e.to_string())?;
    if invalid_notes != 0 {
        return Err("无效便签字段".into());
    }
    let prefs = load(&tx)?;
    let mut bindings = HashSet::new();
    for (key, value) in prefs {
        if key.starts_with("shortcut_")
            && !bindings.insert(
                value
                    .parse::<tauri_plugin_global_shortcut::Shortcut>()
                    .map_err(|e| e.to_string())?,
            )
        {
            return Err("备份中有重复快捷键".into());
        }
    }
    let bad:i64=tx.query_row("SELECT count(*) FROM items WHERE id='' OR length(content)>200 OR trim(content)='' OR date(day) IS NULL OR done NOT IN(0,1) OR carry_days<0",[],|r|r.get(0)).map_err(|e|e.to_string())?;
    if bad != 0 {
        return Err("无效事项".into());
    }
    tx.commit().map_err(|e| e.to_string())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn validation_roundtrip() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("settings.sqlite3");
        let c = db::open(&path).unwrap();
        for (k, v) in defaults() {
            save(&c, &k, &v).unwrap();
            assert_eq!(load(&c).unwrap()[&k], v);
        }
        save(&c, "appearance", "dark").unwrap();
        save(&c, "note_opacity", "75").unwrap();
        drop(c);
        let c = db::open(&path).unwrap();
        assert_eq!(load(&c).unwrap()["appearance"], "dark");
        assert_eq!(load(&c).unwrap()["note_opacity"], "75");
        for (k, v) in [
            ("note_opacity", "101"),
            ("note_opacity", "69"),
            ("font_size", "huge"),
            ("rollover_hour", "7"),
            ("appearance", "blue"),
        ] {
            assert!(save(&c, k, v).is_err());
        }
    }
    #[test]
    fn backup_roundtrip_and_rejection() {
        let mut c = db::open(std::path::Path::new(":memory:")).unwrap();
        db::seed(&mut c).unwrap();
        let json = export(&c).unwrap();
        import(&mut c, &json).unwrap();
        assert_eq!(export(&c).unwrap(), json);
        for bad in [
            "{}",
            &json.replace("\"version\": 1", "\"version\": 9"),
            &json.replace("mist", "invalid"),
        ] {
            assert!(import(&mut c, bad).is_err());
            assert_eq!(export(&c).unwrap(), json);
        }
    }
    #[test]
    fn malformed_backup_is_atomic() {
        let mut c = db::open(std::path::Path::new(":memory:")).unwrap();
        db::seed(&mut c).unwrap();
        initialize(&c).unwrap();
        let json = export(&c).unwrap();
        for (table, column, value) in [
            ("items", 1, serde_json::json!("missing-note")),
            ("items", 3, serde_json::json!("not-a-date")),
            ("notes", 7, serde_json::json!(2)),
            ("notes", 1, serde_json::json!(42)),
        ] {
            let mut backup: Backup = serde_json::from_str(&json).unwrap();
            backup.tables.get_mut(table).unwrap()[0][column] = value;
            assert!(import(&mut c, &serde_json::to_string(&backup).unwrap()).is_err());
            assert_eq!(export(&c).unwrap(), json);
        }
    }
    #[test]
    fn backup_preserves_deleted_notes_and_history() {
        let mut c = db::open(std::path::Path::new(":memory:")).unwrap();
        db::seed(&mut c).unwrap();
        let n = db::active(&c).unwrap().remove(0);
        db::delete(&c, &n.id).unwrap();
        let json = export(&c).unwrap();
        let mut other = db::open(std::path::Path::new(":memory:")).unwrap();
        import(&mut other, &json).unwrap();
        assert!(db::active(&other).unwrap().is_empty());
        assert_eq!(export(&other).unwrap(), json);
    }
    #[test]
    fn restore_only_visible() {
        let c = db::open(std::path::Path::new(":memory:")).unwrap();
        let a = db::create(&c).unwrap();
        let mut b = db::create(&c).unwrap();
        b.visible = false;
        let mut h = Hidden::default();
        h.hide(&[a.clone(), b]);
        h.hide(&[]);
        assert_eq!(h.restore(), HashSet::from([a.id]));
        assert!(h.restore().is_empty());
    }
}
