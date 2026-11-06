//! History queries and edits share the persisted business date with rollover.
use crate::{day, db::Item};
use chrono::{Datelike, Duration, NaiveDate};
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
    c.prepare("SELECT day,sum(done),count(*) FROM items WHERE substr(day,1,7)=?1 AND day<=?2 GROUP BY day ORDER BY day")?.query_map(params![month, day::current(c)?], |r| { let done = r.get::<_, i64>(1)? as usize; let total = r.get::<_, i64>(2)? as usize; Ok(Rate {day:r.get(0)?,done,total,bucket:bucket(done,total)}) })?.collect()
}
/// Rates are fractions in 0..=1. Month follows the calendar selection;
/// week and streak always follow the persisted current business date.
#[derive(Debug, Serialize)]
pub struct Stats {
    pub week_done: usize,
    pub week_total: usize,
    pub week_rate: f64,
    pub month_done: usize,
    pub month_total: usize,
    pub month_rate: f64,
    pub streak: usize,
}
fn fraction(done: usize, total: usize) -> f64 {
    if total == 0 {
        0.0
    } else {
        done as f64 / total as f64
    }
}
/// Pure calculation over daily aggregates. Today extends a streak only when
/// achieved; otherwise yesterday is the anchor, allowing today to stay in progress.
/// Every empty or incomplete day encountered from that anchor breaks the streak.
pub fn calculate_stats(rates: &[Rate], current: NaiveDate, month: NaiveDate) -> Stats {
    let monday = current - Duration::days(current.weekday().num_days_from_monday().into());
    let mut days = std::collections::BTreeMap::<NaiveDate, (usize, usize)>::new();
    let (mut wd, mut wt, mut md, mut mt) = (0, 0, 0, 0);
    for rate in rates {
        let Ok(date) = NaiveDate::parse_from_str(&rate.day, "%Y-%m-%d") else {
            continue;
        };
        if date > current {
            continue;
        }
        let entry = days.entry(date).or_default();
        entry.0 += rate.done;
        entry.1 += rate.total;
        if date >= monday {
            wd += rate.done;
            wt += rate.total;
        }
        if date.year() == month.year() && date.month() == month.month() {
            md += rate.done;
            mt += rate.total;
        }
    }
    let achieved = |date: &NaiveDate| days.get(date).is_some_and(|&(d, t)| t > 0 && d == t);
    let mut cursor = if achieved(&current) {
        Some(current)
    } else {
        current.pred_opt()
    };
    let mut streak = 0;
    while let Some(date) = cursor {
        if !achieved(&date) {
            break;
        }
        streak += 1;
        cursor = date.pred_opt();
    }
    Stats {
        week_done: wd,
        week_total: wt,
        week_rate: fraction(wd, wt),
        month_done: md,
        month_total: mt,
        month_rate: fraction(md, mt),
        streak,
    }
}
pub fn stats(c: &Connection, selected_month: Option<&str>) -> rusqlite::Result<Stats> {
    let current = NaiveDate::parse_from_str(&day::current(c)?, "%Y-%m-%d")
        .map_err(|_| rusqlite::Error::InvalidQuery)?;
    let month = match selected_month {
        Some(m) => NaiveDate::parse_from_str(&format!("{m}-01"), "%Y-%m-%d")
            .map_err(|_| rusqlite::Error::InvalidQuery)?,
        None => current,
    };
    let rates = c
        .prepare("SELECT day,sum(done),count(*) FROM items WHERE day<=?1 GROUP BY day")?
        .query_map([current.to_string()], |r| {
            Ok(Rate {
                day: r.get(0)?,
                done: r.get::<_, i64>(1)? as usize,
                total: r.get::<_, i64>(2)? as usize,
                bucket: None,
            })
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(calculate_stats(&rates, current, month))
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
                day: date.to_string(),
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

#[cfg(test)]
mod stats_tests {
    use super::*;
    fn date(s: &str) -> NaiveDate {
        NaiveDate::parse_from_str(s, "%Y-%m-%d").unwrap()
    }
    fn rates(rows: &[(&str, usize, usize)]) -> Vec<Rate> {
        rows.iter()
            .map(|&(day, done, total)| Rate {
                day: day.into(),
                done,
                total,
                bucket: bucket(done, total),
            })
            .collect()
    }
    #[test]
    fn weighted_week_crosses_year_and_excludes_future() {
        let rows = rates(&[
            ("2025-12-28", 1, 1),
            ("2025-12-29", 1, 3),
            ("2025-12-31", 2, 2),
            ("2026-01-01", 1, 1),
            ("2026-01-02", 9, 9),
        ]);
        let s = calculate_stats(&rows, date("2026-01-01"), date("2025-12-01"));
        assert_eq!(
            (
                s.week_done,
                s.week_total,
                s.month_done,
                s.month_total,
                s.streak
            ),
            (4, 6, 4, 6, 2)
        );
        assert_eq!(s.week_rate, 4.0 / 6.0);
        assert_eq!(s.month_rate, 4.0 / 6.0);
    }
    #[test]
    fn streak_today_in_progress_and_blank_days() {
        let mut rows = rates(&[
            ("2024-02-28", 1, 1),
            ("2024-02-29", 2, 2),
            ("2024-03-01", 1, 2),
        ]);
        assert_eq!(
            calculate_stats(&rows, date("2024-03-01"), date("2024-03-01")).streak,
            2
        );
        rows[2].done = 2;
        assert_eq!(
            calculate_stats(&rows, date("2024-03-01"), date("2024-03-01")).streak,
            3
        );
        assert_eq!(
            calculate_stats(&rows, date("2024-03-02"), date("2024-03-01")).streak,
            3
        );
        assert_eq!(
            calculate_stats(&rows, date("2024-03-03"), date("2024-03-01")).streak,
            0
        );
        rows.remove(1);
        assert_eq!(
            calculate_stats(&rows, date("2024-03-01"), date("2024-03-01")).streak,
            1
        );
    }
    #[test]
    fn empty_and_sunday_monday_boundaries() {
        let rows = rates(&[("2026-11-01", 1, 1), ("2026-11-02", 0, 1)]);
        let sunday = calculate_stats(&rows, date("2026-11-01"), date("2026-12-01"));
        assert_eq!(
            (sunday.week_rate, sunday.month_rate, sunday.streak),
            (1.0, 0.0, 1)
        );
        let monday = calculate_stats(&rows, date("2026-11-02"), date("2026-11-01"));
        assert_eq!(
            (monday.week_done, monday.week_total, monday.streak),
            (0, 1, 1)
        );
        let empty = calculate_stats(&[], date("2026-11-02"), date("2026-11-01"));
        assert_eq!(
            (empty.week_rate, empty.month_rate, empty.streak),
            (0.0, 0.0, 0)
        );
    }
    #[test]
    fn command_query_defaults_deleted_notes_and_validation() {
        let c = crate::db::open(std::path::Path::new(":memory:")).unwrap();
        day::put(&c, "current_business_day", "2026-11-06").unwrap();
        let n = crate::db::create(&c).unwrap();
        for (id, date, done) in [
            ("past", "2026-11-05", 1),
            ("today", "2026-11-06", 0),
            ("tomorrow", "2026-11-07", 1),
        ] {
            c.execute("INSERT INTO items(id,note_id,content,day,done,sort_order,created_at) VALUES(?1,?2,'x',?3,?4,0,'now')",params![id,n.id,date,done]).unwrap();
        }
        crate::db::delete(&c, &n.id).unwrap();
        let s = stats(&c, None).unwrap();
        assert_eq!(
            (
                s.week_done,
                s.week_total,
                s.month_done,
                s.month_total,
                s.streak
            ),
            (1, 2, 1, 2, 1)
        );
        assert_eq!(s.month_rate, 0.5);
        assert_eq!(stats(&c, Some("2026-12")).unwrap().month_total, 0);
        assert!(stats(&c, Some("invalid")).is_err());
    }
}
