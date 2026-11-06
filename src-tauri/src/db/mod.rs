use rusqlite::{Connection, params};
use serde::{Deserialize, Serialize};
use std::{path::Path, sync::Mutex};

pub const COLORS: [&str; 8] = [
    "mist", "sage", "apricot", "lilac", "butter", "blush", "celadon", "stone",
];
pub struct Store(pub Mutex<Connection>);
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Note {
    pub id: String,
    pub title: String,
    pub color: String,
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
    pub visible: bool,
    pub pinned: bool,
    pub collapsed: bool,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Item {
    pub id: String,
    #[serde(default)]
    pub day: String,
    pub content: String,
    pub done: bool,
    pub sort_order: i64,
    #[serde(default)]
    pub carry_days: i64,
    #[serde(default)]
    pub carried_from: Option<String>,
}
pub fn migrate(c: &mut Connection) -> rusqlite::Result<()> {
    let version: i32 = c.pragma_query_value(None, "user_version", |r| r.get(0))?;
    if version == 0 {
        let tx = c.transaction()?;
        tx.execute_batch(include_str!("001.sql"))?;
        tx.pragma_update(None, "user_version", 1)?;
        tx.commit()?;
    }
    Ok(())
}
pub fn open(path: &Path) -> rusqlite::Result<Connection> {
    let mut c = Connection::open(path)?;
    c.pragma_update(None, "journal_mode", "WAL")?;
    c.pragma_update(None, "foreign_keys", "ON")?;
    c.pragma_update(None, "synchronous", "NORMAL")?;
    c.busy_timeout(std::time::Duration::from_secs(5))?;
    migrate(&mut c)?;
    let integrity: String = c.query_row("PRAGMA quick_check", [], |r| r.get(0))?;
    if integrity != "ok" {
        return Err(rusqlite::Error::SqliteFailure(
            rusqlite::ffi::Error::new(rusqlite::ffi::SQLITE_CORRUPT),
            Some(integrity),
        ));
    }
    Ok(c)
}
pub fn active(c: &Connection) -> rusqlite::Result<Vec<Note>> {
    c.prepare("SELECT id,title,color,coalesce(x,160),coalesce(y,180),coalesce(width,280),coalesce(height,360),visible,pinned,collapsed FROM notes WHERE deleted_at IS NULL ORDER BY sort_order")?
        .query_map([], |r| Ok(Note { id:r.get(0)?,title:r.get(1)?,color:r.get(2)?,x:r.get(3)?,y:r.get(4)?,width:r.get(5)?,height:r.get(6)?,visible:r.get(7)?,pinned:r.get(8)?,collapsed:r.get(9)? }))?.collect()
}
pub fn next_color(notes: &[Note], count: usize) -> &'static str {
    COLORS
        .iter()
        .copied()
        .find(|color| !notes.iter().any(|n| n.color == *color))
        .unwrap_or(COLORS[count % 8])
}
pub fn create(c: &Connection) -> rusqlite::Result<Note> {
    let count: i64 = c.query_row("SELECT count(*) FROM notes", [], |r| r.get(0))?;
    let n = Note {
        id: uuid::Uuid::new_v4().to_string(),
        title: "待办".into(),
        color: next_color(&active(c)?, count as usize).into(),
        x: 160,
        y: 180,
        width: 300,
        height: 360,
        visible: true,
        pinned: false,
        collapsed: false,
    };
    c.execute("INSERT INTO notes(id,title,color,x,y,width,height,sort_order,created_at) VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9)", params![n.id,n.title,n.color,n.x,n.y,n.width,n.height,count,chrono::Utc::now().to_rfc3339()])?;
    Ok(n)
}
pub fn save(c: &Connection, n: &Note) -> rusqlite::Result<()> {
    c.execute("UPDATE notes SET title=?2,color=?3,x=?4,y=?5,width=?6,height=?7,visible=?8,pinned=?9,collapsed=?10 WHERE id=?1 AND deleted_at IS NULL",params![n.id,n.title,n.color,n.x,n.y,n.width,n.height,n.visible,n.pinned,n.collapsed])?;
    Ok(())
}
pub fn delete(c: &Connection, id: &str) -> rusqlite::Result<()> {
    c.execute(
        "UPDATE notes SET deleted_at=?2,visible=0 WHERE id=?1",
        params![id, chrono::Utc::now().to_rfc3339()],
    )?;
    Ok(())
}
pub fn seed(c: &mut Connection) -> rusqlite::Result<()> {
    let count: i64 = c.query_row("SELECT count(*) FROM notes", [], |r| r.get(0))?;
    if count == 0 {
        let tx = c.transaction()?;
        let n = create(&tx)?;
        for (i, text) in [
            "在下方写下今天的第一件事",
            "轻点圆圈，记下完成的小事",
            "让不再需要的事项轻轻离开",
        ]
        .iter()
        .enumerate()
        {
            tx.execute("INSERT INTO items(id,note_id,content,day,sort_order,created_at) VALUES(?1,?2,?3,?4,?5,?6)",params![uuid::Uuid::new_v4().to_string(),n.id,text,crate::day::current(&tx)?,i as i64,chrono::Utc::now().to_rfc3339()])?;
        }
        tx.commit()?;
    }
    Ok(())
}
pub fn today(c: &Connection, id: &str) -> rusqlite::Result<Vec<Item>> {
    items_on(c, id, &crate::day::current(c)?)
}
pub fn items_on(c: &Connection, id: &str, day: &str) -> rusqlite::Result<Vec<Item>> {
    c.prepare("SELECT id,content,done,sort_order,carry_days,carried_from,day FROM items WHERE note_id=?1 AND day=?2 ORDER BY sort_order,created_at,id")?
        .query_map(
            params![id, day],
            |r| {
                Ok(Item {
                    day: r.get(6)?,
                    id: r.get(0)?,
            content: r.get(1)?,
                    done: r.get(2)?,
                    sort_order: r.get(3)?,
                    carry_days: r.get(4)?,
                    carried_from: r.get(5)?,
                })
            },
        )?
        .collect()
}
pub fn item_mutation(
    c: &mut Connection,
    note: &str,
    op: &str,
    item: &Item,
    order: &[String],
) -> rusqlite::Result<()> {
    let current = crate::day::current(c)?;
    let tomorrow = crate::day::tomorrow(c)?;
    let day = if op == "add_tomorrow" || item.day == tomorrow {
        tomorrow
    } else {
        current
    };
    let tx = c.transaction()?;
    let next: i64 = tx.query_row(
        "SELECT coalesce(max(sort_order),-1)+1 FROM items WHERE note_id=?1 AND day=?2 AND done=0",
        params![note, day],
        |r| r.get(0),
    )?;
    let content: String = item.content.trim().chars().take(200).collect();
    match op {
        "add" | "add_tomorrow" | "restore" if !content.is_empty() => {
            tx.execute("INSERT INTO items(id,note_id,content,day,done,done_at,sort_order,created_at,carry_days,carried_from) SELECT ?1,?2,?3,?4,?5,?6,?7,?8,?9,?10 WHERE EXISTS(SELECT 1 FROM notes WHERE id=?2 AND deleted_at IS NULL)", params![item.id,note,content,day,item.done,item.done.then(||chrono::Utc::now().to_rfc3339()),if op!="restore" {next}else{item.sort_order},chrono::Utc::now().to_rfc3339(),item.carry_days,item.carried_from])?;
        }
        "edit" if !content.is_empty() => {
            tx.execute(
                "UPDATE items SET content=?3 WHERE id=?1 AND note_id=?2 AND day=?4",
                params![item.id, note, content, day],
            )?;
        }
        "toggle" => {
            tx.execute("UPDATE items SET done=?3,done_at=?4,sort_order=CASE WHEN ?3=0 THEN ?5 ELSE sort_order END WHERE id=?1 AND note_id=?2 AND day=?6",params![item.id,note,item.done,item.done.then(||chrono::Utc::now().to_rfc3339()),next,day])?;
        }
        "delete" => {
            tx.execute(
                "DELETE FROM items WHERE id=?1 AND note_id=?2 AND day=?3",
                params![item.id, note, day],
            )?;
        }
        "reorder" => {
            let mut current: Vec<String> = today(&tx, note)?
                .into_iter()
                .filter(|i| !i.done)
                .map(|i| i.id)
                .collect();
            let mut requested = order.to_vec();
            current.sort();
            requested.sort();
            if current != requested {
                return Err(rusqlite::Error::InvalidQuery);
            }
            for (i, id) in order.iter().enumerate() {
                tx.execute("UPDATE items SET sort_order=?3 WHERE id=?1 AND note_id=?2 AND day=?4 AND done=0",params![id,note,i as i64,day])?;
            }
        }
        "edit" | "add" | "add_tomorrow" | "restore" => {}
        _ => return Err(rusqlite::Error::InvalidQuery),
    }
    tx.commit()
}
/// Move atomically without recreating the item or changing its day/completion metadata.
pub fn move_item(c: &mut Connection, source: &str, target: &str, id: &str) -> rusqlite::Result<()> {
    if source == target {
        return Err(rusqlite::Error::InvalidQuery);
    }
    let today = crate::day::current(c)?;
    let tomorrow = crate::day::tomorrow(c)?;
    let tx = c.transaction()?;
    let valid: bool = tx.query_row(
        "SELECT count(*)=2 FROM notes WHERE id IN (?1,?2) AND deleted_at IS NULL",
        params![source, target],
        |r| r.get(0),
    )?;
    if !valid {
        return Err(rusqlite::Error::InvalidQuery);
    }
    let changed = tx.execute("UPDATE items SET note_id=?3,sort_order=(SELECT coalesce(max(sort_order),-1)+1 FROM items AS destination WHERE destination.note_id=?3 AND destination.day=items.day) WHERE id=?1 AND note_id=?2 AND day IN (?4,?5)", params![id,source,target,today,tomorrow])?;
    if changed != 1 {
        return Err(rusqlite::Error::QueryReturnedNoRows);
    }
    tx.commit()
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn migration_on_disk() {
        let dir = tempfile::tempdir().unwrap();
        let p = dir.path().join("test.db");
        let mut c = open(&p).unwrap();
        migrate(&mut c).unwrap();
        assert_eq!(
            c.query_row("PRAGMA user_version", [], |r| r.get::<_, i32>(0))
                .unwrap(),
            1
        );
        assert_eq!(
            c.query_row("PRAGMA journal_mode", [], |r| r.get::<_, String>(0))
                .unwrap(),
            "wal"
        );
    }
    #[test]
    fn crud_and_soft_delete() {
        let mut c = open(Path::new(":memory:")).unwrap();
        seed(&mut c).unwrap();
        seed(&mut c).unwrap();
        let mut n = active(&c).unwrap().remove(0);
        assert_eq!(today(&c, &n.id).unwrap().len(), 3);
        n.title = "生活".into();
        n.visible = false;
        n.pinned = true;
        n.collapsed = true;
        save(&c, &n).unwrap();
        let got = active(&c).unwrap().remove(0);
        assert_eq!(got.title, "生活");
        assert!(!got.visible);
        assert!(got.pinned);
        assert!(got.collapsed);
        delete(&c, &n.id).unwrap();
        assert!(active(&c).unwrap().is_empty());
        assert_eq!(today(&c, &n.id).unwrap().len(), 3);
    }
    #[test]
    fn colors_cycle() {
        let c = open(Path::new(":memory:")).unwrap();
        for i in 0..17 {
            assert_eq!(create(&c).unwrap().color, COLORS[i % 8]);
        }
    }
}

