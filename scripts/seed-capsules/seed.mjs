#!/usr/bin/env node
// Generates the built-in template library with the cloud model (Anthropic, key from the git-ignored root
// config.local.json), validates every template with the app's own validator and writes:
//   entry/src/main/resources/rawfile/templates/library.json   (packed into the .hap, read by TemplateLibrary)
//   scripts/seed-capsules/marketplace-seed.json               (same templates, slots filled with their defaults,
//                                                               as [{id, title, category, tags, language, capsule}])
//
// Each template is a capsule with "@{slot}" placeholders (see core/templates/TemplateLibrary.ets). A template is
// kept only if it validates filled with its defaults AND with sample values; one retry with the validator errors,
// then it is dropped. The hand-written core/templates/CoreTemplates.ets entries are always included.
//
// Usage (from the repo root):
//   node scripts/seed-capsules/seed.mjs [--only games,timers] [--concurrency 4] [--check]
// --check skips generation and only re-validates the current library.json (exit 1 if anything is invalid).
// --rebuild skips generation: refreshes the core templates in library.json and rewrites marketplace-seed.json.
// Needs Node 18+; downloads esbuild through npx on first run. Never prints the API key.

import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const core = join(root, 'entry/src/main/ets/core');
const LIBRARY = join(root, 'entry/src/main/resources/rawfile/templates/library.json');
const MARKETPLACE = join(root, 'scripts/seed-capsules/marketplace-seed.json');

function arg(name) {
  const i = process.argv.indexOf(name);
  return i > 0 ? process.argv[i + 1] : undefined;
}

// ---- Bundle the app's own core code ----

const work = mkdtempSync(join(tmpdir(), 'hy-seed-'));
writeFileSync(join(work, 'entry.ts'), [
  `export { SCHEMA_TEXT } from ${JSON.stringify(join(core, 'CapsuleModel'))};`,
  `export { validateCapsule } from ${JSON.stringify(join(core, 'CapsuleValidator'))};`,
  `export * from ${JSON.stringify(join(core, 'templates/TemplateLibrary'))};`,
  `export { CORE_TEMPLATES } from ${JSON.stringify(join(core, 'templates/CoreTemplates'))};`
].join('\n'));
execFileSync('npx', ['-y', 'esbuild@0.25.10', join(work, 'entry.ts'), '--bundle', '--format=esm', '--platform=node',
  '--loader:.ets=ts', '--resolve-extensions=.ets,.ts,.js', `--outfile=${join(work, 'core.mjs')}`, '--log-level=warning'],
{ stdio: 'inherit' });
const lib = await import(pathToFileURL(join(work, 'core.mjs')).href);

// ---- Validation ----

function sampleValues(t) {
  const v = {};
  t.slots.forEach((s, i) => {
    if (s.kind === 'number') v[s.name] = (typeof s.default === 'number' ? s.default : 1) + 3;
    else if (s.kind === 'list') v[s.name] = ['Alpha', 'Beta item', 'Gamma'];
    else v[s.name] = `Ann${i}`;
  });
  return v;
}

