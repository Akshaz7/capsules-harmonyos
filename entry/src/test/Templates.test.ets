import { describe, it, expect } from '@ohos/hypium';
import { Capsule, CapsuleComponent, TimerComponent } from '../main/ets/core/CapsuleTypes';
import { allComponents } from '../main/ets/core/CapsuleProgram';
import { validateCapsule } from '../main/ets/core/CapsuleValidator';
import { CORE_TEMPLATES } from '../main/ets/core/templates/CoreTemplates';
import {
  applySlots, extractItems, extractNames, fillTemplate, foldText, matchTemplateIn, parseTimes, TemplateEntry,
  TemplateLibrary, TemplateMatch
} from '../main/ets/core/templates/TemplateLibrary';
import { fillUnclearSlots, parseSlotReply, slotPrompt } from '../main/ets/core/templates/SlotFill';
import { MemoryStore, normaliseRequest, RequestCache } from '../main/ets/core/templates/RequestCache';
import { CapsuleSource, generateCapsuleWith, LocalSources } from '../main/ets/core/CapsuleGenerator';
import { GenerateResult } from '../main/ets/core/CapsuleTypes';
import { MarketReply, MarketTransport, matchTemplateAsync } from '../main/ets/core/templates/MarketMatch';

const STREAK_CAPSULE: string = '{"schemaVersion":1,"id":"theirs","name":"Pomodoro streak","permissions":[],' +
  '"state":{"days":{"type":"number","initial":0}},"ui":[{"type":"display","text":"{days} days"},' +
  '{"type":"button","label":"Done today","do":[{"set":"days","to":"days + 1"}]}]}';

/** Fake marketplace: canned replies by URL part, a call log, and an optional delay. */
class FakeMarket implements MarketTransport {
  calls: string[] = [];
  search: string = '';
  capsule: string = '';
  delayMs: number = 0;

  async get(url: string, timeoutMs: number): Promise<MarketReply> {
    this.calls.push(url);
    if (this.delayMs > 0) {
      await new Promise<void>((done: () => void) => {
        setTimeout(done, this.delayMs);
      });
    }
    const body = url.indexOf('/api/capsules?') >= 0 ? this.search : this.capsule;
    return { status: body.length > 0 ? 200 : 404, body: body };
  }
}

function marketWith(name: string, tags: string, capsule: string): FakeMarket {
  const m = new FakeMarket();
  m.search = `{"capsules":[{"id":"m1","name":"${name}","description":"","tags":${tags}}],"nextCursor":null}`;
  m.capsule = capsule.length > 0 ? `{"id":"m1","capsule":${capsule}}` : '';
  return m;
}

class CountingSource implements CapsuleSource {
  calls: number = 0;

  async generate(request: string): Promise<GenerateResult> {
    this.calls++;
    const r = validateCapsule('{"schemaVersion":0,"id":"x","name":"From device","permissions":[],"ui":[]}');
    return { ok: true, capsule: r.capsule, origin: 'on-device', details: [] };
  }
}

const library = new TemplateLibrary(CORE_TEMPLATES);

const VITAMINS: TemplateEntry = {
  id: 'vitamins', name: 'Vitamins', description: 'Tick off vitamins.', category: 'health',
  tags: ['vitamins', 'vitamin d', 'supplements', 'pills'], slots: [],
  capsule: JSON.parse('{"schemaVersion":0,"id":"vitamins","name":"Vitamins","permissions":[],' +
    '"ui":[{"type":"checklist","id":"c","items":["Vitamin D"]}]}') as Object
};
const WATER: TemplateEntry = {
  id: 'water', name: 'Water tracker', description: 'Glasses of water.', category: 'habits',
  tags: ['water', 'drink water', 'glasses'], slots: [{ name: 'goal', kind: 'number', default: 8, hints: ['glasses', 'goal'] }],
  capsule: JSON.parse('{"schemaVersion":1,"id":"water","name":"Water: @{goal} glasses","permissions":[],' +
    '"state":{"n":{"type":"number","initial":0}},"ui":[{"type":"display","text":"{n} / @{goal}"},' +
    '{"type":"button","label":"+1","do":[{"set":"n","to":"n + 1"}]}]}') as Object
};

