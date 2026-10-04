import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {VO, VOICE, MUSIC, SFX, FPS} from '../src/timeline.ts';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const env = {};
try {
  for (const line of fs.readFileSync(path.join(root, '.env'), 'utf8').split('\n')) {
    const m = line.match(/^\s*([A-Z_]+)\s*=\s*(.*?)\s*$/);
    if (m) env[m[1]] = m[2].replace(/^['"]|['"]$/g, '');
  }
} catch {}
const KEY = env.ELEVENLABS_API_KEY;
if (!KEY) { console.error('ELEVENLABS_API_KEY missing in .env'); process.exit(1); }
const VOICE_ID = env.VOICE_ID || VOICE.defaultVoiceId;
const API = 'https://api.elevenlabs.io';
const out = (...p) => path.join(root, ...p);
const sha = (o) => crypto.createHash('sha256').update(JSON.stringify(o)).digest('hex');
let apiCalls = 0;

async function call(url, body, tries = 3) {
  for (let i = 0; i < tries; i++) {
    apiCalls++;
    let res;
    try {
      res = await fetch(url, {method: 'POST', headers: {'xi-api-key': KEY, 'Content-Type': 'application/json'}, body: JSON.stringify(body)});
    } catch (e) {
      if (i < tries - 1) { await new Promise((r) => setTimeout(r, 1500 * (i + 1))); continue; }
      throw new Error('network error: ' + e.message);
    }
    if (res.ok) return res;
    const txt = (await res.text()).slice(0, 400);
    if ((res.status === 429 || res.status >= 500) && i < tries - 1) { await new Promise((r) => setTimeout(r, 2000 * (i + 1))); continue; }
    throw new Error(`HTTP ${res.status}: ${txt}`);
  }
}

async function pool(items, n, fn) {
  let i = 0;
  await Promise.all(Array.from({length: n}, async () => { while (i < items.length) await fn(items[i++]); }));
}

function analyse(line, al) {
  const {characters: ch, character_start_times_seconds: st, character_end_times_seconds: en} = al;
  let first = ch.findIndex((c) => c.trim() !== '');
  let last = ch.length - 1; while (last > 0 && ch[last].trim() === '') last--;
  const trimStartSec = Math.max(0, st[first] - 0.02);
  const speechEndSec = en[last];
  const durSec = speechEndSec - trimStartSec + 0.15;
  const slotFrames = line.end - line.at;
  const budget = slotFrames - 10;
  const raw = Math.ceil(durSec * FPS);
  let rate = 1, overrun = false;
  if (raw > budget) {
    rate = Math.min(VOICE.maxSpeed ?? 1.1, 1.1, raw / budget);
    if (Math.ceil(durSec * FPS / rate) > budget) overrun = true;
  }
  const words = [];
  let cur = null;
  for (let i = first; i <= last; i++) {
    if (ch[i].trim() === '') { cur = null; continue; }
    if (!cur) { cur = {word: '', frame: Math.floor(((st[i] - trimStartSec) / rate) * FPS)}; words.push(cur); }
    cur.word += ch[i];
  }
  return {
    file: `audio/vo/${line.id}.mp3`,
    trimStartFrames: Math.floor(trimStartSec * FPS),
    durationFrames: Math.ceil((durSec * FPS) / rate),
    playbackRate: Math.round(rate * 1000) / 1000,
    slotFrames, budgetFrames: budget, overrun, words,
  };
}

const manifest = {vo: {}, music: {}, sfx: {}};

await pool(VO, 2, async (line) => {
  const text = line.tts ?? line.text;
  const hash = sha({text, VOICE_ID, model: VOICE.model, settings: VOICE.settings});
  const jf = out('public/audio/vo', line.id + '.json');
  const mf = out('public/audio/vo', line.id + '.mp3');
  try {
    let data;
    try { const j = JSON.parse(fs.readFileSync(jf, 'utf8')); if (j.hash === hash && fs.existsSync(mf)) data = j; } catch {}
    if (!data) {
      const res = await call(`${API}/v1/text-to-speech/${VOICE_ID}/with-timestamps?output_format=mp3_44100_128`,
        {text, model_id: VOICE.model, voice_settings: VOICE.settings});
      const j = await res.json();
      fs.writeFileSync(mf, Buffer.from(j.audio_base64, 'base64'));
      data = {hash, alignment: j.alignment};
      fs.writeFileSync(jf, JSON.stringify(data));
    }
    manifest.vo[line.id] = analyse(line, data.alignment);
  } catch (e) { manifest.vo[line.id] = {error: e.message}; }
});

// Music
{
  const body = {
    model_id: 'music_v1',
    composition_plan: {
      positive_global_styles: [MUSIC.positive], negative_global_styles: [MUSIC.negative],
      sections: MUSIC.sections.map((s) => ({section_name: s.name, positive_local_styles: [s.styles], negative_local_styles: [], duration_ms: s.ms, lines: []})),
    },
    respect_sections_durations: true,
  };
  const hash = sha(body);
  const jf = out('public/audio/music.json'), mf = out('public/audio/music.mp3');
  try {
    let cached = false;
    try { cached = JSON.parse(fs.readFileSync(jf, 'utf8')).hash === hash && fs.existsSync(mf); } catch {}
    if (!cached) {
      const res = await call(`${API}/v1/music?output_format=mp3_44100_128`, body, 2);
      fs.writeFileSync(mf, Buffer.from(await res.arrayBuffer()));
      fs.writeFileSync(jf, JSON.stringify({hash}));
    }
    manifest.music = {ok: true, file: 'audio/music.mp3'};
  } catch (e) { manifest.music = {ok: false, error: e.message}; }
}

// SFX
const sfxDur = {whoosh: 0.8, pop: 0.5, thunk: 0.6, ticks: 1.2};
for (const [key, text] of Object.entries(SFX)) {
  const f = out('public/audio/sfx', key + '.mp3');
  const dur = sfxDur[key] ?? 1;
  try {
    const hash = sha({text, dur});
    const jf = out('public/audio/sfx', key + '.json');
    let cached = false;
    try { cached = JSON.parse(fs.readFileSync(jf, 'utf8')).hash === hash && fs.existsSync(f); } catch {}
    if (!cached) {
      const res = await call(`${API}/v1/sound-generation?output_format=mp3_44100_128`, {text, duration_seconds: dur}, 2);
      fs.writeFileSync(f, Buffer.from(await res.arrayBuffer()));
      fs.writeFileSync(jf, JSON.stringify({hash}));
    }
    manifest.sfx[key] = {ok: true, file: `audio/sfx/${key}.mp3`, durationFrames: Math.ceil(dur * FPS)};
  } catch (e) { manifest.sfx[key] = {ok: false, error: e.message}; }
}

fs.mkdirSync(out('src/generated'), {recursive: true});
fs.writeFileSync(out('src/generated/audio-manifest.json'), JSON.stringify(manifest, null, 2));
console.log('API calls:', apiCalls);
for (const [id, v] of Object.entries(manifest.vo)) console.log(id, v.error ? 'ERROR ' + v.error : `${v.durationFrames}f / budget ${v.budgetFrames} rate ${v.playbackRate}${v.overrun ? ' OVERRUN' : ''}`);
console.log('music', JSON.stringify(manifest.music));
for (const [k, v] of Object.entries(manifest.sfx)) console.log('sfx', k, v.ok ? 'ok' : v.error);
