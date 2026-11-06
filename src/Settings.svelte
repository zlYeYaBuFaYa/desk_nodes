<script lang="ts">
 import {onMount} from 'svelte';
 import {invoke} from '@tauri-apps/api/core';
 import {listen} from '@tauri-apps/api/event';
 import type {Settings} from './settings';
 let values=$state<Settings>({}), errors=$state<Settings>({}), message=$state('');
 const shortcuts=[['shortcut_toggle_all','显示 / 隐藏便签'],['shortcut_new_note','新建便签'],['shortcut_open_panel','打开管理面板']];
 async function save(key:string,value:string){try{await invoke('update_setting',{key,value});values[key]=value;errors[key]='';message='';}catch(e){errors[key]=String(e);message=String(e);}}
 function capture(e:KeyboardEvent,key:string){
  const input=e.target as HTMLInputElement;
  if(e.key==='Enter'){e.preventDefault();save(key,input.value.trim());return;}
  if(e.key==='Escape'){input.value=values[key];errors[key]='';return;}
  if(e.key==='Tab'||(!e.ctrlKey&&!e.metaKey&&!e.altKey)||(e.ctrlKey&&!e.shiftKey&&!e.altKey&&['a','c','v','x'].includes(e.key.toLowerCase())))return;
  if(['Control','Shift','Alt','Meta'].includes(e.key))return;
  e.preventDefault();
  const parts=[e.ctrlKey?'Control':'',e.metaKey?'Super':'',e.altKey?'Alt':'',e.shiftKey?'Shift':'',e.code==='Space'?'Space':e.key.length===1?e.key.toUpperCase():e.key].filter(Boolean);
  input.value=parts.join('+');save(key,input.value);
 }
 async function data(importing:boolean){try{message='';await invoke('backup_data',{import:importing});message='操作完成';}catch(e){message=String(e);}}
 onMount(()=>{let disposed=false;let off=()=>{};(async()=>{const unlisten=await listen<Settings>('settings-changed',e=>values=e.payload);if(disposed)unlisten();else off=unlisten;values=await invoke('get_settings');})().catch(e=>message=String(e));return()=>{disposed=true;off();};});
</script>
<section class="panel-main settings-main">
 <div class="panel-heading"><h1>设置</h1><span class="settings-version">DeskNodes · V0.2</span></div><p class="subtitle">按自己的节奏，安放每一天。</p>
 {#if values.appearance}
 <div class="settings-group"><h2>日常</h2>
 {#each [['autostart','开机自启','登录电脑后，让便签静静等候。'],['auto_carry','未完成事项自动顺延','把未完成的小事，带到新的一天。']] as [key,label,hint]}
 <div class="setting-row"><div><label for={key}>{label}</label><p>{errors[key]||values[key+'_status']||hint}</p></div><button id={key} aria-label={label} class="visibility" class:on={values[key]==='1'} role="switch" aria-checked={values[key]==='1'} onclick={()=>save(key,values[key]==='1'?'0':'1')}><span></span></button></div>{/each}
 <div class="setting-row"><div><label for="rollover_hour">换日时间</label><p>在这个时间，开始新的一天。</p></div><select id="rollover_hour" value={values.rollover_hour} onchange={e=>save('rollover_hour',e.currentTarget.value)}>{#each [0,1,2,3,4,5,6] as hour}<option value={String(hour)}>{String(hour).padStart(2,'0')}:00</option>{/each}</select></div></div>
 <div class="settings-group"><h2>外观</h2><div class="setting-row"><label for="appearance">外观</label><select id="appearance" value={values.appearance} onchange={e=>save('appearance',e.currentTarget.value)}><option value="system">跟随系统</option><option value="light">浅色</option><option value="dark">深色</option></select></div>
 <div class="setting-row"><label for="note_opacity">便签透明度</label><div class="slider-control"><input id="note_opacity" type="range" min="70" max="100" value={values.note_opacity} oninput={e=>save('note_opacity',e.currentTarget.value)}/><output>{values.note_opacity}%</output></div></div>
 <div class="setting-row"><label for="font_size">字号</label><select id="font_size" value={values.font_size} onchange={e=>save('font_size',e.currentTarget.value)}><option value="small">小 · 13</option><option value="medium">中 · 14</option><option value="large">大 · 16</option></select></div></div>
 <div class="settings-group"><h2>全局快捷键 <span>输入组合键，按回车保存</span></h2>{#each shortcuts as [key,label]}<div class="setting-row"><label for={key}>{label}</label><div class="shortcut-control"><input id={key} class:invalid={!!(errors[key]||values[key+'_status'])} aria-invalid={!!(errors[key]||values[key+'_status'])} aria-describedby={key+'-error'} value={values[key]} onkeydown={e=>capture(e,key)} onblur={e=>{if(e.currentTarget.value!==values[key])save(key,e.currentTarget.value.trim());}} placeholder="按下组合键"/><p id={key+'-error'} class="shortcut-error">{errors[key]||values[key+'_status']||''}</p></div></div>{/each}</div>
 <div class="settings-group data-settings"><h2>数据 <span>只保存在这台电脑上</span></h2><div class="data-buttons"><button onclick={()=>data(false)}>导出备份…</button><button onclick={()=>data(true)}>导入备份…</button><button onclick={()=>invoke('open_data_dir').catch(e=>message=String(e))}>打开数据目录 ↗</button></div></div>
 {/if}<p class="settings-message" role="status">{message}</p>
</section>
