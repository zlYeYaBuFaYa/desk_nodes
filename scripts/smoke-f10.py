"""Isolated native F10 acceptance; never installs a package or changes system autostart."""
import os, pathlib, signal, sqlite3, subprocess as sp, time, json
os.environ.update(DISPLAY=':3', DESKNODES_DATA_DIR='/tmp/desknodes-f10-shots', DESKNODES_FAKE_NOW='2026-11-06T12:00:00', XDG_CONFIG_HOME='/tmp/desknodes-f10-config', GDK_BACKEND='x11')
root=pathlib.Path(os.environ['DESKNODES_DATA_DIR']);root.mkdir(exist_ok=True)
binary=os.getenv('DESKNODES_BINARY','/workspace/desknotes/target/release/desk-nodes')
log=open('/workspace/desknotes/logs/f10-runtime.log','w')
def start():
 p=sp.Popen([binary],env=os.environ,stdout=log,stderr=log,start_new_session=True);time.sleep(4);return p
def stop(p):
 os.killpg(p.pid,signal.SIGTERM);p.wait(timeout=10);time.sleep(.5)
def wins():return sp.check_output(['wmctrl','-lG'],text=True).splitlines()
def win(title):
 rows=wins()
 return next((l.split()[0] for l in rows if l.split(None,7)[-1]==title),next(l.split()[0] for l in rows if title in l))
def click(w,x,y,button=1,delay=.5):
 sp.run(['xdotool','mousemove','--window',w,str(x),str(y),'click',str(button)],check=True);time.sleep(delay)
def shot(name,w='root'):
 sp.run(['xdotool','mousemove','1800','1100'],check=True);time.sleep(.25)
 sp.run(['import','-window',w,f'/workspace/desknotes/shots/f10-{name}.png'],check=True)
def geometry(w):
 data=sp.check_output(['xdotool','getwindowgeometry','--shell',w],text=True)
 return dict(line.split('=',1) for line in data.splitlines() if '=' in line)
def sql(query,args=()):
 with sqlite3.connect(root/'desknodes.sqlite3') as c:return c.execute(query,args).fetchall()
p=start();stop(p)
with sqlite3.connect(root/'desknodes.sqlite3') as c:
 c.execute('drop trigger if exists f10_geometry');c.execute('drop table if exists f10_audit')
 c.execute('delete from items');c.execute('delete from notes')
 c.execute("insert or replace into settings values('appearance','dark')")
 c.execute("insert or replace into settings values('current_business_day','2026-11-06')")
 for i,(title,color) in enumerate([('今天，慢慢来','mist'),('生活的小事','sage')]):
  c.execute('insert into notes(id,title,color,x,y,width,height,visible,pinned,collapsed,sort_order,created_at) values(?,?,?,?,?,380,440,1,0,0,?,?)',(f'f10-{i}',title,color,420+i*440,300,i,'now'))
 c.execute("insert into items(id,note_id,content,day,done,sort_order,created_at) values('item','f10-0','整理本周的灵感与笔记','2026-11-06',0,0,'now')")
p=start()
try:
 for l in wins():
  if 'DeskNodes controls' in l:sp.run(['xdotool','windowminimize',l.split()[0]],check=True)
 w=win('今天，慢慢来');target=win('生活的小事')
 with sqlite3.connect(root/'desknodes.sqlite3') as c:
  c.execute('create table f10_audit(id text,height integer)')
  c.execute('create trigger f10_geometry after update of x,y,width,height on notes begin insert into f10_audit values(new.id,new.height); end')
 click(w,145,110,3);click(w,175,126);shot('move-menu-dark')
 sp.run(['xdotool','key','Escape'],check=True);time.sleep(.3)
 def tween(collapsed):
  sql('delete from f10_audit')
  click(w,347,28)
  click(w,240,70,delay=0)
  samples=[];deadline=time.monotonic()+.65
  while time.monotonic()<deadline:
   samples.append((time.monotonic(),int(geometry(w)['HEIGHT']),sql("select height from notes where id='f10-0'")[0][0]));time.sleep(.008)
  assert sql("select collapsed,height from notes where id='f10-0'")==[(collapsed,440)]
  writes=sql("select height from f10_audit where id='f10-0'")
  assert writes==[(440,)],writes
  heights=sorted(set(s[1] for s in samples))
  assert len(heights)>2,heights
  assert all(s[2]==440 for s in samples),samples
  assert int(geometry(w)['HEIGHT'])==(58 if collapsed else 440)
  print(f'tween collapsed={collapsed}: sampled heights={heights}; geometry writes={len(writes)}; DB height always 440',flush=True)
  return samples
 tween(1);tween(0);shot('collapse-tween')
 # Real GTK work-area notification via the disposable X11 root property.
 original=sp.check_output(['xprop','-root','_NET_WORKAREA'],text=True).split('=',1)[1].strip()
 try:
  sp.run(['xprop','-root','-f','_NET_WORKAREA','32c','-set','_NET_WORKAREA','0, 0, 1000, 800'],check=True)
  time.sleep(4)
  rows=sql('select x,y,width,height from notes where deleted_at is null')
  if all(x>=0 and x+width<=1000 and y+height<=800 for x,y,width,height in rows):
   print('PASS live work-area shrink: both windows clamped and persisted',rows,flush=True)
  else: print('CAVEAT GTK/X11 ignored synthetic work-area change; physical hotplug still manual',rows,flush=True)
 finally:
  sp.run(['xprop','-root','-f','_NET_WORKAREA','32c','-set','_NET_WORKAREA',original],check=True);time.sleep(4)
 # Open management before deleting all notes using their native confirmation UI.
 sp.run([binary],env=os.environ,check=True,timeout=15);time.sleep(2)
 panel=win('DeskNodes')
 sp.run(['xdotool','windowminimize',panel],check=True)
 for current in [w,target]:
  sp.run(['xdotool','windowactivate','--sync',current],check=True)
  click(current,347,28);click(current,240,134);click(current,290,250)
  # Confirmation layout may differ; verify instead of assuming deletion.
  if sql('select count(*) from notes where deleted_at is null')[0][0] == (2 if current==w else 1):
   shot('delete-debug',current);raise AssertionError('delete confirmation coordinate needs adjustment')
 assert sql('select count(*) from notes where deleted_at is null')==[(0,)]
 sp.run(['xdotool','windowmap',panel],check=True);sp.run(['xdotool','windowactivate','--sync',panel],check=True);time.sleep(1)
 shot('last-note-empty',panel)
 print('PASS last-note deletion and empty management capture',flush=True)
 click(panel,614,376);time.sleep(1)
 assert sql('select count(*) from notes where deleted_at is null')==[(1,)]
 assert sql('select count(*) from items join notes on notes.id=items.note_id where notes.deleted_at is null')==[(0,)]
 print('PASS new note from empty state, without first-run reseeding',flush=True)
finally:stop(p);log.close()
