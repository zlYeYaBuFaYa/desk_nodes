import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
export type Settings = Record<string,string>;
export function applySettings(values:Settings) {
 document.documentElement.dataset.theme=values.appearance;
 document.documentElement.style.setProperty('--body-size',({small:'13px',medium:'14px',large:'16px'} as Record<string,string>)[values.font_size]??'14px');
 document.documentElement.style.setProperty('--note-opacity',String(Number(values.note_opacity)/100));
}
export async function watchSettings(){const off=await listen<Settings>('settings-changed',e=>applySettings(e.payload));try{applySettings(await invoke<Settings>('get_settings'));}catch(e){off();throw e;}return off;}