/** Returns validator errors for a template ([] = valid). */
function check(t) {
  const errors = [];
  if (!/^[a-z0-9][a-z0-9-]{1,40}$/.test(t.id ?? '')) errors.push('id must be lowercase-kebab-case');
  for (const f of ['name', 'description']) if (typeof t[f] !== 'string' || t[f].length === 0) errors.push(`missing ${f}`);
  if (!Array.isArray(t.tags) || t.tags.length < 3) errors.push('needs at least 3 tags');
  if ((t.language ?? 'en') !== 'en') errors.push('templates are English only');
  if (/[^\x00-\x7f]/.test(JSON.stringify([t.tags, t.slots.map((s) => s.hints ?? [])]))) errors.push('tags and hints must be English');
  if (!Array.isArray(t.slots)) return errors.concat('slots must be an array');
  const json = JSON.stringify(t.capsule ?? null);
  for (const s of t.slots) {
    if (!['text', 'number', 'list'].includes(s.kind)) errors.push(`slot ${s.name}: bad kind`);
    if (s.kind === 'number' && typeof s.default !== 'number') errors.push(`slot ${s.name}: default must be a number`);
    if (s.kind === 'list' && !Array.isArray(s.default)) errors.push(`slot ${s.name}: default must be an array`);
    if (s.kind === 'text' && typeof s.default !== 'string') errors.push(`slot ${s.name}: default must be text`);
    if (!json.includes(`@{${s.name}}`)) errors.push(`slot ${s.name} is not used in the capsule`);
  }
  if (errors.length > 0 || typeof t.capsule !== 'object') return errors;
  for (const [label, values] of [['defaults', {}], ['sample values', sampleValues(t)]]) {
    const filled = lib.applySlots(t, values);
    if (filled.includes('@{')) errors.push(`${label}: unknown placeholder left`);
    const v = lib.validateCapsule(filled);
    if (!v.ok) errors.push(...v.errors.map((e) => `${label}: ${e}`));
  }
  return errors;
}

// ---- What to generate ----

const IDEAS = {
  games: [
    'darts 501 countdown scorer for two players (subtract each throw, bust if below zero)',
    'table tennis / ping-pong scoreboard to 11, win by 2, serve switch every 2 points',
    'badminton scoreboard to 21 for two players', 'volleyball set scoreboard to 25 for two teams with sets won',
    'basketball scoreboard with +1 +2 +3 buttons for two teams', 'football (soccer) match score for two teams',
    'padel / squash scoreboard for two players', 'card game scores for 4 players with rounds (rummy, uno)',
    'board game turn tracker for up to 4 players showing whose turn it is', 'scrabble score keeper for 2 players',
    'bowling frame and total score tracker for one player', 'golf scorecard: strokes per hole for 9 holes with total',
    'chess clock: two timers, tapping one side pauses it and starts the other', 'cornhole / bean bag score to 21',
    'poker chip counter per player with buy-in input', 'billiards / pool rack wins for two players',
    'quiz night team scores for 3 teams', 'rock paper scissors best-of tally for two players'
  ],
  timers: [
    'cooking timers: pasta, sauce and garlic bread with start all', 'soft / medium / hard boiled egg timers',
    'interval training: work and rest timers with rounds', 'tabata 20s/10s style rounds counter with timers',
    'tea steeping timers: green, black, herbal', 'nap timer 20 minutes', 'meditation timer with a gong notification',
    'plank challenge timer', 'laundry washer and dryer timers', 'baking timer for bread rise and bake',
    'screen break 20-20-20 eye timer', 'stretching routine with 3 stretch timers', 'parking meter timer',
    'presentation / speech timer with 1 minute warning', 'kids bedtime routine timers (bath, story, lights out)'
  ],
  calculators: [
    'tip calculator: bill and tip percent, shows tip and total', 'bill split with tip among people',
    'kilometres to miles converter', 'celsius to fahrenheit converter', 'kilograms to pounds converter',
    'centimetres to feet and inches converter', 'cooking units: cups to millilitres and grams of flour',
    'fuel cost of a trip: distance, consumption per 100 km, price per litre', 'discount / sale price calculator',
    'BMI calculator with category', 'percentage calculator (x% of y)', 'running pace calculator (time and distance)',
    'unit price comparison of two products', 'VAT calculator with 23% default', 'age in days/weeks calculator from years',
    'recipe scaler: servings from N to M multiplies ingredient amounts', 'loan monthly payment simple calculator'
  ],
  quizzes: [
    'times-tables quiz with score', 'capital cities quiz (5 questions, multiple choice buttons)',
    'foreign vocabulary flashcards with know / don\'t know counts', 'true or false science quiz',
    'flag / country guess quiz with score', 'spelling practice self-check list with score'
  ],
  habits: [
    'daily habit streak counter (did it today / missed resets)', 'drink water glasses tracker with goal',
    'reading pages tracker with daily goal', 'no-sugar day streak', 'morning routine checklist',
    'evening routine checklist', 'vitamins / medication taken checklist morning and evening',
    'gratitude journal: add three good things list', 'mood tracker with 5 mood buttons and counts',
    'sleep hours log with weekly average', 'steps goal tracker with input'
  ],
  fitness: [
    'sets and reps tracker for an exercise (sets of N reps)', 'squat counter with goal', 'sit-up counter',
    'gym workout checklist (warm up, bench, squat, deadlift)', 'running laps counter', 'jumping jacks counter',
    'weight lifting: weight input and reps with total volume', 'push-up challenge day tracker 30 days',
    'motion step counter while walking', 'pull-up counter with personal best'
  ],
  cooking: [
    'shopping list where I can add and remove items', 'pancake recipe ingredient checklist',
    'meal plan for the week checklist', 'pizza dough recipe timers (knead, rise, bake)', 'grill / BBQ flip timers',
    'calorie counter with add food calories and daily goal', 'coffee brewing: bloom and brew timers'
  ],
  study: [
    'exam revision checklist of topics', 'homework tracker list', 'study session counter with hours goal',
    'grade average calculator for 5 grades', 'language learning words learned counter',
    'reading list of books to tick off'
  ],
  money: [
    'monthly budget: income minus expenses shows what is left', 'savings goal tracker with deposits',
    'expense log: add amounts, shows total', 'pocket money / allowance tracker for a kid',
    'shared flat expenses split between flatmates', 'currency-free price per person for a group trip'
  ],
  household: [
    'cleaning chores checklist', 'weekly chores rota for flatmates', 'plant watering checklist',
    'packing list for a trip', 'moving house checklist', 'baby feeding and diaper counters',
    'dog walk counter and feeding checklist', 'grocery pantry restock checklist', 'leaving home checklist (keys, wallet)'
  ]
};

