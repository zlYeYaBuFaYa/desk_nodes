"""Native F8 smoke and captures. Uses an isolated, disposable fixture."""
import os, pathlib, signal, sqlite3, subprocess as sp, time
os.environ.update(DISPLAY=':3', DESKNODES_DATA_DIR='/tmp/desknodes-f8-shots', DESKNODES_FAKE_NOW='2026-11-06T12:00:00', XDG_CONFIG_HOME='/tmp/desknodes-f8-config', GDK_BACKEND='x11')
root=pathlib.Path(os.environ['DESKNODES_DATA_DIR']); root.mkdir(exist_ok=True)
log=open('/workspace/desknotes/logs/f8-runtime.log','w')
def start():
 p=sp.Popen(['/workspace/desknotes/target/debug/desk-nodes'],env=os.environ,stdout=log,stderr=log,start_new_session=True);time.sleep(3);return p
def stop(p):
 os.killpg(p.pid,signal.SIGTERM);p.wait(timeout=10);time.sleep(.5)
p=start();stop(p)
db=root/'desknodes.sqlite3'
with sqlite3.connect(db) as c:
 c.execute('delete from items');c.execute('delete from notes')
 c.execute("insert or replace into settings values('appearance','light')")
 c.execute("insert or replace into settings values('current_business_day','2026-11-06')")
 for i,(title,color) in enumerate([('今天，慢慢来','mist'),('生活的小事','sage')]):
  c.execute('insert into notes(id,title,color,x,y,width,height,visible,pinned,collapsed,sort_order,created_at) values(?,?,?,?,?,380,440,1,0,0,?,?)',(f'f8-{i}',title,color,420+i*440,300,i,'now'))
 for i,(text,note,day,done) in enumerate([('整理本周的灵感与笔记',0,'2026-11-06',0),('留一点时间，读几页书',0,'2026-11-06',0),('让桌面恢复一点留白',0,'2026-11-06',1),('带一本书，去喜欢的咖啡馆',0,'2026-11-07',0),('买一束花，放在窗边',1,'2026-11-06',0)]):
  c.execute('insert into items(id,note_id,content,day,done,sort_order,created_at) values(?,?,?,?,?,?,?)',(f'item-{i}',f'f8-{note}',text,day,done,i,'now'))
p=start()
def wins():return sp.check_output(['wmctrl','-lG'],text=True)
def win(title):return next(l.split()[0] for l in wins().splitlines() if title in l)
def click(w,x,y,button=1):
 sp.run(['xdotool','mousemove','--window',w,str(x),str(y),'click',str(button)],check=True);time.sleep(.5)
def shot(name):
 sp.run(['xdotool','mousemove','1800','1100'],check=True);time.sleep(.3)
 sp.run(['import','-window','root',f'/workspace/desknotes/shots/{name}.png'],check=True)
def row(item):
 with sqlite3.connect(db) as c:return c.execute('select note_id,day,done from items where id=?',(item,)).fetchone()
def menu(w,y):
 click(w,145,y,3);click(w,175,min(y,230)+16)
try:
 w=win('今天，慢慢来');target=win('生活的小事')
 for line in wins().splitlines():
  if 'DeskNodes controls' in line:sp.run(['xdotool','windowminimize',line.split()[0]],check=True)
 menu(w,110);shot('f8-move-menu-light')
 sp.run(['xdotool','key','Escape'],check=True);time.sleep(.3)
 click(w,340,412);menu(w,110);shot('f8-move-menu-dark')
 sp.run(['xdotool','key','Escape'],check=True);time.sleep(.3)
 click(w,340,412);menu(w,110);click(w,190,169)
 assert row('item-0')==('f8-1','2026-11-06',0), row('item-0')
 shot('f8-moved-light')
 click(w,315,365)
 assert row('item-0')==('f8-0','2026-11-06',0),row('item-0')
 # Completed item move and undo.
 click(w,70,224);menu(w,247);click(w,190,294)
 assert row('item-2')==('f8-1','2026-11-06',1),row('item-2')
 click(w,315,365)
 assert row('item-2')==('f8-0','2026-11-06',1)
 # Tomorrow retains its date.
 click(w,65,289);menu(w,322);click(w,190,294)
 assert row('item-3')==('f8-1','2026-11-07',0),row('item-3')
 print('PASS today/completed/tomorrow move, undo, identity/day/done, Escape, light/dark captures')
finally:stop(p);log.close()
