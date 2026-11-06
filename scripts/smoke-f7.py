"""Native F7 fixture, interaction checks, and screenshots (isolated data)."""
import os, sqlite3, subprocess as sp, time, pathlib, signal
os.environ.update(DISPLAY=':3', DESKNODES_DATA_DIR='/tmp/desknodes-f7-shots', DESKNODES_FAKE_NOW='2026-11-06T12:00:00', XDG_CONFIG_HOME='/tmp/desknodes-f7-config', GDK_BACKEND='x11')
root=pathlib.Path(os.environ['DESKNODES_DATA_DIR']);root.mkdir(exist_ok=True)
launcher=root/'bin';launcher.mkdir(exist_ok=True)
opened=root/'opened-url';opened.unlink(missing_ok=True)
(launcher/'xdg-open').write_text('#!/bin/sh\nprintf \'%s\\n\' "$1" > /tmp/desknodes-f7-shots/opened-url\n')
(launcher/'xdg-open').chmod(0o755)
os.environ['PATH']=str(launcher)+':'+os.environ['PATH']
binary='/workspace/desknotes/target/debug/desk-nodes'
log=open('/workspace/desknotes/logs/f7-runtime.log','w')
def start():
 p=sp.Popen([binary],env=os.environ,stdout=log,stderr=log,start_new_session=True);time.sleep(3);return p
def stop(p):
 os.killpg(p.pid,signal.SIGTERM);p.wait(timeout=10);time.sleep(.6)
p=start();stop(p)
db=root/'desknodes.sqlite3'
with sqlite3.connect(db) as c:
 c.execute('delete from items');c.execute('delete from notes')
 c.execute("insert or replace into settings values('appearance','light')")
 c.execute("insert or replace into settings values('current_business_day','2026-11-06')")
 for i,(title,color,collapsed) in enumerate([('今天，慢慢来','mist',0),('生活的小事','sage',1),('留一点空白','apricot',1)]):
  c.execute('insert into notes(id,title,color,x,y,width,height,visible,pinned,collapsed,sort_order,created_at) values(?,?,?,?,?,380,440,1,0,?,?,?)',(f'f7-{i}',title,color,350+i*420,290,collapsed,i,'now'))
 for i,(text,day,done) in enumerate([('整理本周的灵感与笔记','2026-11-06',0),('看看 https://example.com 的新灵感','2026-11-06',0),('让桌面恢复一点留白','2026-11-06',1),('带一本书，去喜欢的咖啡馆','2026-11-07',0),('把新的想法写下来','2026-11-07',0)]):
  c.execute('insert into items(id,note_id,content,day,done,sort_order,created_at) values(?,?,?,?,?,?,?)',(f'item-{i}','f7-0',text,day,done,i,'now'))
p=start()
def wins():return sp.check_output(['wmctrl','-lG'],text=True)
def win(title):return next(l.split()[0] for l in wins().splitlines() if title in l)
def click(w,x,y):sp.run(['xdotool','mousemove','--window',w,str(x),str(y),'click','1'],check=True);time.sleep(.6)
def shot(name,window='root'):
 sp.run(['xdotool','mousemove','1800','1100'],check=True);time.sleep(.4);sp.run(['import','-window',window,f'/workspace/desknotes/shots/{name}.png'],check=True)
try:
 w=win('今天，慢慢来');cwin=win('生活的小事')
 
 # Minimize the host tray fallback window for clean desktop captures.
 for line in wins().splitlines():
  if 'DeskNodes controls' in line:sp.run(['xdotool','windowminimize',line.split()[0]],check=True)
 shot('f7-collapse-light')
 # Collapsed menu must be reachable; expand restores saved card height.
 click(cwin,347,28);click(cwin,240,70)
 with sqlite3.connect(db) as c:assert c.execute("select collapsed,height from notes where id='f7-1'").fetchone()==(0,440)
 click(cwin,347,28);click(cwin,240,70)
 with sqlite3.connect(db) as c:assert c.execute("select collapsed,height from notes where id='f7-1'").fetchone()==(1,440)
 click(w,340,412);shot('f7-collapse-dark')
 click(w,340,412)
 # Tomorrow disclosure follows completed group.
 click(w,65,250)
 shot('f7-tomorrow',w);shot('f7-url-link',w)
 click(w,145,139)
 assert opened.read_text().strip()=='https://example.com/'
 # The non-link text still opens the plain-text editor.
 click(w,65,139)
 sp.run(['xdotool','key','ctrl+a'],check=True)
 sp.run(['xdotool','type','--clearmodifiers','Read https://example.com today'],check=True)
 sp.run(['xdotool','key','Return'],check=True);time.sleep(.6)
 with sqlite3.connect(db) as c:assert c.execute("select content from items where id='item-1'").fetchone()[0]=='Read https://example.com today'
 click(w,110,354)
 sp.run(['xdotool','type','--clearmodifiers','A small plan'],check=True)
 sp.run(['xdotool','key','Return'],check=True);time.sleep(.6)
 with sqlite3.connect(db) as c:assert c.execute("select day from items where content='A small plan'").fetchone()==('2026-11-07',)

 print('PASS collapse/expand geometry and persistence, URL launcher vs plain text edit, tomorrow add; native captures complete')
finally:stop(p);log.close()