#[cfg(test)]
mod item_tests {
    use super::*;
    #[test]
    fn item_lifecycle_and_order() {
        let mut c = open(Path::new(":memory:")).unwrap();
        let n = create(&c).unwrap();
        let mut a = Item {
            id: "a".into(),
            day: String::new(),
            content: "  first  ".into(),
            done: false,
            sort_order: 0,
            carry_days: 0,
            carried_from: None,
        };
        let b = Item {
            id: "b".into(),
            day: String::new(),
            content: "second".into(),
            done: false,
            sort_order: 1,
            carry_days: 0,
            carried_from: None,
        };
        item_mutation(&mut c, &n.id, "add", &a, &[]).unwrap();
        item_mutation(&mut c, &n.id, "add", &b, &[]).unwrap();
        assert_eq!(today(&c, &n.id).unwrap()[0].content, "first");
        a.content = "edited".into();
        item_mutation(&mut c, &n.id, "edit", &a, &[]).unwrap();
        assert_eq!(today(&c, &n.id).unwrap()[0].content, "edited");
        a.done = true;
        item_mutation(&mut c, &n.id, "toggle", &a, &[]).unwrap();
        assert!(today(&c, &n.id).unwrap()[0].done);
        a.done = false;
        item_mutation(&mut c, &n.id, "toggle", &a, &[]).unwrap();
        assert_eq!(today(&c, &n.id).unwrap()[1].id, "a");
        item_mutation(&mut c, &n.id, "reorder", &a, &["a".into(), "b".into()]).unwrap();
        let got = today(&c, &n.id).unwrap();
        assert_eq!(got[0].id, "a");
        assert_eq!(got[1].sort_order, 1);
        assert!(item_mutation(&mut c, &n.id, "reorder", &a, &["a".into(), "a".into()]).is_err());
        item_mutation(&mut c, &n.id, "delete", &a, &[]).unwrap();
        assert_eq!(today(&c, &n.id).unwrap().len(), 1);
        item_mutation(&mut c, &n.id, "restore", &got[0], &[]).unwrap();
        assert_eq!(today(&c, &n.id).unwrap()[0].id, "a");
    }
    #[test]
    fn validates_content_and_today_scope() {
        let mut c = open(Path::new(":memory:")).unwrap();
        let n = create(&c).unwrap();
        let other = create(&c).unwrap();
        let mut a = Item {
            id: "a".into(),
            day: String::new(),
            content: " ".into(),
            done: false,
            sort_order: 0,
            carry_days: 0,
            carried_from: None,
        };
        item_mutation(&mut c, &n.id, "add", &a, &[]).unwrap();
        assert!(today(&c, &n.id).unwrap().is_empty());
        a.content = "字".repeat(201);
        item_mutation(&mut c, &n.id, "add", &a, &[]).unwrap();
        assert_eq!(today(&c, &n.id).unwrap()[0].content.chars().count(), 200);
        item_mutation(&mut c, &other.id, "delete", &a, &[]).unwrap();
        assert_eq!(today(&c, &n.id).unwrap().len(), 1);
        c.execute("UPDATE items SET day='2000-01-01'", []).unwrap();
        item_mutation(&mut c, &n.id, "delete", &a, &[]).unwrap();
        assert_eq!(
            c.query_row("SELECT count(*) FROM items", [], |r| r.get::<_, i64>(0))
                .unwrap(),
            1
        );
    }
}

