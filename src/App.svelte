<script lang="ts">
  import { dragHandleZone, dragHandle } from 'svelte-dnd-action';
  import { onMount, tick } from 'svelte';
  import { invoke } from '@tauri-apps/api/core';
  import { listen } from '@tauri-apps/api/event';
  import { LogicalSize } from '@tauri-apps/api/dpi';
  import { getCurrentWindow } from '@tauri-apps/api/window';
  type Note = { id:string; title:string; color:string; pinned:boolean; width:number; collapsed:boolean };
  type Item = { day?:string; id:string; content:string; done:boolean; sort_order:number; carry_days?:number; carried_from?:string };
  const params=new URLSearchParams(location.search), id=params.get('id');
  const palette=['mist','sage','apricot','lilac','butter','blush','celadon','stone'];
  const edges: {direction:Parameters<ReturnType<typeof getCurrentWindow>["startResizeDragging"]>[0]; style:string}[] = [
    {direction:'North',style:'top:0;left:10px;right:10px;width:auto;height:10px;cursor:n-resize'},
    {direction:'South',style:'bottom:0;left:10px;right:10px;width:auto;height:10px;cursor:s-resize'},
    {direction:'West',style:'left:0;top:10px;bottom:10px;height:auto;width:10px;cursor:w-resize'},
    {direction:'East',style:'right:0;top:10px;bottom:10px;height:auto;width:10px;cursor:e-resize'},
    {direction:'NorthWest',style:'top:0;left:0;cursor:nw-resize'},
    {direction:'NorthEast',style:'top:0;right:0;cursor:ne-resize'},
    {direction:'SouthWest',style:'bottom:0;left:0;cursor:sw-resize'},
    {direction:'SouthEast',style:'bottom:0;right:0;cursor:se-resize'}
  ];
  const names=['雾蓝','鼠尾草','杏橙','丁香','奶油黄','浅蔷薇','青瓷','暖石'];
  const fills=['#E3EBF3','#E2EBDF','#F7E6D6','#ECE2EE','#F7F0D4','#F6E1E1','#DCEDEA','#ECE9E4'];
  let destinations=$state<Note[]>([]);
  let context=$state<{item:Item;x:number;y:number}>(), moveExpanded=$state(false), moveUndo=$state<{item:Item;target:string}>();
  let note=$state<Note>(), items=$state<Item[]>([]), editing=$state(false), draft=$state('');
  let reducedMotion=$state(matchMedia('(prefers-reduced-motion: reduce)').matches), scrolling=$state(false), scrollTimer:ReturnType<typeof setTimeout>;
  function scrolled(){scrolling=true;clearTimeout(scrollTimer);scrollTimer=setTimeout(()=>scrolling=false,700);}
  let fading=$state(false), rolling=$state(false), notice=$state('');
  let mutationQueue:Promise<unknown>=Promise.resolve();
  let tomorrow=$state<Item[]>([]), tomorrowExpanded=$state(false), tomorrowEntry=$state('');
  let entry=$state(''), editId=$state(''), editText=$state(''), expanded=$state(false), selected=$state('');
  let pending=$state<string[]>([]), openItems=$state<Item[]>([]), undo=$state<Item>(), undoTimer:ReturnType<typeof setTimeout>;
  let editInput=$state<HTMLTextAreaElement>();
  $effect(()=>{openItems=items.filter(i=>!i.done || pending.includes(i.id));});
  const completed=$derived(items.filter(i=>i.done && !pending.includes(i.id)));
  const blank:Item={id:'',content:'',done:false,sort_order:0};
  async function mutate(op:string,item:Item=blank,order:string[]=[]){const task=mutationQueue.then(async()=>{await invoke('mutate_item',{op,item,order});await refresh();});mutationQueue=task.catch(()=>{});await task;}
  async function add(){if(!entry.trim())return;const content=entry;entry='';try{await mutate('add',{...blank,id:crypto.randomUUID(),content});}catch(e){entry=content+entry;throw e;}await tick();itemInput?.focus();}
  async function addTomorrow(){if(!tomorrowEntry.trim())return;const content=tomorrowEntry;tomorrowEntry='';try{await mutate('add_tomorrow',{...blank,id:crypto.randomUUID(),content});}catch(e){tomorrowEntry=content+tomorrowEntry;throw e;}}
  async function edit(item:Item){selected=item.id;editId=item.id;editText=item.content;await tick();editInput?.focus();}
  async function saveEdit(){if(!editId)return;const savingId=editId;const item=[...items,...tomorrow].find(i=>i.id===savingId);if(item && editText.trim())await mutate('edit',{...item,content:editText});if(editId===savingId)editId='';}
  async function toggle(item:Item){if(pending.includes(item.id))return;if(!item.done)pending=[...pending,item.id];try{await mutate('toggle',{...item,done:!item.done});if(!item.done)await new Promise(r=>setTimeout(r,300));}finally{pending=pending.filter(id=>id!==item.id);}}
  async function remove(item:Item){await mutate('delete',item);moveUndo=undefined;undo=item;clearTimeout(undoTimer);undoTimer=setTimeout(()=>undo=undefined,5000);selected='';if(!items.length){await tick();itemInput?.focus();}}
  async function restore(){if(moveUndo){await requestMove(moveUndo.item.id,id!,moveUndo.target);moveUndo=undefined;clearTimeout(undoTimer);await refresh();return;}if(!undo)return;await mutate('restore',undo);undo=undefined;clearTimeout(undoTimer);}
  async function reorder(event:CustomEvent<{items:Item[]}>){openItems=event.detail.items;await mutate('reorder',blank,openItems.filter(i=>!i.done).map(i=>i.id));}
  let panel=$state(''), error=$state(''), hiding=$state(false), theme=$state(params.get('theme')??'system');
  let titleInput=$state<HTMLInputElement>(), itemInput=$state<HTMLInputElement>();
  $effect(()=>{if(note?.collapsed){const width=note.width,height=panel==='palette'?160:panel?230:58;run(()=>getCurrentWindow().setSize(new LogicalSize(width,height)));}});
  $effect(()=>{document.documentElement.dataset.color=note?.color??'mist';});
  async function refresh(){const notes=await invoke<Note[]>('list_notes');destinations=notes.filter(n=>n.id!==id);note=notes.find(n=>n.id===id);items=await invoke<Item[]>('today_items',{id});tomorrow=await invoke<Item[]>('tomorrow_items',{id});}
  async function itemMenu(event:MouseEvent,item:Item){event.preventDefault();event.stopPropagation();panel='';moveExpanded=false;context={item,x:Math.max(12,Math.min(event.clientX,innerWidth-212)),y:Math.max(12,Math.min(event.clientY,innerHeight-210))};await tick();document.querySelector<HTMLButtonElement>('.item-menu > button')?.focus();}
  async function requestMove(itemId:string,target:string,source?:string){const task=mutationQueue.then(()=>invoke('move_item',{itemId,target,source}));mutationQueue=task.catch(()=>{});await task;}
  async function moveTo(target:string){if(!context)return;const item=context.item;context=undefined;await requestMove(item.id,target);undo=undefined;moveUndo={item,target};clearTimeout(undoTimer);undoTimer=setTimeout(()=>moveUndo=undefined,5000);await refresh();}
  async function run(task:()=>Promise<unknown>){try{await task();error='';}catch(e){error=String(e);}}
  function dragTitle(event:PointerEvent){
    if(event.button!==0)return;
    const x=event.screenX,y=event.screenY;
    const stop=()=>{window.removeEventListener('pointermove',move);window.removeEventListener('pointerup',stop);};
    const move=(next:PointerEvent)=>{if(Math.hypot(next.screenX-x,next.screenY-y)>4){stop();run(()=>getCurrentWindow().startDragging());}};
    window.addEventListener('pointermove',move);window.addEventListener('pointerup',stop,{once:true});
  }
  async function rename(){panel='';draft=note?.title??'';editing=true;await tick();titleInput?.focus();titleInput?.select();}
  async function save(changes:Partial<Note>={}){if(!note)return;await invoke('update_note',{title:note.title,color:note.color,pinned:note.pinned,collapsed:note.collapsed,...changes});await refresh();}
  async function confirmTitle(){if(!editing)return;editing=false;await run(()=>save({title:draft}));itemInput?.focus();}
  async function hide(){hiding=true;await new Promise(r=>setTimeout(r,140));await run(()=>invoke('hide_note'));hiding=false;}
  onMount(()=>{const media=matchMedia('(prefers-reduced-motion: reduce)');const motion=()=>reducedMotion=media.matches;media.addEventListener('change',motion);let disposed=false;let unlisten:(()=>void)|undefined;run(async()=>{await refresh();unlisten=await listen('notes-changed',()=>run(refresh));const offItems=await listen('items-changed',()=>run(refresh));const offPrepare=await listen('rollover-prepare',()=>{if(rolling)return;run(async()=>{rolling=true;try{await mutationQueue;await saveEdit();await add();await addTomorrow();await confirmTitle();undo=undefined;moveUndo=undefined;context=undefined;clearTimeout(undoTimer);await invoke('rollover_ready');}catch(e){rolling=false;throw e;}});});const offDay=await listen('day-changed',()=>run(async()=>{fading=true;await new Promise(r=>setTimeout(r,150));await refresh();tomorrowExpanded=false;editId='';selected='';fading=false;rolling=false;}));const offRecovery=await listen('backup-restored',()=>{notice='已从备份恢复数据';setTimeout(()=>notice='',6000);});await invoke('recovery_notice');const offNotes=unlisten;unlisten=()=>{offNotes?.();offItems();offPrepare();offDay();offRecovery();};if(disposed)unlisten();await tick();if(!items.length)itemInput?.focus();if(params.get('new')==='true')await rename();});const timer=setInterval(()=>run(refresh),60000);return()=>{disposed=true;unlisten?.();clearInterval(timer);clearTimeout(undoTimer);clearTimeout(scrollTimer);media.removeEventListener('change',motion);};});
