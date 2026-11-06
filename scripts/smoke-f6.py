"""Native F6 smoke + captures. Build with tauri/custom-protocol; requires fresh fixture directory."""
import os,sqlite3,subprocess as sp,time,pathlib
os.environ.update(DISPLAY=':3',DESKNODES_DATA_DIR='/tmp/desknodes-f6-shots',XDG_CONFIG_HOME='/tmp/desknodes-f6-config',GDK_BACKEND='x11')
if pathlib.Path('/tmp/desknodes-f6-shots').exists():
 raise RuntimeError('Preserve or move /tmp/desknodes-f6-shots before running this fresh-fixture smoke test')
log=open('/workspace/desknotes/logs/f6-runtime.log','w')
p=sp.Popen(['/workspace/desknotes/target/debug/desk-nodes'],stdout=log,stderr=log,env=os.environ,start_new_session=True)
try:
 time.sleep(3)
 sp.run(['xdotool','key','ctrl+shift+d'],check=True);time.sleep(2)
 db='/tmp/desknodes-f6-shots/desknodes.sqlite3';shots=pathlib.Path('/workspace/desknotes/shots')
 def windows():return sp.check_output(['wmctrl','-lpG'],text=True).splitlines()
 def win(title):return next(l.split()[0] for l in windows() if l.split(None,8)[-1]==title)
 w=win('DeskNodes')
 def click(x,y):sp.run(['xdotool','mousemove','--window',w,str(x),str(y),'click','1'],check=True);time.sleep(.35)
 def key(k):sp.run(['xdotool','key','--clearmodifiers',k],check=True);time.sleep(.4)
 def value(k):
  with sqlite3.connect(db) as c:return c.execute('select value from settings where key=?',(k,)).fetchone()[0]
 def shot(name):time.sleep(.5);sp.run(['import','-window',w,str(shots/name)],check=True)
 click(65,179)
 shot('f6-settings-light.png')
 # Duplicate binding must fail and retain the previous active registration.
 click(860,520);key('ctrl+a');sp.run(['xdotool','type','--clearmodifiers','Control+Shift+Space'],check=True);key('Return')
 assert value('shortcut_new_note')=='Control+Shift+N'
 shot('f6-shortcut-conflict.png')
 # Clear failed attempt and change appearance; event broadcasts to all webviews.
 key('Escape');click(940,317);key('End');key('Return');assert value('appearance')=='dark'
 shot('f6-settings-dark.png')
 click(940,317);key('Home');key('Down');key('Return');assert value('appearance')=='light'
 # Live appearance controls and day-engine settings.
 click(840,359);key('Home');key('Right');key('Right');key('Right');key('Right');key('Right');assert value('note_opacity')=='75'
 click(940,399);key('End');key('Return');assert value('font_size')=='large'
 click(940,235);key('Home');key('Down');key('Down');key('Down');key('Return');assert value('rollover_hour')=='3'
 click(996,194);assert value('auto_carry')=='0';click(996,194);assert value('auto_carry')=='1'
 # Real plugin writes an XDG desktop entry into an isolated config directory.
 click(996,152);assert value('autostart')=='0';click(996,152);assert value('autostart')=='1'
 autostart=pathlib.Path('/tmp/desknodes-f6-config/autostart/DeskNodes.desktop');assert autostart.exists();assert 'Exec=' in autostart.read_text()
 # New-note shortcut still works after the rejected change.
 key('ctrl+shift+n');time.sleep(.7)
 with sqlite3.connect(db) as c: assert c.execute('select count(*) from notes').fetchone()[0]==2
 # Place notes side by side and capture the desktop.
 notes=[l.split()[0] for l in windows() if 'DeskNodes · ' in l]
 for i,n in enumerate(notes):sp.run(['wmctrl','-ir',n,'-e',f'0,{300+i*440},270,400,410'],check=True)
 sp.run(['xdotool','windowminimize',w],check=True);time.sleep(.8)
 sp.run(['import','-window','root',str(shots/'f6-notes-opacity-font.png')],check=True)
 # Individually hide one note, then temporary hide/restore must leave it hidden.
 with sqlite3.connect(db) as c:ids=[r[0] for r in c.execute('select id from notes order by sort_order')]
 n=notes[0];sp.run(['wmctrl','-ic',n],check=True);time.sleep(.5)
 key('ctrl+shift+space');time.sleep(1.3)
 with sqlite3.connect(db) as c:assert c.execute('select sum(visible) from notes').fetchone()[0]==0
 assert value('hide_all_hint_shown')=='1'
 key('ctrl+shift+space')
 with sqlite3.connect(db) as c:assert c.execute('select sum(visible) from notes').fetchone()[0]==1
 print('PASS native shortcuts, duplicate rejection retaining working binding, live appearance/opacity/font/hour/carry, XDG autostart entry, hide-all restore subset and persisted hint')
finally:
 p.terminate()
 p.wait(timeout=10)
 log.close()