function match(request: string): TemplateMatch {
  const m = matchTemplateIn(library, request);
  expect(m === null).assertFalse();
  return m as TemplateMatch;
}

function timers(c: Capsule): number[] {
  return allComponents(c.ui).filter((x: CapsuleComponent) => x.type === 'timer')
    .map((t: CapsuleComponent) => (t as TimerComponent).minutes);
}

const CHECKLIST: TemplateEntry = {
  id: 'packing', name: 'Packing list', description: 'Things to pack.', tags: ['packing', 'luggage', 'trip'],
  slots: [{ name: 'items', kind: 'list', default: ['passport'] }],
  capsule: JSON.parse('{"schemaVersion":0,"id":"packing","name":"Packing list","permissions":[],' +
    '"ui":[{"type":"checklist","id":"c","items":["@{items}"]},{"type":"text","text":"Pack @{items}"}]}') as Object
};

export default function templatesTest() {
  describe('Templates', () => {
    it('every core template validates with its defaults', 0, () => {
      CORE_TEMPLATES.forEach((t: TemplateEntry) => {
        const v = validateCapsule(applySlots(t, {}));
        expect(`${t.id}: ${v.errors.join('; ')}`).assertEqual(`${t.id}: `);
      });
    });

    it('tennis scoreboard me vs Sam -> tennis with Me and Sam', 0, () => {
      const m = match('tennis scoreboard me vs Sam');
      expect(m.template.id).assertEqual('tennis');
      expect(m.capsule.name).assertEqual('Tennis: Me vs Sam');
      const text = JSON.stringify(m.capsule);
      expect(text).assertContain('Point Me');
      expect(text).assertContain('Point Sam');
      expect(text).assertContain('Advantage Sam');
      expect(m.unfilledSlots.length).assertEqual(0);
      expect(m.score >= 0.9).assertTrue();
    });

    it('pomodoro 50/10 -> 50 and 10 minute timers', 0, () => {
      const m = match('pomodoro 50/10');
      expect(m.template.id).assertEqual('pomodoro');
      expect(JSON.stringify(timers(m.capsule))).assertEqual('[50,10]');
      expect(JSON.stringify(m.capsule)).assertContain('"do":["stopTimer:focus","startTimer:rest","increment:rounds"]');
      expect(JSON.stringify(m.capsule)).assertContain('"label":"Start focus","action":"","do":["stopTimer:rest","startTimer:focus"]');
      expect(JSON.stringify(m.capsule).indexOf('startAllTimers')).assertEqual(-1); // BUG-10: no Start all
    });

    it('numbers next to a hint word go to that slot', 0, () => {
      expect(JSON.stringify(timers(match('pomodoro with a 10 minute break and 40 min focus').capsule)))
        .assertEqual('[40,10]');
      expect(JSON.stringify(timers(match('pomodoro break 15 work 45').capsule))).assertEqual('[45,15]');
      expect(JSON.stringify(timers(match('pomodoro 40 work, 20 rest').capsule))).assertEqual('[40,20]');
    });

    it('push-up counter -> push-up counter with a goal', 0, () => {
      const m = match('push-up counter');
      expect(m.template.id).assertEqual('pushups');
      expect(m.capsule.name).assertEqual('Push-up counter');
      expect(match('pushups goal 80').values['goal']).assertEqual(80);
    });

    it('nonsense -> null', 0, () => {
      expect(matchTemplateIn(library, 'asdf qwerty zxcv') === null).assertTrue();
      expect(matchTemplateIn(library, '') === null).assertTrue();
      expect(matchTemplateIn(library, '50/10') === null).assertTrue();
    });

    it('requests that ask for much more than a template are left to the models', 0, () => {
      expect(matchTemplateIn(library, 'tennis scoreboard with tiebreaks, sets and a serve clock') === null).assertTrue();
    });

    it('search ranks by score and folds accents and plurals', 0, () => {
      expect(foldText('Café TIMER')).assertEqual('cafe timer');
      expect(library.search('tennis scoreboards')[0].template.id).assertEqual('tennis');
      const hits = library.search('push ups counter');
      expect(hits[0].template.id).assertEqual('pushups');
      expect(hits[0].score).assertEqual(1);
    });

    it('extracts names and items', 0, () => {
      expect(JSON.stringify(extractNames('darts Anna vs Tom vs Ola'))).assertEqual('["Anna","Tom","Ola"]');
      expect(JSON.stringify(extractNames('volleyball Team A vs Team B'))).assertEqual('["Team A","Team B"]');
      expect(JSON.stringify(extractNames('cards for Ann, Bo and Cy'))).assertEqual('["Ann","Bo","Cy"]');
      expect(JSON.stringify(extractNames('checklist for keys and wallet'))).assertEqual('[]');
      expect(JSON.stringify(extractNames('scoreboard between Ann and Bo'))).assertEqual('["Ann","Bo"]');
      expect(JSON.stringify(extractItems('packing: socks, charger and passport')))
        .assertEqual('["socks","charger","passport"]');
    });

    it('fills list slots and strips quotes and braces from slot text', 0, () => {
      const f = fillTemplate(CHECKLIST, 'packing list: socks, "hat", {x}');
      expect(f.error === undefined).assertTrue();
      expect(JSON.stringify(f.capsule?.ui[0])).assertContain('["socks","hat","x"]');
      expect(JSON.stringify(f.capsule?.ui[1])).assertContain('Pack socks, hat, x');
      const evil = fillTemplate(CORE_TEMPLATES[0], "tennis Bob' + 1 vs {Sam}");
      expect(evil.error === undefined).assertTrue();
    });

    it('reports unclear slots only when the request says more than the rules used', 0, () => {
      expect(match('tennis').unfilledSlots.length).assertEqual(0);
      const f = fillTemplate(CORE_TEMPLATES[0], 'tennis scoreboard for Ann with Bo');
      expect(JSON.stringify(f.unclear)).assertEqual('["player1","player2"]');
    });

    it('on-device hook fills unclear slots with grounded values only', 0, async () => {
      const base = match('pomodoro');
      const m: TemplateMatch = {
        capsule: base.capsule, score: base.score, template: base.template, values: base.values,
        unfilledSlots: ['work', 'rest'], origin: 'template', source: base.source
      };
      const request = 'pomodoro focus fifty 50 then rest 7';
      expect(slotPrompt(m.template, request, m.unfilledSlots)).assertContain('{"work":NUMBER,"rest":NUMBER}');
      const better = await fillUnclearSlots(m, request, async (): Promise<string> => '{"work":50,"rest":7}');
      expect(JSON.stringify(timers(better.capsule))).assertEqual('[50,7]');
      expect(better.unfilledSlots.length).assertEqual(0);
      const made = parseSlotReply('{"work":99,"rest":7}', m.template, request, m.unfilledSlots);
      expect(JSON.stringify(made)).assertEqual('{"rest":7}');
      const broken = await fillUnclearSlots(m, request, async (): Promise<string> => 'no json');
      expect(broken).assertEqual(m);
    });

    it('request cache normalises, re-validates and caps entries', 0, async () => {
      expect(normaliseRequest('  Tennis scoreboard, me vs SAM! ')).assertEqual('tennis scoreboard me vs sam');
      expect(normaliseRequest('Pomodoro 50/10.')).assertEqual('pomodoro 50/10');
      const store = new MemoryStore();
      let now = 0;
      const cache = new RequestCache(store, 3, (): number => ++now);
      const c = match('pomodoro 50/10').capsule;
      await cache.put('Pomodoro 50/10', c, 'template');
      const hit = new RequestCache(store, 3).get('pomodoro   50/10!');
      expect(hit?.origin).assertEqual('template');
      expect(JSON.stringify(hit?.capsule)).assertEqual(JSON.stringify(c));
      await cache.put('a', c, 'rules');
      await cache.put('b', c, 'rules');
      cache.get('pomodoro 50/10'); // recently used: survives the next put
      await cache.put('d', c, 'rules');
      expect(cache.size).assertEqual(3);
      expect(cache.get('a') === null).assertTrue();
      expect(cache.get('pomodoro 50/10') === null).assertFalse();
      store.text = '[{"key":"x","capsule":"{\\"bad\\":1}","origin":"rules","t":1}]';
      expect(new RequestCache(store).get('x') === null).assertTrue();
      expect(new RequestCache(new MemoryStore()).get('anything') === null).assertTrue();
    });
    it('routing: cache, then rules, then a template, before the on-device model', 0, async () => {
      const device = new CountingSource();
      const cache = new RequestCache(new MemoryStore());
      const local: LocalSources = { cache: cache, library: library };
      const t = await generateCapsuleWith('tennis scoreboard me vs Sam', [], '', device, undefined, local);
      expect(t.origin).assertEqual('template');
      expect(t.capsule?.name).assertEqual('Tennis: Me vs Sam');
      expect(device.calls).assertEqual(0);
      const rules = await generateCapsuleWith('count my squats', [], '', device, undefined, local);
      expect(rules.origin).assertEqual('rules');
      const other = await generateCapsuleWith('my grandma knitting patterns', [], '', device, undefined, local);
      expect(other.origin).assertEqual('on-device');
      expect(device.calls).assertEqual(1);
      await cache.put('my grandma knitting patterns', other.capsule as Capsule, 'on-device');
      const again = await generateCapsuleWith('My grandma knitting patterns!', [], '', device, undefined, local);
      expect(again.origin).assertEqual('on-device');
      expect(device.calls).assertEqual(1); // served from the cache
      const smarter = await generateCapsuleWith('my grandma knitting patterns', [], '', device, { cloudOnly: true }, local);
      expect(smarter.ok).assertFalse(); // "Make it smarter" skips the cache (no cloud configured here)
      const plain = await generateCapsuleWith('tennis scoreboard me vs Sam', [], '', device);
      expect(plain.origin).assertEqual('on-device'); // without local sources nothing changes
    });
  it('marketplace: offline or no base URL -> local only, no request', 0, async () => {
      const m = marketWith('Pomodoro streak', '["pomodoro","streak"]', STREAK_CAPSULE);
      const off = await matchTemplateAsync(library, 'pomodoro streak', { baseUrl: 'https://m.example', transport: m,
        online: false });
      expect(off === null).assertTrue(); // local pomodoro alone scores too low for "pomodoro streak"
      const none = await matchTemplateAsync(library, 'pomodoro 50/10', { baseUrl: '', transport: m });
      expect(none?.origin).assertEqual('template');
      expect(m.calls.length).assertEqual(0);
    });

    it('marketplace: a timeout falls back to local templates', 0, async () => {
      const m = marketWith('Tennis pro', '["tennis","scoreboard"]', STREAK_CAPSULE);
      m.delayMs = 300;
      const r = await matchTemplateAsync(library, 'tennis scoreboard me vs Sam',
        { baseUrl: 'https://m.example', transport: m, timeoutMs: 50 });
      expect(r?.origin).assertEqual('template');
      expect(r?.capsule.name).assertEqual('Tennis: Me vs Sam');
    });

    it('marketplace: a better marketplace hit beats a weaker local one, validated with a fresh id', 0, async () => {
      const m = marketWith('Pomodoro streak', '["pomodoro","streak","focus-streak"]', STREAK_CAPSULE);
      const r = await matchTemplateAsync(library, 'pomodoro streak', { baseUrl: 'https://m.example/', transport: m });
      expect(r?.origin).assertEqual('community');
      expect(r?.source).assertEqual('Pomodoro streak');
      expect(r?.capsule.name).assertEqual('Pomodoro streak');
      expect(r?.capsule.id.startsWith('community-')).assertTrue();
      expect(m.calls[0]).assertEqual('https://m.example/api/capsules?q=pomodoro%20streak&limit=20');
      expect(m.calls[1]).assertEqual('https://m.example/api/capsules/m1');
    });

    it('marketplace: local wins a tie, and invalid marketplace JSON is dropped', 0, async () => {
      const tie = marketWith('Tennis scoreboard', '["tennis","scoreboard"]', STREAK_CAPSULE);
      const t = await matchTemplateAsync(library, 'tennis scoreboard', { baseUrl: 'https://m.example', transport: tie });
      expect(t?.score).assertEqual(1);
      expect(t?.origin).assertEqual('template');
      expect(tie.calls.length).assertEqual(1); // searched, but nothing downloaded
      const bad = marketWith('Pomodoro streak', '["pomodoro","streak"]',
        '{"schemaVersion":1,"id":"x","name":"Evil","permissions":[],"ui":[{"type":"script","code":"rm"}]}');
      expect(await matchTemplateAsync(library, 'pomodoro streak', { baseUrl: 'https://m.example', transport: bad }) ===
        null).assertTrue();
      const garbage = new FakeMarket();
      garbage.search = '<html>502</html>';
      const g = await matchTemplateAsync(library, 'pomodoro 50/10', { baseUrl: 'https://m.example', transport: garbage });
      expect(g?.origin).assertEqual('template');
    });

    it('routing: a community capsule comes back with origin community', 0, async () => {
      const m = marketWith('Pomodoro streak', '["pomodoro","streak"]', STREAK_CAPSULE);
      const local: LocalSources = { library: library, market: { baseUrl: 'https://m.example', transport: m } };
      const r = await generateCapsuleWith('pomodoro streak', [], '', new CountingSource(), undefined, local);
      expect(r.origin).assertEqual('community');
    });
  it('time triggers: parses times of day', 0, () => {
      expect(JSON.stringify(parseTimes('vitamin D every morning at 8'))).assertEqual('["08:00"]');
      expect(JSON.stringify(parseTimes('meds at 8am and 8pm'))).assertEqual('["08:00","20:00"]');
      expect(JSON.stringify(parseTimes('water every evening at 9'))).assertEqual('["21:00"]');
      expect(JSON.stringify(parseTimes('stretch 7:30 and 12pm and 12am'))).assertEqual('["07:30","12:00","00:00"]');
      expect(JSON.stringify(parseTimes('pomodoro 50/10'))).assertEqual('[]');
      expect(JSON.stringify(parseTimes('vitamins every morning'))).assertEqual('[]');
    });

    it('time triggers: vitamins and medication get one daily trigger per time, valid', 0, () => {
      const one = fillTemplate(VITAMINS, 'vitamin D every morning at 8');
      expect(one.error === undefined).assertTrue();
      expect(one.capsule?.schemaVersion).assertEqual(1);
      expect(JSON.stringify(one.capsule?.triggers)).assertEqual(
        '[{"on":"time","do":["notify:Time for Vitamins"],"at":"08:00","label":"Vitamins at 08:00"}]');
      expect(JSON.stringify(one.capsule?.permissions)).assertEqual('["reminders","notifications"]');
      const two = fillTemplate(VITAMINS, 'meds at 8am and 8pm');
      expect(two.capsule?.triggers?.length).assertEqual(2);
      const none = fillTemplate(VITAMINS, 'vitamins checklist');
      expect(none.capsule?.triggers === undefined).assertTrue();
      expect(none.capsule?.schemaVersion).assertEqual(0);
    });

    it('time triggers: habit templates too, and times are not read as goals', 0, () => {
      const f = fillTemplate(WATER, 'drink water 10 glasses, remind me at 9am and 3pm');
      expect(f.values['goal']).assertEqual(10);
      expect(JSON.stringify(f.capsule?.triggers?.map((t) => t.at))).assertEqual('["09:00","15:00"]');
      const plain = fillTemplate(WATER, 'water at 9am');
      expect(plain.values['goal']).assertEqual(8); // 9 is a time, not a goal
      expect(fillTemplate(WATER, 'water tracker').capsule?.triggers === undefined).assertTrue();
      expect(fillTemplate(CORE_TEMPLATES[1], 'pomodoro at 9am').capsule?.triggers === undefined).assertTrue();
    });
});
}
