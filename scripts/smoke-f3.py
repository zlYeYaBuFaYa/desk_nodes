"""X11 item lifecycle smoke test. Uses an isolated temporary database."""
import os, pathlib, sqlite3, subprocess as sp, tempfile, time
os.environ['DISPLAY'] = os.getenv('DISPLAY', ':3')
root = pathlib.Path(tempfile.mkdtemp(prefix='desknodes-f3-smoke-'))
os.environ['DESKNODES_DATA_DIR'] = str(root)
os.environ['DESKNODES_THEME'] = 'light'
binary = os.getenv('DESKNODES_BINARY', '/workspace/desknotes/target/release/desk-nodes')
def click(x, y):
    sp.run(['xdotool','mousemove',str(x),str(y),'click','1'],check=True); time.sleep(.35)
def key(keys):
    sp.run(['xdotool','key','--clearmodifiers',keys],check=True); time.sleep(.3)
def text(value):
    sp.run(['xdotool','type','--clearmodifiers',value],check=True); time.sleep(.2)
def rows():
    with sqlite3.connect(root/'desknodes.sqlite3') as c:
        c.row_factory=sqlite3.Row
        return [dict(r) for r in c.execute('select * from items order by sort_order')]
log = open('/workspace/desknotes/logs/f3-smoke-app.log','w')
p = sp.Popen([binary],stdout=log,stderr=log)
try:
    time.sleep(3)
    assert len(rows()) == 3
    # Default note geometry: 160,180,300,360. Three one-line items.
    click(215,388); text('Continuous one'); key('Return'); text('Continuous two'); key('Return')
    assert [r['content'] for r in rows()][-2:] == ['Continuous one','Continuous two'], rows()
    click(240,286); key('ctrl+a'); text('Edited first'); key('Return')
    assert rows()[0]['content']=='Edited first'
    click(192,286); assert rows()[0]['done']==1
    click(230,456)  # expand the completed group
    click(192,486)
    assert all(not r['done'] for r in rows()), rows()
    assert rows()[-1]['content']=='Edited first'
    click(426,286)
    assert len(rows())==4
    click(415,473)
    assert len(rows())==5
    before=[r['id'] for r in rows()]
    sp.run(['xdotool','mousemove','179','286','mousedown','1','sleep','.2','mousemove','179','320','sleep','.2','mousemove','179','386','sleep','.3','mouseup','1'],check=True)
    time.sleep(.7)
    assert [r['id'] for r in rows()] != before, rows()
    assert sorted(r['sort_order'] for r in rows())==list(range(5))
    click(240,286);key('ctrl+a');text('Blur saved');click(210,245)
    assert rows()[0]['content']=='Blur saved'
    key('Delete');assert len(rows())==4
    click(415,473);assert len(rows())==5
    click(240,286);key('ctrl+a');text('x'*205);key('Return')
    assert len(rows()[0]['content'])==200
    control=next(line.split()[0] for line in sp.check_output(['wmctrl','-l'],text=True).splitlines() if 'DeskNodes controls' in line)
    def toggle_note():
        sp.run(['xdotool','windowmap',control],check=True)
        click(200,119);click(225,176)
    toggle_note()
    with sqlite3.connect(root/'desknodes.sqlite3') as c: assert c.execute('select visible from notes').fetchone()[0]==0
    toggle_note()
    with sqlite3.connect(root/'desknodes.sqlite3') as c: assert c.execute('select visible from notes').fetchone()[0]==1
    for _ in range(5): click(426,286)
    assert not rows()
    text('Empty focus');key('Return');assert rows()[0]['content']=='Empty focus'
    print('PASS: empty-list autofocus; drag reorder/sort_order; continuous entry/focus; Enter/blur edits; 200-char limit; complete/uncomplete append; button/keyboard delete; undo; native note visibility toggle')
finally:
    p.terminate();p.wait();log.close()
