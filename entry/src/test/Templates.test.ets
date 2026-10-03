import { describe, it, expect } from '@ohos/hypium';
import { Capsule, CapsuleComponent, TimerComponent } from '../main/ets/core/CapsuleTypes';
import { allComponents } from '../main/ets/core/CapsuleProgram';
import { validateCapsule } from '../main/ets/core/CapsuleValidator';
import { CORE_TEMPLATES } from '../main/ets/core/templates/CoreTemplates';
import {
  applySlots, extractItems, extractNames, fillTemplate, foldText, matchTemplateIn, TemplateEntry, TemplateLibrary,
  TemplateMatch
} from '../main/ets/core/templates/TemplateLibrary';
import { fillUnclearSlots, parseSlotReply, slotPrompt } from '../main/ets/core/templates/SlotFill';
import { MemoryStore, normaliseRequest, RequestCache } from '../main/ets/core/templates/RequestCache';
import { CapsuleSource, generateCapsuleWith, LocalSources } from '../main/ets/core/CapsuleGenerator';
import { GenerateResult } from '../main/ets/core/CapsuleTypes';

class CountingSource implements CapsuleSource {
  calls: number = 0;

  async generate(request: string): Promise<GenerateResult> {
    this.calls++;
    const r = validateCapsule('{"schemaVersion":0,"id":"x","name":"From device","permissions":[],"ui":[]}');
    return { ok: true, capsule: r.capsule, origin: 'on-device', details: [] };
  }
}

const library = new TemplateLibrary(CORE_TEMPLATES);

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
        unfilledSlots: ['work', 'rest']
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
});
}
