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
}
#[derive(Serialize)]
pub struct Item {
    pub id: String,
    pub content: String,
    pub done: bool,
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
    Ok(c)
}
pub fn active(c: &Connection) -> rusqlite::Result<Vec<Note>> {
    c.prepare("SELECT id,title,color,coalesce(x,160),coalesce(y,180),coalesce(width,280),coalesce(height,360),visible,pinned FROM notes WHERE deleted_at IS NULL ORDER BY sort_order")?
        .query_map([], |r| Ok(Note { id:r.get(0)?,title:r.get(1)?,color:r.get(2)?,x:r.get(3)?,y:r.get(4)?,width:r.get(5)?,height:r.get(6)?,visible:r.get(7)?,pinned:r.get(8)? }))?.collect()
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
    };
    c.execute("INSERT INTO notes(id,title,color,x,y,width,height,sort_order,created_at) VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9)", params![n.id,n.title,n.color,n.x,n.y,n.width,n.height,count,chrono::Utc::now().to_rfc3339()])?;
    Ok(n)
}
pub fn save(c: &Connection, n: &Note) -> rusqlite::Result<()> {
    c.execute("UPDATE notes SET title=?2,color=?3,x=?4,y=?5,width=?6,height=?7,visible=?8,pinned=?9 WHERE id=?1 AND deleted_at IS NULL",params![n.id,n.title,n.color,n.x,n.y,n.width,n.height,n.visible,n.pinned])?;
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
            tx.execute("INSERT INTO items(id,note_id,content,day,sort_order,created_at) VALUES(?1,?2,?3,?4,?5,?6)",params![uuid::Uuid::new_v4().to_string(),n.id,text,chrono::Local::now().format("%Y-%m-%d").to_string(),i as i64,chrono::Utc::now().to_rfc3339()])?;
        }
        tx.commit()?;
    }
    Ok(())
}
pub fn today(c: &Connection, id: &str) -> rusqlite::Result<Vec<Item>> {
    c.prepare("SELECT id,content,done FROM items WHERE note_id=?1 AND day=?2 ORDER BY sort_order")?
        .query_map(
            params![id, chrono::Local::now().format("%Y-%m-%d").to_string()],
            |r| {
                Ok(Item {
                    id: r.get(0)?,
                    content: r.get(1)?,
                    done: r.get(2)?,
                })
            },
        )?
        .collect()
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
        save(&c, &n).unwrap();
        let got = active(&c).unwrap().remove(0);
        assert_eq!(got.title, "生活");
        assert!(!got.visible);
        assert!(got.pinned);
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
