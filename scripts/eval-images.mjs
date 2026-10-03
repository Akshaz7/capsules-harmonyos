#!/usr/bin/env node
// Photo -> capsule eval (T5-4). Runs the 10 synthetic photos in scripts/eval-images/ through the app's own
// cloud photo path (core/providers/CloudVision.ets: provider transcribes the photo, then the shared-text
// converters, then the cloud capsule model), once per provider in config.local.json, and checks each capsule.
//
// With --ondevice <file.jsonl> (results of the on-device run on the emulator, one {"image","result"} per line)
// it also reports the full chain: the on-device result when it built a capsule, else the cloud result.
//
// The photos are synthetic (rendered text, scripts/eval-images/render.py), not camera photos.
//
// Usage (from the repo root):
//   node scripts/eval-images.mjs [--only mistral] [--model pixtral-12b-latest] [--vision-model pixtral-12b-latest] [--ondevice results.jsonl [--no-cloud]] [--out results.json]
// Needs Node 18+ and network access; downloads esbuild through npx on first run.
// Never prints API keys. config.local.json is git-ignored; never commit it.

import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const core = join(root, 'entry/src/main/ets/core');
const imagesDir = join(root, 'scripts/eval-images');

function arg(name) {
  const i = process.argv.indexOf(name);
  return i > 0 ? process.argv[i + 1] : undefined;
}

const work = mkdtempSync(join(tmpdir(), 'hy-img-'));
const entry = join(work, 'entry.ts');
writeFileSync(entry, [
  `export { CapsuleModel } from ${JSON.stringify(join(core, 'CapsuleModel'))};`,
  `export { createProvider, parseModelConfigs } from ${JSON.stringify(join(core, 'ModelProvider'))};`,
  `export { allComponents, initialState, renderTemplate } from ${JSON.stringify(join(core, 'CapsuleProgram'))};`,
  `export { generateFromImageWith, imageMime } from ${JSON.stringify(join(core, 'providers/CloudVision'))};`
].join('\n'));
const bundle = join(work, 'core.mjs');
execFileSync('npx', ['-y', 'esbuild@0.25.10', entry, '--bundle', '--format=esm', '--platform=node',
  '--loader:.ets=ts', '--resolve-extensions=.ets,.ts,.js', `--outfile=${bundle}`, '--log-level=warning'],
  { stdio: 'inherit' });
const lib = await import(pathToFileURL(bundle).href);

let configText = '{"providers":{}}';
try {
  configText = readFileSync(join(root, 'config.local.json'), 'utf8');
} catch {
  if (!process.argv.includes('--no-cloud')) {
    console.error('No config.local.json in the repo root. See CLAUDE.md.');
    process.exit(1);
  }
}
const parsed = lib.parseModelConfigs(configText);
if (parsed.error && !process.argv.includes('--no-cloud')) {
  console.error(parsed.error);
  process.exit(1);
}
const only = arg('--only');
// --model overrides the model of every selected provider (e.g. --only mistral --model pixtral-12b-latest).
const modelOverride = arg('--model');
const configs = (parsed.configs ?? []).filter((c) => only === undefined || c.provider === only)
  .map((c) => (modelOverride === undefined ? c : { ...c, model: modelOverride }));
// --vision-model overrides only the model that reads the photo; the capsule is still built by the configured model.
const visionModel = arg('--vision-model');

const sleep = (ms) => new Promise((done) => setTimeout(done, ms));

class FetchTransport {
  async post(url, headers, body, timeoutMs) {
    for (let attempt = 0; ; attempt++) {
      const resp = await fetch(url, { method: 'POST', headers, body, signal: AbortSignal.timeout(timeoutMs) });
      if (resp.status !== 429 || attempt === 4) {
        return { status: resp.status, body: await resp.text() };
      }
      await sleep(Math.min(Number(resp.headers.get('retry-after') ?? 0) * 1000 || 5000 * 2 ** attempt, 60000));
    }
  }
}

// ---- Checks: each gets the validated capsule and returns '' if correct, else a short reason ----

