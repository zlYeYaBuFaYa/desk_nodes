
CREATE TABLE notes (
  id          TEXT PRIMARY KEY,   -- UUID
  title       TEXT NOT NULL,
  color       TEXT NOT NULL,      -- 色名，如 mist_blue
  x INTEGER, y INTEGER, width INTEGER, height INTEGER,
  visible     INTEGER NOT NULL DEFAULT 1,
  pinned      INTEGER NOT NULL DEFAULT 0,
  collapsed   INTEGER NOT NULL DEFAULT 0,
  sort_order  INTEGER NOT NULL,
  created_at  TEXT NOT NULL,
  deleted_at  TEXT                -- 软删除；非空表示已删除，历史仍可查
);

CREATE TABLE items (
  id           TEXT PRIMARY KEY,
  note_id      TEXT NOT NULL REFERENCES notes(id),
  content      TEXT NOT NULL,
  day          TEXT NOT NULL,     -- 业务日 YYYY-MM-DD，可为明天
  done         INTEGER NOT NULL DEFAULT 0,
  done_at      TEXT,
  carried_from TEXT,              -- 顺延来源事项 id
  carry_days   INTEGER NOT NULL DEFAULT 0,
  sort_order   INTEGER NOT NULL,
  created_at   TEXT NOT NULL
);
CREATE INDEX idx_items_day ON items(day, note_id);

CREATE TABLE settings (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
