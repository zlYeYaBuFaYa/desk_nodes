"""Linux-only production migration smoke test; isolates XDG_DATA_HOME."""
import os, pathlib, sqlite3, subprocess, tempfile, time
root=pathlib.Path(tempfile.mkdtemp(prefix='desknodes-migration-'))
old=root/'com.desknodes.app';old.mkdir()
source=sqlite3.connect(old/'desknodes.sqlite3')
source.execute('pragma journal_mode=WAL')
source.executescript(pathlib.Path('src-tauri/src/db/001.sql').read_text())
source.execute('pragma user_version=1')
source.execute("insert into notes(id,title,color,visible,sort_order,created_at) values('migration','Migrated','sage',0,0,'2026-11-05')")
source.commit()  # Leave the WAL present to verify recovery of its committed data.
env={**os.environ,'DISPLAY':':3','XDG_DATA_HOME':str(root)}
env.pop('DESKNODES_DATA_DIR',None)
log=open('/workspace/desknotes/logs/f3-migration-app.log','w')
app=subprocess.Popen([os.getenv('DESKNODES_BINARY','/workspace/desknotes/target/release/desk-nodes')],env=env,stdout=log,stderr=log)
try:
    time.sleep(3)
    destination=root/'DeskNodes'/'desknodes.sqlite3'
    assert destination.is_file()
    with sqlite3.connect(destination) as c:
        assert c.execute('select title from notes').fetchone()[0]=='Migrated'
    assert (old/'desknodes.sqlite3').is_file()
    print('PASS: default product path, old Tauri path detection, committed WAL data, old backup retained')
finally:
    app.terminate();app.wait();source.close();log.close()