const flat = (c) => lib.allComponents(c.ui);
const ofType = (c, t) => flat(c).filter((x) => x.type === t);
const need = (ok, reason) => (ok ? '' : reason);
const first = (...reasons) => reasons.find((r) => r !== '') ?? '';
const text = (c) => JSON.stringify(c).toLowerCase();
const mentions = (c, words) => {
  const missing = words.filter((w) => !text(c).includes(w));
  return need(missing.length === 0, `misses ${missing.join(', ')}`);
};
const timerMinutes = (c) => ofType(c, 'timer').map((t) => t.minutes);
const hasTimers = (c, mins) => {
  const got = timerMinutes(c);
  const missing = mins.filter((m) => !got.includes(m));
  return need(missing.length === 0, `timers ${got.join(',')}`);
};
const checklistHas = (c, words) => {
  const items = ofType(c, 'checklist').flatMap((l) => l.items.map((i) => i.toLowerCase()));
  const missing = words.filter((w) => !items.some((i) => i.includes(w)));
  return need(missing.length === 0, `checklist misses ${missing.join(', ')}`);
};
/** Every display rendered with the initial state. */
const shown = (c) => {
  const state = lib.initialState(c);
  return ofType(c, 'display').map((d) => lib.renderTemplate(c, state, d.text)).join(' | ');
};
const shows = (c, expected) => need(expected.every((e) => shown(c).includes(e)), `display "${shown(c)}"`);

const IMAGES = [
  ['receipt.jpg', 'cafe receipt, total 64.50 zł', (c) => first(mentions(c, ['64.5']), need(ofType(c, 'input').length > 0 ||
    ofType(c, 'display').length > 0, 'no bill split'))],
  ['restaurant_bill.jpg', 'bill €67.50 split between 4', (c) => shows(c, ['16.88'])],
  ['recipe.jpg', 'recipe: boil 9, simmer 15, bake 10, rest 2 min', (c) => hasTimers(c, [9, 15, 10])],
  ['whiteboard_todo.jpg', 'whiteboard to-do list', (c) => checklistHas(c, ['anna', 'dentist', 'bike', 'rent'])],
  ['shopping_list.jpg', 'handwritten shopping list', (c) => checklistHas(c, ['milk', 'eggs', 'bread', 'apples', 'coffee'])],
  ['workout.jpg', 'leg-day workout plan', (c) => checklistHas(c, ['squat', 'lunge', 'plank', 'burpee'])],
  ['timetable.jpg', 'weekly class timetable', (c) => mentions(c, ['maths', 'physics', 'english', 'chemistry', 'history'])],
  ['medicine.jpg', 'ibuprofen: 1 tablet every 8 hours', (c) => first(mentions(c, ['ibuprofen']),
    need(timerMinutes(c).includes(480) || /8 ?h|8 hours|every 8/.test(text(c)), 'no 8-hour interval'))],
  ['scoreboard.jpg', 'ping pong Tom vs Ana', (c) => first(mentions(c, ['tom', 'ana']), need(ofType(c, 'button').length >= 2 ||
    ofType(c, 'counter').length >= 2, 'no way to score both'))],
  ['sticky_note.jpg', 'sticky note: water the plants every 3 days', (c) => mentions(c, ['plant', '3'])]
];

function judge(r, check) {
  if (!r.ok) {
    return { valid: false, correct: false, verdict: `INVALID  ${r.error}${r.needsCloud ? ' (needsCloud)' : ''}` };
  }
  let reason;
  try {
    reason = check(r.capsule);
  } catch (e) {
    reason = `check crashed: ${e?.message ?? e}`;
  }
  return { valid: true, correct: reason === '', verdict: reason === '' ? 'correct' : `valid, wrong: ${reason}` };
}

function image(name) {
  const path = join(imagesDir, name);
  return { path, mime: lib.imageMime(path), readBase64: () => readFileSync(path).toString('base64') };
}

const onDevice = new Map();
const onDeviceFile = arg('--ondevice');
if (onDeviceFile !== undefined) {
  for (const line of readFileSync(onDeviceFile, 'utf8').split('\n').filter((l) => l.trim().length > 0)) {
    const row = JSON.parse(line);
    if (row.image !== undefined && row.result !== undefined) {
      onDevice.set(row.image, row.result);
    }
  }
}

