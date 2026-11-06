#!/usr/bin/env python3
# X11 release smoke test; close other DeskNodes instances before running.
import os, subprocess as sp, time, sqlite3, re, pathlib, signal, tempfile
os.environ['DISPLAY']=':3'
root=pathlib.Path(tempfile.mkdtemp(prefix='desknodes-f2-smoke-'))
os.environ['DESKNODES_DATA_DIR']=str(root);os.environ['DESKNODES_THEME']='light'
binary=os.getenv('DESKNODES_BINARY', '/workspace/desknotes/target/release/desk-nodes')
def run(*args):return sp.check_output(args,text=True).strip()
def click(x,y,count=1):sp.run(['xdotool','mousemove',str(x),str(y),'click','--repeat',str(count),'--delay','100','1'],check=True);time.sleep(.35)
def key(*keys):sp.run(['xdotool','key',*keys],check=True);time.sleep(.25)
def text(s):sp.run(['xdotool','type','--clearmodifiers',s],check=True);time.sleep(.15)
def windows():return [line.split()[0] for line in run('wmctrl','-l').splitlines() if 'DeskNodes ·' in line]
def geom(w):
 s=run('xwininfo','-id',w)
 return tuple(int(re.search(p,s)[1]) for p in [r'Absolute upper-left X:\s+(-?\d+)',r'Absolute upper-left Y:\s+(-?\d+)',r'Width:\s+(\d+)',r'Height:\s+(\d+)'])
def notes():
 with sqlite3.connect(root/'desknodes.sqlite3') as c:c.row_factory=sqlite3.Row;return [dict(r) for r in c.execute('select * from notes order by sort_order')]
def menu(index):
 c=next(l.split()[0] for l in run('wmctrl','-l').splitlines() if 'DeskNodes controls' in l);x,y,_,_=geom(c);click(x+40,y+13);click(x+65,y+41+index*29)
def start():
 log=open('/workspace/desknotes/logs/f2-smoke-app.log','a');p=sp.Popen([binary],stdout=log,stderr=log,start_new_session=True);time.sleep(2);return p
p=start()
try:
 assert len(notes())==1 and notes()[0]['color']=='mist'
 with sqlite3.connect(root/'desknodes.sqlite3') as c:assert c.execute('select count(*) from items').fetchone()[0]==3
 w=windows()[0];x,y,ww,hh=geom(w)
 assert '_NET_WM_STATE_SKIP_TASKBAR' in run('xprop','-id',w,'_NET_WM_STATE')
 hints=run('xprop','-id',w,'WM_NORMAL_HINTS');assert '220 by 160' in hints and '600 by 900' in hints
 # Drag the transparent southeast resize hit area, as a user would.
 sp.run(['xdotool','mousemove',str(x+ww-4),str(y+hh-4),'mousedown','1','sleep','.2','mousemove',str(x+ww+35),str(y+hh+40),'sleep','.2','mouseup','1'],check=True);time.sleep(.5)
 assert geom(w)[2]>ww and geom(w)[3]>hh
 sp.run(['wmctrl','-ir',w,'-e',f'0,{x},{y},300,360'],check=True);time.sleep(.4)

 click(x+45,y+28,2);key('ctrl+a');text('Daily focus');key('Return');assert notes()[0]['title']=='Daily focus'
 click(x+45,y+28,2);key('ctrl+a');text('Cancelled');key('Escape');assert notes()[0]['title']=='Daily focus'
 click(x+210,y+28);click(x+194,y+72);assert notes()[0]['color']=='sage'
 click(x+185,y+28);assert notes()[0]['pinned']==1;assert '_NET_WM_STATE_ABOVE' in run('xprop','-id',w,'_NET_WM_STATE')
 sp.run(['xdotool','mousemove',str(x+50),str(y+28),'mousedown','1','sleep','.2','mousemove',str(x+120),str(y+90),'sleep','.2','mousemove',str(x+150),str(y+110),'sleep','.2','mouseup','1'],check=True);time.sleep(.5)
 assert geom(w)[:2]!=(x,y)
 sp.run(['wmctrl','-ir',w,'-e','0,400,300,390,440'],check=True);time.sleep(.5)
 assert notes()[0]['width']==390 and notes()[0]['height']==440
 x,y,ww,hh=geom(w);click(x+ww-62,y+28);assert notes()[0]['visible']==0;assert 'IsUnMapped' in run('xwininfo','-id',w)
 menu(1);assert notes()[0]['visible']==1;assert 'IsViewable' in run('xwininfo','-id',w)
 # A fresh note receives keyboard focus, and Enter commits its title.
 menu(0);text('Created by controls');key('Return');assert len(notes())==2 and notes()[1]['title']=='Created by controls'
 nw=next(a for a in windows() if a!=w);nx,ny,nww,_=geom(nw);click(nx+nww-37,ny+28);click(nx+nww-120,ny+105);time.sleep(.2)
 # Confirmation retains data until confirmed; Escape cancels.
 assert notes()[1]['deleted_at'] is None;key('Escape');assert notes()[1]['deleted_at'] is None
 click(nx+nww-37,ny+28);click(nx+nww-120,ny+105);click(nx+nww-65,ny+220);time.sleep(.5)
 assert notes()[1]['deleted_at'] is not None and len(windows())==1
 menu(2);assert notes()[0]['visible']==0;menu(1);assert notes()[0]['visible']==1
 before=notes()[0];p.terminate();p.wait();time.sleep(.5);p=start();after=notes()[0]
 assert len(windows())==1
 assert all(before[k]==after[k] for k in ['title','color','pinned','x','y','width','height']), (before,after)
 assert geom(windows()[0])==(after['x'],after['y'],after['width'],after['height'])
 print('PASS: seed; rename/cancel; palette; pin; drag; native edge resize/size bounds; resize; hide/show; native create; delete confirmation/cancel; hide/show all; restart geometry/pin/title/color; soft-delete retention')
finally:
 p.terminate();p.wait()
