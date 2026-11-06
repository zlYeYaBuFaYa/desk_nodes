<script lang="ts">
  import { getCurrentWindow } from '@tauri-apps/api/window';
  const params = new URLSearchParams(location.search);
  const id = Number(params.get('id') ?? 0);
  const palette = ['mist', 'sage', 'apricot', 'lilac', 'butter', 'blush', 'celadon', 'stone'];
  const titles = ['A little focus', 'Life, slowly', 'Ideas to keep', 'Make something', 'Small joys'];
  const lines = [
    ['Leave room for deep work', 'One meaningful thing at a time', 'A quiet desk, a clearer mind'],
    ['Take a walk after lunch', 'Pick up something fresh', 'Call someone you miss'],
    ['A place for the next spark', 'Collect the unexpected', 'Let the idea breathe'],
    ['Sketch the first version', 'Keep it simple and useful', 'Make space for a little play'],
    ['Open the window', 'Put on a favorite record', 'Notice the good things']
  ];
  let color = $state(palette.includes(params.get('color') ?? '') ? params.get('color')! : 'mist');
  let pinned = $state(false);
  let theme = $state(params.get('theme') ?? 'system');
  let error = $state('');
  $effect(() => {
    document.documentElement.dataset.color = color;
    document.documentElement.dataset.theme = theme;
  });
  async function pin() {
    try { await getCurrentWindow().setAlwaysOnTop(!pinned); pinned = !pinned; error = ''; }
    catch (e) { error = String(e); }
  }
  async function hide() {
    try { await getCurrentWindow().hide(); } catch (e) { error = String(e); }
  }
</script>

<main class="note">
  <header data-tauri-drag-region>
    <span class="title" data-tauri-drag-region>{titles[id % 5]}</span>
    <button class:active={pinned} onclick={pin} title="Always on top" aria-label="Always on top" aria-pressed={pinned}>
      <svg viewBox="0 0 20 20" aria-hidden="true"><path d="m7 3 6 0-1 5 3 3H5l3-3-1-5Zm3 8v6" /></svg>
    </button>
    <button class="color" onclick={() => color = palette[(palette.indexOf(color) + 1) % 8]} title="Cycle note color" aria-label="Cycle note color"><span></span></button>
    <button onclick={hide} title="Hide note" aria-label="Hide note">−</button>
  </header>
  <section class="content" aria-label="Sample note content">
    <div class="eyebrow">TODAY <span>•</span> {String(id + 1).padStart(2, '0')}</div>
    <p class="intro">{['Find your own rhythm.', 'For the everyday things.', 'Good ideas start small.', 'From a thought to a thing.', 'There is time for this.'][id % 5]}</p>
    <ul>{#each lines[id % 5] as line}<li><span class="check" aria-hidden="true"></span><span>{line}</span></li>{/each}</ul>
    <p class="placeholder">A little space for what comes next…</p>
    {#if error}<p role="alert">{error}</p>{/if}
  </section>
  <footer><span>DeskNodes <span class="prototype">/ prototype</span></span><button class="theme" onclick={() => theme = theme === 'dark' ? 'light' : 'dark'} title="Toggle light / dark appearance" aria-label="Toggle light / dark appearance">{theme === 'dark' ? '☼' : '☾'}</button></footer>
</main>