const TEMPLATE_RULES = `You write TEMPLATES for a built-in library of tiny phone apps ("capsules"). A template is a capsule
whose user-specific parts are SLOTS, written as placeholders "@{slotName}" inside the capsule JSON:
- number slot: the whole JSON string "@{name}" is replaced by a number, e.g. "minutes": "@{work}" or
  "initial": "@{goal}"; inside a longer string it is written in place, e.g. an expression "n >= @{goal}" or a label.
- text slot: written in place inside strings, e.g. "label": "Point @{player1}" or 'Advantage @{player1}' inside an
  expression's quoted text. Never use a text slot as a bare expression or v1 name.
- list slot: the whole array element "@{items}" is replaced by the items, e.g. "items": ["@{items}"] in a
  checklist or "initial": ["@{items}"] for a list state var.
Use 0-3 slots, only for what a user would naturally say in a request: player or team names (text: player1,
player2, ...), durations in minutes and goals (number), list items (list). Every slot must appear in the capsule.

Reply with ONE JSON array, nothing else. Each element:
{ "id": kebab-case, "name": short English title, "description": one sentence,
  "category": one of games, timers, calculators, quizzes, habits, fitness, cooking, study, money, household,
  "language": "en",
  "tags": 12-25 English search words: synonyms and the words people type ("scoreboard", "score", "counter"),
  "slots": [ { "name": letters only, "kind": "text" | "number" | "list", "default": value, "hints"?: [words that
    tie a number to this slot, e.g. ["break","rest"]] } ],
  "capsule": the capsule JSON object with placeholders }

The capsule must be valid for this schema once placeholders are filled:
${lib.SCHEMA_TEXT}

Rules for capsules:
- "permissions" lists exactly what is needed: timers and timer actions need "reminders", motion counters need
  "motion", notify:<text> needs "notifications".
- Ids kebab-case; v1 state/computed names letters, digits, underscore only (no hyphens).
- v1 expressions: only names, numbers, 'text', true, false, + - * / %, == != < <= > >=, and, or, not, parentheses,
  if, min, max, round, abs, len. No str(), concat(), indexing, random or time. Text + number is already text.
- In "do", "to" and "value" are expression strings ("to": "0"); v0 actions are plain strings ("startTimer:focus").
- Sequential timers (focus then break, work then rest): the button that starts one stops the other,
  e.g. "do": ["stopTimer:focus", "startTimer:rest"]. Offer pause with pauseTimer where useful.
- Countdowns are always timer components; expressions have no clock.
- Make them genuinely useful and complete (scores with win/reset logic, calculators with live displays, quizzes
  with a score), but compact: at most 25 components.
Example template:
${JSON.stringify(lib.CORE_TEMPLATES.find((t) => t.id === 'pomodoro'))}`;

