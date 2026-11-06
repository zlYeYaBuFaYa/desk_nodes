//! History queries and edits share the persisted business date with rollover.
use crate::{day, db::Item};
use chrono::NaiveDate;
use rusqlite::{Connection, params};
use serde::Serialize;
#[derive(Debug, Serialize)]
pub struct Rate {
    pub day: String,
    pub done: usize,
    pub total: usize,
    pub bucket: Option<u8>,
}
pub fn bucket(done: usize, total: usize) -> Option<u8> {
    if total == 0 {
        None
    } else if done == 0 {
        Some(0)
    } else if done >= total {
        Some(3)
    } else if done * 2 >= total {
        Some(2)
    } else {
        Some(1)
    }
}
#[derive(Debug, Serialize)]
pub struct Group {
    pub id: String,
    pub title: String,
    pub color: String,
    pub deleted: bool,
    pub items: Vec<Item>,
}
#[derive(Serialize)]
pub struct Detail {
    pub groups: Vec<Group>,
    pub done: usize,
    pub total: usize,
    pub editable: bool,
}
pub fn editable(date: &str, current: &str) -> bool {
    NaiveDate::parse_from_str(current, "%Y-%m-%d")
        .ok()
        .and_then(|d| d.pred_opt())
        .is_some_and(|d| d.to_string() == date)
}
pub fn month(c: &Connection, month: &str) -> rusqlite::Result<Vec<Rate>> {
    NaiveDate::parse_from_str(&format!("{month}-01"), "%Y-%m-%d")
        .map_err(|_| rusqlite::Error::InvalidQuery)?;
    c.prepare("SELECT day,sum(done),count(*) FROM items WHERE substr(day,1,7)=?1 GROUP BY day ORDER BY day")?.query_map([month], |r| { let done = r.get::<_, i64>(1)? as usize; let total = r.get::<_, i64>(2)? as usize; Ok(Rate {day:r.get(0)?,done,total,bucket:bucket(done,total)}) })?.collect()
}
pub fn detail(c: &Connection, date: &str) -> rusqlite::Result<Detail> {
    NaiveDate::parse_from_str(date, "%Y-%m-%d").map_err(|_| rusqlite::Error::InvalidQuery)?;
    let mut groups: Vec<Group> = Vec::new();
    let mut stmt = c.prepare("SELECT n.id,n.title,n.color,n.deleted_at IS NOT NULL,i.id,i.content,i.done,i.sort_order,i.carry_days,i.carried_from FROM items i JOIN notes n ON n.id=i.note_id WHERE i.day=?1 ORDER BY n.sort_order,n.id,i.sort_order,i.created_at,i.id")?;
    let rows = stmt.query_map([date], |r| {
        Ok((
            r.get::<_, String>(0)?,
            r.get::<_, String>(1)?,
            r.get::<_, String>(2)?,
            r.get::<_, bool>(3)?,
            Item {
                id: r.get(4)?,
                content: r.get(5)?,
                done: r.get(6)?,
                sort_order: r.get(7)?,
                carry_days: r.get(8)?,
                carried_from: r.get(9)?,
            },
        ))
    })?;
    let (mut done, mut total) = (0, 0);
    for row in rows {
        let (id, title, color, deleted, item) = row?;
        done += usize::from(item.done);
        total += 1;
        if groups.last().is_none_or(|g| g.id != id) {
            groups.push(Group {
                id,
                title,
                color,
                deleted,
                items: vec![],
            });
        }
        groups.last_mut().unwrap().items.push(item);
    }
    Ok(Detail {
        groups,
        done,
        total,
        editable: editable(date, &day::current(c)?),
    })
}
pub fn toggle(c: &mut Connection, date: &str, id: &str, done: bool) -> rusqlite::Result<()> {
    let current = day::current(c)?;
    if !editable(date, &current) {
        return Err(rusqlite::Error::InvalidQuery);
    }
    let tx = c.transaction()?;
    let changed = tx.execute("UPDATE items SET done=?3,done_at=CASE WHEN ?3 THEN ?4 ELSE NULL END WHERE id=?1 AND day=?2",params![id,date,done,chrono::Utc::now().to_rfc3339()])?;
    if changed != 1 {
        return Err(rusqlite::Error::QueryReturnedNoRows);
    }
    if done {
        tx.execute(
            "DELETE FROM items WHERE carried_from=?1 AND day=?2",
            params![id, current],
        )?;
    }
    tx.commit()
}
#[cfg(test)]
mod tests {
    use super::*;
    struct Fixed;
    impl day::Clock for Fixed {
        fn now(&self) -> chrono::NaiveDateTime {
            NaiveDate::from_ymd_opt(2026, 11, 5)
                .unwrap()
                .and_hms_opt(2, 0, 0)
                .unwrap()
        }
    }
    #[test]
    fn buckets_and_boundaries() {
        assert_eq!(
            (
                bucket(0, 0),
                bucket(0, 3),
                bucket(1, 3),
                bucket(1, 2),
                bucket(2, 2)
            ),
            (None, Some(0), Some(1), Some(2), Some(3))
        );
        assert!(editable("2025-12-31", "2026-01-01"));
        assert!(editable("2024-02-29", "2024-03-01"));
        assert!(!editable("bad", "bad"));
        assert!(!editable("2026-11-05", "2026-11-05"));
    }
    #[test]
    fn history_transaction_and_groups() {
        let dir = tempfile::tempdir().unwrap();
        let mut c = crate::db::open(&dir.path().join("history.db")).unwrap();
        day::put(&c, "rollover_hour", "4").unwrap();
        day::sync(&mut c, &Fixed).unwrap();
        assert_eq!(day::current(&c).unwrap(), "2026-11-04");
        let a = crate::db::create(&c).unwrap();
        let b = crate::db::create(&c).unwrap();
        for (id, n, date, source) in [
            ("old", &a.id, "2026-11-03", None),
            ("copy", &a.id, "2026-11-04", Some("old")),
            ("older-copy", &a.id, "2026-11-02", Some("old")),
            ("other", &b.id, "2026-11-03", None),
        ] {
            c.execute("INSERT INTO items(id,note_id,content,day,sort_order,created_at,carried_from) VALUES(?1,?2,'任务',?3,0,'now',?4)",params![id,n,date,source]).unwrap();
        }
        crate::db::delete(&c, &b.id).unwrap();
        let d = detail(&c, "2026-11-03").unwrap();
        assert_eq!(d.groups.len(), 2);
        assert!(d.groups[1].deleted);
        assert_eq!(d.total, 2);
        assert!(d.editable);
        assert!(toggle(&mut c, "2026-11-02", "older-copy", true).is_err());
        assert!(toggle(&mut c, "2026-11-03", "missing", true).is_err());
        toggle(&mut c, "2026-11-03", "old", true).unwrap();
        assert!(crate::db::today(&c, &a.id).unwrap().is_empty());
        assert_eq!(detail(&c, "2026-11-02").unwrap().total, 1);
        toggle(&mut c, "2026-11-03", "old", false).unwrap();
        assert_eq!(detail(&c, "2026-11-03").unwrap().done, 0);
        assert_eq!(month(&c, "2026-11").unwrap().len(), 2);
        assert!(month(&c, "bad").is_err());
        assert!(detail(&c, "bad").is_err());
    }
}