const results = [];
const summary = [];
if (onDevice.size > 0) {
  let valid = 0;
  let correct = 0;
  console.log('\n== on-device (LFM2-VL-450M, from the emulator run) ==');
  for (const [name, what, check] of IMAGES) {
    const r = onDevice.get(name) ?? { ok: false, error: 'not run' };
    const j = judge(r, check);
    valid += j.valid ? 1 : 0;
    correct += j.correct ? 1 : 0;
    console.log(`  ${j.verdict.padEnd(9).substring(0, 110)}  ${what}`);
  }
  summary.push(`on-device: valid ${valid}/${IMAGES.length}, correct ${correct}/${IMAGES.length}`);
}

// Device chain (photo-eval rows from scripts/phone-photo-eval.sh carry "chain": the app's result with the cloud allowed).
const deviceChain = [...onDevice.keys()].length > 0 && onDeviceFile !== undefined ?
  readFileSync(onDeviceFile, 'utf8').split('\n').filter((l) => l.trim().length > 0).map((l) => JSON.parse(l))
    .filter((row) => row.chain !== undefined) : [];
if (deviceChain.length > 0) {
  let valid = 0;
  let correct = 0;
  console.log('\n== device chain (on the phone, cloud allowed) ==');
  for (const [name, what, check] of IMAGES) {
    const row = deviceChain.find((x) => x.image === name);
    const j = judge(row?.chain ?? { ok: false, error: 'not run' }, check);
    valid += j.valid ? 1 : 0;
    correct += j.correct ? 1 : 0;
    console.log(`  ${j.verdict.padEnd(9).substring(0, 110)}  ${what}  [${row?.chain?.origin ?? '-'}]`);
  }
  summary.push(`device chain: valid ${valid}/${IMAGES.length}, correct ${correct}/${IMAGES.length}`);
}

const transport = new FetchTransport();
for (const config of process.argv.includes('--no-cloud') ? [] : configs) {
  const model = new lib.CapsuleModel(lib.createProvider(config, transport));
  let valid = 0;
  let correct = 0;
  let chainValid = 0;
  let chainCorrect = 0;
  let totalMs = 0;
  console.log(`\n== cloud ${config.provider} (${config.model}) ==`);
  for (const [name, what, check] of IMAGES) {
    await sleep(1000);
    const started = Date.now();
    let r;
    try {
      const visionConfig = visionModel === undefined ? config : { ...config, model: visionModel };
      r = await lib.generateFromImageWith(image(name), null, null, null, [model], [visionConfig], transport,
        { allowCloud: true, allowNonEu: true, cloudOnly: true });
    } catch (e) {
      r = { ok: false, error: String(e?.message ?? e), details: [] };
    }
    const ms = Date.now() - started;
    totalMs += ms;
    const j = judge(r, check);
    valid += j.valid ? 1 : 0;
    correct += j.correct ? 1 : 0;
    const local = onDevice.get(name);
    const chain = local !== undefined && local.ok ? judge(local, check) : j;
    chainValid += chain.valid ? 1 : 0;
    chainCorrect += chain.correct ? 1 : 0;
    console.log(`${String(ms).padStart(6)} ms  ${j.verdict.padEnd(9).substring(0, 110)}  ${what}`);
    results.push({ provider: config.provider, model: config.model, image: name, ok: r.ok, origin: r.origin,
      verdict: j.verdict, ms, capsule: r.capsule });
  }
  summary.push(`cloud ${config.provider}: valid ${valid}/${IMAGES.length}, correct ${correct}/${IMAGES.length}, ` +
    `avg ${Math.round(totalMs / IMAGES.length)} ms`);
  if (onDevice.size > 0) {
    summary.push(`on-device then cloud ${config.provider} (chain): valid ${chainValid}/${IMAGES.length}, ` +
      `correct ${chainCorrect}/${IMAGES.length}`);
  }
}

console.log('\n== Summary ==');
summary.forEach((s) => console.log(s));
const out = arg('--out');
if (out !== undefined) {
  writeFileSync(out, JSON.stringify(results, null, 2));
  console.log(`Details written to ${out}`);
}