// ---- Anthropic call ----

function anthropicConfig() {
  let text;
  try {
    text = readFileSync(join(root, 'config.local.json'), 'utf8');
  } catch {
    console.error('No config.local.json in the repo root. See CLAUDE.md.');
    process.exit(1);
  }
  const cfg = JSON.parse(text);
  const a = cfg.providers?.anthropic ?? (cfg.provider === 'anthropic' ? cfg : undefined);
  if (!a?.apiKey) {
    console.error('config.local.json has no anthropic provider.');
    process.exit(1);
  }
  return { apiKey: a.apiKey, model: a.model ?? 'claude-sonnet-5-5' };
}

async function ask(cfg, messages) {
  for (let attempt = 0; ; attempt++) {
    const resp = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-api-key': cfg.apiKey, 'anthropic-version': '2023-06-01' },
      body: JSON.stringify({ model: cfg.model, max_tokens: 32000, system: TEMPLATE_RULES, messages }),
      signal: AbortSignal.timeout(600000)
    });
    if ((resp.status === 429 || resp.status >= 500) && attempt < 4) {
      await new Promise((r) => setTimeout(r, 5000 * 2 ** attempt));
      continue;
    }
    const body = await resp.json();
    if (resp.status !== 200) throw new Error(`HTTP ${resp.status}: ${body?.error?.message ?? ''}`);
    return body.content.filter((c) => c.type === 'text').map((c) => c.text).join('');
  }
}

function parseArray(reply) {
  const start = reply.indexOf('[');
  const end = reply.lastIndexOf(']');
  if (start < 0 || end < start) return [];
  try {
    const arr = JSON.parse(reply.slice(start, end + 1));
    return Array.isArray(arr) ? arr : [];
  } catch {
    return [];
  }
}

async function generateBatch(cfg, category, ideas) {
  const prompt = `Write ${ideas.length} templates, category "${category}", one for each idea:\n` +
    ideas.map((i, n) => `${n + 1}. ${i}`).join('\n');
  const messages = [{ role: 'user', content: prompt }];
  const reply = await ask(cfg, messages);
  if (parseArray(reply).length === 0) console.log(`  ${category}: no JSON array in the reply (${reply.length} chars)`);
  const out = [];
  const retry = [];
  for (const t of parseArray(reply)) {
    const errors = check(t);
    if (errors.length === 0) out.push(t);
    else retry.push({ t, errors });
  }
  if (retry.length > 0) {
    const fix = `These templates are invalid. Reply with ONE JSON array of the corrected templates only:\n` +
      retry.map(({ t, errors }) => `${t.id}: ${errors.slice(0, 8).join(' | ')}`).join('\n');
    const again = parseArray(await ask(cfg, [...messages, { role: 'assistant', content: reply },
      { role: 'user', content: fix }]));
    const asked = new Set(retry.map(({ t }) => t.id));
    for (const t of again.filter((x) => asked.has(x.id) && !out.some((o) => o.id === x.id))) {
      const errors = check(t);
      if (errors.length === 0) out.push(t);
      else console.log(`  dropped ${t.id}: ${errors[0]}`);
    }
  }
  console.log(`${category}: ${out.length}/${ideas.length} valid`);
  return out;
}

// ---- Output ----

function slim(t) {
  const e = { id: t.id, name: t.name, description: t.description, category: t.category, language: t.language ?? 'en',
    tags: [...new Set(t.tags.map((x) => String(x).trim()).filter((x) => x.length > 0))], slots: t.slots,
    capsule: t.capsule };
  e.capsule.id = t.id;
  return e;
}

