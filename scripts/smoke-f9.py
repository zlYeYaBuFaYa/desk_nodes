"""Native F9 fixture, history interactions, theme captures and memory sample."""
import os, pathlib, signal, sqlite3, subprocess as sp, time
os.environ.update(DISPLAY=':3', DESKNODES_DATA_DIR='/tmp/desknodes-f9-shots', DESKNODES_FAKE_NOW='2026-11-06T12:00:00', GDK_BACKEND='x11', XDG_CONFIG_HOME='/tmp/desknodes-f9-config')
root=pathlib.Path(os.environ['DESKNODES_DATA_DIR']);root.mkdir(exist_ok=True)
binary='/workspace/desknotes/target/debug/desk-nodes'
log=open('/workspace/desknotes/logs/f9-runtime.log','w')
def start(theme):
 p=sp.Popen([binary],env=os.environ|{'DESKNODES_THEME':theme},stdout=log,stderr=log,start_new_session=True);time.sleep(4);return p
def stop(p):
 os.killpg(p.pid,signal.SIGTERM);p.wait(timeout=10);time.sleep(.5)
def win():
 lines=sp.check_output(['wmctrl','-l'],text=True).splitlines()
 return next(l.split()[0] for l in lines if l.split(None,3)[-1]=='DeskNodes')
def click(w,x,y):
 sp.run(['xdotool','mousemove','--window',w,str(x),str(y),'click','1'],check=True);time.sleep(.6)
def shot(w,theme):
 sp.run(['xdotool','mousemove','1800','1100'],check=True);time.sleep(.3)
 sp.run(['import','-window',w,f'/workspace/desknotes/shots/f9-stats-{theme}.png'],check=True)
p=start('light');stop(p)
with sqlite3.connect(root/'desknodes.sqlite3') as c:
 c.execute('delete from items');c.execute('delete from notes')
 c.execute("insert or replace into settings values('current_business_day','2026-11-06')")
 c.execute("insert into notes(id,title,color,x,y,width,height,visible,pinned,collapsed,sort_order,created_at) values('f9','日常的小事','sage',100,180,360,400,0,0,0,0,'now')")
 for day in range(1,8):
  for i,text in enumerate(['整理本周的灵感','读几页喜欢的书','给窗边的植物浇水']):
   done=day in (3,4,5,7) or i==0
   c.execute('insert into items(id,note_id,content,day,done,sort_order,created_at) values(?,?,?,?,?,?,?)',(f'd{day}-{i}','f9',text,f'2026-11-{day:02}',done,i,'now'))
for theme in ['light','dark']:
 with sqlite3.connect(root/'desknodes.sqlite3') as c:
  c.execute("insert or replace into settings values('appearance',?)",(theme,))
 p=start(theme)
 try:
  sp.run([binary],env=os.environ,check=True,timeout=15);time.sleep(2)
  w=win();click(w,60,139)
  # Navigate back and forth, then choose yesterday for editable detail.
  click(w,661,44);click(w,698,44);click(w,463,316)
  shot(w,theme)
  if theme=='light':
   # Toggle yesterday's second item, then restore it; persistence + refresh.
   click(w,780,164)
   with sqlite3.connect(root/'desknodes.sqlite3') as c:
    assert c.execute("select done from items where id='d5-1'").fetchone()[0]==0
   click(w,780,164)
   with sqlite3.connect(root/'desknodes.sqlite3') as c:
    assert c.execute("select done from items where id='d5-1'").fetchone()[0]==1
   shot(w,theme)
  time.sleep(2)
  entries={}
  for d in pathlib.Path('/proc').iterdir():
   if not d.name.isdigit():continue
   try:
    fields=(d/'stat').read_text().rsplit(')',1)[1].split()
    if int(fields[3])==p.pid:entries[int(d.name)]=d
   except (OSError,ValueError):pass
  rss=pss=0
  for d in entries.values():
   try:
    status=dict(l.split(':',1) for l in (d/'status').read_text().splitlines() if ':' in l)
    roll=dict(l.split(':',1) for l in (d/'smaps_rollup').read_text().splitlines() if ':' in l)
    rss+=int(status.get('VmRSS','0 kB').split()[0]);pss+=int(roll['Pss'].split()[0])
   except OSError:pass
  print(f'{theme}: history panel, hidden note; RSS {rss/1024:.2f} MiB; PSS {pss/1024:.2f} MiB',flush=True)
 finally:stop(p)
print('PASS native history navigation, yesterday toggle/restore, light/dark captures')
log.close()