function parts(text:string){return text.split(/(https?:\/\/[^\s<>"，。！？；）】]+)/g).filter(Boolean).map(text=>({text,url:/^https?:\/\//.test(text)}));}
</script>
{#snippet label(item:Item)}
  <span class="item-label">{#each parts(item.content) as part}{#if part.url}<a href={part.text} onclick={(e)=>{e.preventDefault();e.stopPropagation();run(()=>invoke('open_url',{url:part.text}));}}>{part.text}</a>{:else}<button class="text-fragment" onclick={()=>run(()=>edit(item))}>{part.text}</button>{/if}{/each}</span>
  {#if item.carry_days}<span class="carry-badge">顺延 {item.carry_days} 天</span>{/if}
{/snippet}

<svelte:window onpointerdown={(e)=>{if(!(e.target instanceof Element)||!e.target.closest('.item-menu'))context=undefined;}} onkeydown={(e)=>{if(e.key==='Escape'){editing=false;editId='';panel='';selected='';context=undefined;}if((e.key==='Delete'||e.key==='Backspace') && selected && !(e.target instanceof HTMLInputElement) && !(e.target instanceof HTMLTextAreaElement)){e.preventDefault();const item=items.find(i=>i.id===selected);if(item)run(()=>remove(item));}}} />
<main class="note" class:collapsed={note?.collapsed} class:hiding inert={rolling}>
  <header data-tauri-drag-region>
    {#if editing}<input class="title-input" bind:this={titleInput} bind:value={draft} aria-label="便签标题" onblur={()=>run(confirmTitle)} onkeydown={(e)=>{if(e.key==='Enter') {e.preventDefault();run(confirmTitle);}if(e.key==='Escape'){e.preventDefault();editing=false;}}} />
    {:else}<button class="title" ondblclick={rename} title="双击重命名" onpointerdown={dragTitle}>{note?.title??'待办'}</button>{/if}
    <span class="count">{items.filter(i=>!i.done).length}</span><div class="tools">
      <button class:active={note?.pinned} onclick={()=>run(()=>save({pinned:!note?.pinned}))} title="置顶" aria-label="置顶" aria-pressed={note?.pinned??false}><svg viewBox="0 0 20 20" aria-hidden="true"><path d="m7 3 6 0-1 5 3 3H5l3-3-1-5Zm3 8v6" /></svg></button>
      <button class="color" onclick={()=>panel=panel==='palette'?'':'palette'} title="更换颜色" aria-label="更换颜色" aria-expanded={panel==='palette'}><span></span></button>
      <button onclick={hide} title="隐藏便签" aria-label="隐藏便签">−</button>
      <button onclick={()=>panel=panel==='more'?'':'more'} title="更多" aria-label="更多" aria-expanded={panel==='more'}>⋯</button>
    </div>
  </header>
  {#if panel==='palette'}<div class="popover palette" aria-label="便签颜色">{#each palette as color,i}<button style:background={fills[i]} class:selected={note?.color===color} aria-label={names[i]} title={names[i]} onclick={()=>run(async()=>{await save({color});panel='';})}>{note?.color===color?'✓':''}</button>{/each}</div>{/if}
  {#if panel==='more'}<div class="popover menu"><button onclick={()=>run(async()=>{await save({collapsed:!note?.collapsed});panel='';})}>{note?.collapsed?'展开':'折叠'}</button><button onclick={rename}>重命名 <span>双击标题</span></button><button onclick={()=>{panel='confirm';}}>删除便签…</button></div>{/if}
  {#if !note?.collapsed}
  <section class="content" class:scrolling class:fading onscroll={scrolled} aria-label="今天的事项">
    <div class="eyebrow">今天</div>
    <div class="open-list" use:dragHandleZone={{items:openItems,flipDurationMs:reducedMotion?0:150,dragDisabled:pending.length>0}} onconsider={(e)=>openItems=e.detail.items} onfinalize={(e)=>run(()=>reorder(e))}>
      {#each openItems as item (item.id)}
        <div role="group" oncontextmenu={(e)=>itemMenu(e,item)} class="item" class:done={item.done} class:pending={pending.includes(item.id)} class:selected={selected===item.id}>
          <span class="grip" use:dragHandle aria-label="拖动排序" title="拖动排序">⠿</span>
          <button class="check" aria-label={`完成 ${item.content}`} aria-pressed={item.done} onclick={()=>run(()=>toggle(item))}><svg viewBox="0 0 16 16"><path d="m4 8 3 3 5-6" /></svg></button>
          {#if editId===item.id}<textarea bind:this={editInput} bind:value={editText} maxlength="200" rows="2" aria-label="编辑事项" onblur={()=>run(saveEdit)} onkeydown={(e)=>{if(e.key==='Enter'&&!e.isComposing){e.preventDefault();run(saveEdit);}}}></textarea>
          {:else}<div class="item-text">{@render label(item)}</div>{/if}
          <button class="delete-item" aria-label={`删除 ${item.content}`} onclick={()=>run(()=>remove(item))}>×</button>
        </div>
      {/each}
    </div>
    <div class="input-row"><span>＋</span><input bind:this={itemInput} bind:value={entry} maxlength="200" aria-label="添加事项" placeholder="写下今天要做的事…" onkeydown={(e)=>{if(e.key==='Enter'&&!e.isComposing){e.preventDefault();run(add);}}} /></div>
    {#if completed.length}<button class="completed-toggle" aria-expanded={expanded} onclick={()=>expanded=!expanded}><span>{expanded?'⌄':'›'}</span> 已完成 {completed.length}</button>
      {#if expanded}<div class="completed-list">{#each completed as item (item.id)}<div role="group" oncontextmenu={(e)=>itemMenu(e,item)} class="item done"><button class="check" aria-label={`取消完成 ${item.content}`} aria-pressed="true" onclick={()=>run(()=>toggle(item))}><svg viewBox="0 0 16 16"><path d="m4 8 3 3 5-6" /></svg></button>{#if editId===item.id}<textarea bind:this={editInput} bind:value={editText} maxlength="200" aria-label="编辑已完成事项" onblur={()=>run(saveEdit)} onkeydown={(e)=>{if(e.key==='Enter'&&!e.isComposing){e.preventDefault();run(saveEdit);}}}></textarea>{:else}<div class="item-text">{@render label(item)}</div>{/if}<button class="delete-item" aria-label={`删除 ${item.content}`} onclick={()=>run(()=>remove(item))}>×</button></div>{/each}</div>{/if}
    {/if}
    <button class="completed-toggle tomorrow-toggle" aria-expanded={tomorrowExpanded} onclick={()=>tomorrowExpanded=!tomorrowExpanded}><span>{tomorrowExpanded?'⌄':'›'}</span> 明天 <span class="tomorrow-count">{tomorrow.length || ''}</span></button>
    {#if tomorrowExpanded}<div class="tomorrow-list">{#each tomorrow as item (item.id)}<div role="group" oncontextmenu={(e)=>itemMenu(e,item)} class="item" class:done={item.done}>
      <span class="tomorrow-dot">·</span>
      {#if editId===item.id}<textarea bind:this={editInput} bind:value={editText} maxlength="200" aria-label="编辑明天事项" onblur={()=>run(saveEdit)} onkeydown={(e)=>{if(e.key==='Enter'&&!e.isComposing){e.preventDefault();run(saveEdit);}}}></textarea>{:else}<div class="item-text">{@render label(item)}</div>{/if}
      <button class="delete-item" aria-label={`删除 ${item.content}`} onclick={()=>run(()=>remove(item))}>×</button>
    </div>{/each}<div class="input-row"><span>＋</span><input bind:value={tomorrowEntry} maxlength="200" aria-label="添加明天事项" placeholder="留给明天的小事…" onkeydown={(e)=>{if(e.key==='Enter'&&!e.isComposing){e.preventDefault();run(addTomorrow);}}} /></div></div>{/if}
    {#if error}<p role="alert">{error}</p>{/if}
  </section>
  {#if undo || moveUndo}<div class="undo-toast" role="status"><span>{moveUndo?'已移动':'事项已删除'}</span><button onclick={()=>run(restore)}>撤销</button></div>{/if}
  {#if notice}<div class="undo-toast" role="status">{notice}</div>{/if}
  <footer><button class="theme" onclick={()=>run(()=>invoke('update_setting',{key:'appearance',value:document.documentElement.dataset.theme==='dark'?'light':'dark'}))} title="切换浅色 / 深色" aria-label="切换浅色 / 深色">{theme==='dark'?'☼':'☾'}</button></footer>
  {/if}
  {#if panel==='confirm'}<div class="scrim"><div class="confirmation" role="alertdialog" aria-modal="true" aria-label="删除便签"><strong>删除「{note?.title}」？</strong><p>便签将从桌面移除，事项仍保存在本地。</p><div><button onclick={()=>panel=''}>取消</button><button class="danger" onclick={()=>run(()=>invoke('delete_note'))}>删除</button></div></div></div>{/if}
</main>

{#if !note?.collapsed}{#each edges as edge}<button class="resize-edge" style={edge.style} tabindex="-1" aria-label={`Resize ${edge.direction}`} onpointerdown={(e)=>{if(e.button===0)run(()=>getCurrentWindow().startResizeDragging(edge.direction));}}></button>{/each}{/if}

{#if context}
  <div class="popover menu item-menu" style:left={`${context.x}px`} style:top={`${context.y}px`} role="menu" aria-label="事项操作">
    <button role="menuitem" aria-haspopup="menu" aria-expanded={moveExpanded} onclick={()=>moveExpanded=!moveExpanded} onkeydown={(e)=>{if(e.key==='ArrowRight'){e.preventDefault();moveExpanded=true;tick().then(()=>document.querySelector<HTMLButtonElement>('.move-targets button')?.focus());}}}>移动到… <span>{moveExpanded?'⌄':'›'}</span></button>
    {#if moveExpanded}<div class="move-targets" role="menu" aria-label="选择目标便签">
      {#each destinations as target}<button role="menuitem" onclick={()=>run(()=>moveTo(target.id))}><i style:background={fills[palette.indexOf(target.color)]??fills[0]}></i><span>{target.title}</span></button>{:else}<p>没有其他便签</p>{/each}
    </div>{/if}
  </div>
{/if}