#[cfg(test)]
mod more_tests {
    use super::*;
    #[test]
    fn monthly_rates_empty_days_and_deleted_notes() {
        let dir = tempfile::tempdir().unwrap();
        let c = crate::db::open(&dir.path().join("rates.db")).unwrap();
        day::put(&c, "current_business_day", "2026-03-01").unwrap();
        let n = crate::db::create(&c).unwrap();
        for (date, count, done) in [
            ("2026-02-01", 3, 0),
            ("2026-02-02", 3, 1),
            ("2026-02-03", 3, 2),
            ("2026-02-04", 3, 3),
            ("2026-03-01", 1, 1),
        ] {
            for i in 0..count {
                c.execute("INSERT INTO items(id,note_id,content,day,done,sort_order,created_at) VALUES(?1,?2,'x',?3,?4,?5,'now')",params![format!("{date}-{i}"),n.id,date,i<done,i]).unwrap();
            }
        }
        crate::db::delete(&c, &n.id).unwrap();
        let rates = month(&c, "2026-02").unwrap();
        assert_eq!(
            rates.iter().map(|r| r.bucket).collect::<Vec<_>>(),
            vec![Some(0), Some(1), Some(2), Some(3)]
        );
        assert!(month(&c, "2025-02").unwrap().is_empty());
        let empty = detail(&c, "2026-02-28").unwrap();
        assert_eq!(empty.total, 0);
        assert!(empty.editable);
        assert!(!detail(&c, "2026-02-04").unwrap().editable);
        assert!(detail(&c, "2026-02-04").unwrap().groups[0].deleted);
    }
    #[test]
    fn undone_keeps_copy_and_repeated_done_is_safe() {
        let dir = tempfile::tempdir().unwrap();
        let mut c = crate::db::open(&dir.path().join("toggle.db")).unwrap();
        day::put(&c, "current_business_day", "2026-01-01").unwrap();
        let n = crate::db::create(&c).unwrap();
        for (id, date, source) in [
            ("a", "2025-12-31", None),
            ("b", "2026-01-01", Some("a")),
            ("c", "2026-01-01", None),
        ] {
            c.execute("INSERT INTO items(id,note_id,content,day,carried_from,sort_order,created_at) VALUES(?1,?2,'x',?3,?4,0,'now')",params![id,n.id,date,source]).unwrap();
        }
        toggle(&mut c, "2025-12-31", "a", false).unwrap();
        assert_eq!(crate::db::today(&c, &n.id).unwrap().len(), 2);
        toggle(&mut c, "2025-12-31", "a", true).unwrap();
        toggle(&mut c, "2025-12-31", "a", true).unwrap();
        assert_eq!(crate::db::today(&c, &n.id).unwrap()[0].id, "c");
        assert!(toggle(&mut c, "2026-01-01", "c", true).is_err());
    }
}
