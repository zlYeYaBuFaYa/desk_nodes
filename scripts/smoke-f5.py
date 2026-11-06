"""Isolated native F5 smoke checks and screenshot fixtures (requires X11)."""
import os, pathlib, sqlite3, subprocess as sp, time, signal
os.environ.update(DISPLAY=':3', DESKNODES_DATA_DIR='/tmp/desknodes-f5-shots', DESKNODES_FAKE_NOW='2026-10-29T12:00:00', GDK_BACKEND='x11')
root=pathlib.Path(os.environ['DESKNODES_DATA_DIR']); root.mkdir(exist_ok=True)
db=root/'desknodes.sqlite3'
if db.exists():
    raise RuntimeError('Fixture directory already exists; preserve or remove it before running')
c=sqlite3.connect(db); c.executescript(pathlib.Path('src-tauri/src/db/001.sql').read_text());c.execute('pragma user_version=1')
c.executemany('insert into settings values(?,?)',[('current_business_day','2026-10-29'),('rollover_hour','0'),('auto_carry','1')])
for i,(title,color) in enumerate([('工作','mist'),('生活','apricot'),('读书会','stone')]):
 c.execute('insert into notes(id,title,color,x,y,width,height,visible,pinned,sort_order,created_at,deleted_at) values(?,?,?,?,?,?,?,?,?,?,?,?)',(f'n{i}',title,color,40+i*50,280,360,400,i==0,i==0,i,'now','deleted' if i==2 else None))
texts=[['整理周会纪要','回复客户邮件','评审设计稿'],['交水电费','去健身房'],['准备分享材料','读完第 5 章']]
for day in range(1,29):
 for ni,items in enumerate(texts):
  for j,text in enumerate(items):
   done=(day%4==0 or (day%4==1 and j==0) or (day%4==2 and ni<2))
   if day in (27,28): done=(j==0)
   c.execute('insert into items(id,note_id,content,day,done,sort_order,created_at) values(?,?,?,?,?,?,?)',(f'd{day}n{ni}i{j}',f'n{ni}',text,f'2026-10-{day:02}',done,j,'now'))
for j,(text,days) in enumerate([('评审设计稿',3),('整理下一阶段的计划',1)]):
 c.execute('insert into items(id,note_id,content,day,sort_order,created_at,carry_days,carried_from) values(?,?,?,?,?,?,?,?)',(f'today{j}','n0',text,'2026-10-29',j,'now',days,'d28n0i2' if j==0 else 'd28n0i1'))
c.commit();c.close()
binary=os.getenv('DESKNODES_BINARY','/workspace/desknotes/target/debug/desk-nodes')
shots=pathlib.Path('/workspace/desknotes/shots');shots.mkdir(exist_ok=True)
def windows():
 return sp.check_output(['wmctrl','-lpG'],text=True).splitlines()
def win(title):
 return next(line.split()[0] for line in windows() if line.split(None,8)[-1]==title)
def click(w,x,y):
 sp.run(['xdotool','mousemove','--window',w,str(x),str(y),'click','1'],check=True);time.sleep(.5)
def shot(w,name):
 sp.run(['xdotool','windowactivate','--sync',w],check=True);time.sleep(.4);sp.run(['import','-window',w,str(shots/name)],check=True)
def launch(theme):
 env=os.environ|{'DESKNODES_THEME':theme};log=open(f'/workspace/desknotes/logs/f5-runtime-{theme}.log','w');p=sp.Popen([binary],env=env,stdout=log,stderr=log,start_new_session=True);time.sleep(4)
 second=sp.run([binary],env=env,timeout=15,capture_output=True);assert second.returncode==0,second.stderr;time.sleep(2)
 return p,log,win('DeskNodes')
def stop(p,log):
 os.killpg(p.pid,signal.SIGTERM);p.wait();log.close();time.sleep(1)
p,log,w=launch('light')
try:
 assert len([line for line in windows() if line.split(None,8)[-1]=='DeskNodes'])==1
 shot(w,'f5-panel-notes.png')
 # Visibility and pin update through the management command.
 click(w,980,160)
 with sqlite3.connect(db) as c: assert c.execute("select visible from notes where id='n0'").fetchone()[0]==0
 click(w,980,160)
 click(w,928,160)
 with sqlite3.connect(db) as c: assert c.execute("select pinned from notes where id='n0'").fetchone()[0]==0
 click(w,928,160)
 click(w,60,139) # History sidebar
 # October 27: fifth calendar row, Tuesday.
 click(w,317,380)
 shot(w,'f5-history-light.png')
 # Older days cannot toggle; yesterday can, and today's carried copy disappears.
 click(w,774,164)
 with sqlite3.connect(db) as c: assert c.execute("select done from items where id='d27n0i1'").fetchone()[0]==0
 click(w,390,365);click(w,774,164)
 with sqlite3.connect(db) as c:
  assert c.execute("select done from items where id='d28n0i1'").fetchone()[0]==1
  assert c.execute("select count(*) from items where id='today1'").fetchone()[0]==0
 click(w,774,164)
 with sqlite3.connect(db) as c: assert c.execute("select done from items where id='d28n0i1'").fetchone()[0]==0
 click(w,698,44);click(w,661,44)
 # Close destroys the panel; second launch recreates it on notes.
 sp.run(['wmctrl','-ic',w],check=True);time.sleep(.7)
 assert all(line.split(None,8)[-1]!='DeskNodes' for line in windows())
 sp.run([binary],timeout=15,check=True);time.sleep(1);w=win('DeskNodes')
 sp.run(['wmctrl','-ic',w],check=True);time.sleep(.5)
 shot(win('DeskNodes · 工作'),'f5-carry-badge.png')
 print('PASS single instance; one panel; visibility/pin commands; readonly older days; yesterday done/undone and carried-copy removal; month navigation; panel destroyed and recreated')
finally: stop(p,log)
p,log,w=launch('dark')
try:
 click(w,60,139);click(w,317,380);shot(w,'f5-history-dark.png')
finally: stop(p,log)