#[cfg(test)]
mod move_tests {
    use super::*;
    #[test]
    fn move_today_and_tomorrow_preserves_identity_and_metadata() {
        for (tomorrow, done) in [(false, false), (false, true), (true, false)] {
            let mut c = open(Path::new(":memory:")).unwrap();
            let source = create(&c).unwrap();
            let target = create(&c).unwrap();
            let day = if tomorrow {
                crate::day::tomorrow(&c)
            } else {
                crate::day::current(&c)
            }
            .unwrap();
            for (id, note, order) in [("moving", &source.id, 2), ("existing", &target.id, 9)] {
                c.execute("INSERT INTO items(id,note_id,content,day,done,done_at,sort_order,created_at,carry_days,carried_from) VALUES(?1,?2,'keep me',?3,1,'completed',?4,'created',3,'origin')",params![id,note,day,order]).unwrap();
            }
            c.execute("UPDATE items SET done=?1 WHERE id='moving'", [done])
                .unwrap();
            move_item(&mut c, &source.id, &target.id, "moving").unwrap();
            assert!(items_on(&c, &source.id, &day).unwrap().is_empty());
            let items = items_on(&c, &target.id, &day).unwrap();
            let moved = &items[1];
            assert_eq!(moved.id, "moving");
            assert_eq!(moved.day, day);
            assert_eq!(moved.done, done);
            assert_eq!(moved.content, "keep me");
            assert_eq!(moved.sort_order, 10);
            assert_eq!(moved.carry_days, 3);
            assert_eq!(moved.carried_from.as_deref(), Some("origin"));
            let metadata: (String, String) = c
                .query_row(
                    "SELECT done_at,created_at FROM items WHERE id='moving'",
                    [],
                    |r| Ok((r.get(0)?, r.get(1)?)),
                )
                .unwrap();
            assert_eq!(metadata, ("completed".into(), "created".into()));
        }
    }
    #[test]
    fn rejects_unavailable_targets_and_wrong_source_without_losing_item() {
        let mut c = open(Path::new(":memory:")).unwrap();
        seed(&mut c).unwrap();
        let source = active(&c).unwrap().remove(0);
        let target = create(&c).unwrap();
        let item = today(&c, &source.id).unwrap().remove(0);
        assert!(move_item(&mut c, &source.id, "missing", &item.id).is_err());
        assert!(move_item(&mut c, &source.id, &source.id, &item.id).is_err());
        assert!(move_item(&mut c, &target.id, &source.id, &item.id).is_err());
        delete(&c, &target.id).unwrap();
        assert!(move_item(&mut c, &source.id, &target.id, &item.id).is_err());
        assert_eq!(today(&c, &source.id).unwrap().len(), 3);
    }
}