function write(templates) {
  mkdirSync(dirname(LIBRARY), { recursive: true });
  writeFileSync(LIBRARY, JSON.stringify({ version: 1, templates }) + '\n');
  const market = templates.map((t) => ({
    id: t.id, title: t.name, category: t.category, tags: t.tags, language: t.language,
    capsule: JSON.parse(lib.applySlots(t, {}))
  }));
  writeFileSync(MARKETPLACE, JSON.stringify(market, null, 1) + '\n');
}

function report(templates) {
  const library = new lib.TemplateLibrary(templates);
  let self = 0;
  for (const t of templates) {
    const top = library.search(t.name)[0];
    if (top?.template.id === t.id) self++;
    else console.log(`  search("${t.name}") -> ${top?.template.id ?? 'none'}`);
  }
  for (const [request, want] of [['tennis scoreboard me vs Sam', 'tennis'], ['pomodoro 50/10', 'pomodoro'],
    ['push-up counter', 'push'], ['asdf qwerty', null]]) {
    const m = lib.matchTemplateIn(library, request);
    console.log(`  ${(want === null ? m === null : m !== null && new RegExp(want).test(m.template.id)) ? 'ok  ' : 'FAIL'} ` +
      `"${request}" -> ${m ? `${m.template.id} ${m.score} "${m.capsule.name}"` : 'null'}`);
  }
  console.log(`${templates.length} templates, ${self} find themselves by name; ` +
    `library.json ${Math.round(readFileSync(LIBRARY).length / 1024)} KB`);
}

if (process.argv.includes('--check')) {
  const templates = JSON.parse(readFileSync(LIBRARY, 'utf8')).templates;
  let bad = 0;
  for (const t of templates) {
    const errors = check(t);
    if (errors.length > 0) {
      bad++;
      console.log(`INVALID ${t.id}: ${errors.join(' | ')}`);
    }
  }
  console.log(`${templates.length - bad}/${templates.length} templates valid`);
  report(templates);
  process.exit(bad > 0 ? 1 : 0);
}

if (process.argv.includes('--rebuild')) {
  const current = JSON.parse(readFileSync(LIBRARY, 'utf8')).templates;
  const core = lib.CORE_TEMPLATES.map((t) => slim(JSON.parse(JSON.stringify(t))));
  const rest = current.filter((t) => !core.some((c) => c.id === t.id) && check(t).length === 0);
  write([...core, ...rest]);
  report([...core, ...rest]);
  process.exit(0);
}

const cfg = anthropicConfig();
const only = arg('--only')?.split(',');
const batches = [];
for (const [category, ideas] of Object.entries(IDEAS)) {
  if (only && !only.includes(category)) continue;
  for (let i = 0; i < ideas.length; i += 6) batches.push([category, ideas.slice(i, i + 6)]);
}
const concurrency = Number(arg('--concurrency') ?? 4);
const results = [];
let next = 0;
await Promise.all(Array.from({ length: concurrency }, async () => {
  while (next < batches.length) {
    const [category, ideas] = batches[next++];
    try {
      results.push(...await generateBatch(cfg, category, ideas));
    } catch (e) {
      console.log(`${category}: batch failed (${e.message})`);
    }
  }
}));

// --only adds to (and replaces same-id entries in) the current library instead of starting over.
const byId = new Map();
for (const t of lib.CORE_TEMPLATES) byId.set(t.id, slim(JSON.parse(JSON.stringify(t))));
const kept = new Set(byId.keys());
if (only) {
  try {
    for (const t of JSON.parse(readFileSync(LIBRARY, 'utf8')).templates) if (!kept.has(t.id)) byId.set(t.id, t);
  } catch {
    // no library yet
  }
}
for (const t of results) {
  let id = t.id;
  for (let n = 2; kept.has(id) || (!only && byId.has(id)); n++) id = `${t.id}-${n}`;
  byId.set(id, slim({ ...t, id }));
}
const templates = [...byId.values()];
write(templates);
report(templates);
