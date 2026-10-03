import { describe, it, expect } from '@ohos/hypium';
import { ActionGuard, CapsuleRuntime } from '../main/ets/renderer/CapsuleRuntime';
import { validateCapsule } from '../main/ets/core/CapsuleValidator';
import { BILL_SPLIT_CAPSULE as BILL, TENNIS_CAPSULE as TENNIS } from '../main/ets/core/V1Fixtures';
import {
  allComponents, applyActions, ApplyResult, evaluate, initialState, inputText, isEnabled, isShown, listItems,
  renderTemplate, restoreState, setInput, StateValues
} from '../main/ets/core/CapsuleProgram';
import {
  ButtonComponent, Capsule, CapsuleComponent, DisplayComponent, WhenComponent
} from '../main/ets/core/CapsuleTypes';

// ---- Example capsules ----

const SHOPPING: string = `{
  "schemaVersion": 1, "id": "shop", "name": "Shopping", "permissions": [],
  "state": { "item": { "type": "text", "initial": "" }, "items": { "type": "list", "initial": [] } },
  "ui": [
    { "type": "input", "bind": "item", "kind": "text", "label": "Item" },
    { "type": "button", "label": "Add", "enabledIf": "len(item) > 0",
      "do": [ { "push": "items", "value": "item" }, { "set": "item", "to": "''" } ] },
    { "type": "button", "label": "Undo", "enabledIf": "len(items) > 0", "do": [ { "pop": "items" } ] },
    { "type": "display", "text": "{len(items)} items" },
    { "type": "list", "source": "items" }
  ]
}`;

// ---- Helpers ----

function load(json: string): Capsule {
  const r = validateCapsule(json);
  expect(r.errors.join('\n')).assertEqual('');
  return r.capsule as Capsule;
}

function button(c: Capsule, label: string): ButtonComponent {
  return allComponents(c.ui).find((x: CapsuleComponent) => x.type === 'button' &&
    (x as ButtonComponent).label === label) as ButtonComponent;
}

function press(c: Capsule, s: StateValues, label: string): StateValues {
  const r = applyActions(c, s, button(c, label));
  expect(r.error ?? '').assertEqual('');
  return r.state;
}

function pressAll(c: Capsule, s: StateValues, labels: string[]): StateValues {
  let state = s;
  labels.forEach((l: string) => {
    state = press(c, state, l);
  });
  return state;
}

function show(c: Capsule, s: StateValues, index: number): string {
  return renderTemplate(c, s, (c.ui[index] as DisplayComponent).text);
}

function typed(c: Capsule, s: StateValues, name: string, raw: string): StateValues {
  const r = setInput(c, s, name, raw);
  expect(r.ok).assertTrue();
  return r.state;
}

/** A v1 capsule with the given state, computed and ui JSON snippets. */
function v1(state: string, computed: string, ui: string, permissions?: string): string {
  return `{"schemaVersion":1,"id":"x","name":"X","permissions":${permissions ?? '[]'},"state":${state},` +
    `"computed":${computed},"ui":${ui}}`;
}

/** A v1 capsule with NUM state, the given permissions and triggers. */
function v1Triggers(permissions: string, triggers: string): string {
  return `{"schemaVersion":1,"id":"x","name":"X","permissions":${permissions},"state":${NUM_STATE},` +
    `"ui":[{"type":"display","text":"{n}"}],"triggers":${triggers}}`;
}

function errorsOf(json: string): string {
  return validateCapsule(json).errors.join('\n');
}

const NUM_STATE: string = '{"n":{"type":"number","initial":0},"t":{"type":"text","initial":"hi"}}';
const NUM: string = '{"n":{"type":"number","initial":0},"t":{"type":"text","initial":"hi"},' +
  '"xs":{"type":"list","initial":[1,2]},"on":{"type":"bool","initial":true}}';

/** A gatekeeper stand-in that refuses every action. */
class DenyAll implements ActionGuard {
  allowAction(action: string): boolean {
    return false;
  }
}

export default function capsuleV1Test() {
  describe('Schema v1: tennis scoreboard', () => {
    it('validates and starts at 0 - 0', 0, () => {
      const c = load(TENNIS);
      const s = initialState(c);
      expect(show(c, s, 0)).assertEqual('Games 0 - 0');
      expect(show(c, s, 1)).assertEqual('0 - 0');
      expect(isShown(c, s, c.ui[3] as WhenComponent)).assertFalse();
      expect(isEnabled(c, s, button(c, 'Reset match'))).assertFalse();
    });

    it('counts 15, 30, 40 and wins a game', 0, () => {
      const c = load(TENNIS);
      let s = initialState(c);
      s = press(c, s, 'Point P1');
      expect(show(c, s, 1)).assertEqual('15 - 0');
      s = press(c, s, 'Point P1');
      expect(show(c, s, 1)).assertEqual('30 - 0');
      s = press(c, s, 'Point P2');
      expect(show(c, s, 1)).assertEqual('30 - 15');
      s = press(c, s, 'Point P1');
      expect(show(c, s, 1)).assertEqual('40 - 15');
      s = press(c, s, 'Point P1');
      expect(show(c, s, 0)).assertEqual('Games 1 - 0');
      expect(show(c, s, 1)).assertEqual('0 - 0');
      expect(isShown(c, s, c.ui[3] as WhenComponent)).assertTrue();
      expect(renderTemplate(c, s, ((c.ui[3] as WhenComponent).show[0] as DisplayComponent).text)).assertEqual('P1 leads');
    });

    it('handles deuce and advantage both ways, then a game for P2', 0, () => {
      const c = load(TENNIS);
      let s = pressAll(c, initialState(c), ['Point P1', 'Point P1', 'Point P1', 'Point P2', 'Point P2', 'Point P2']);
      expect(show(c, s, 1)).assertEqual('Deuce');
      s = press(c, s, 'Point P1');
      expect(show(c, s, 1)).assertEqual('Advantage P1');
      s = press(c, s, 'Point P2');
      expect(show(c, s, 1)).assertEqual('Deuce');
      s = press(c, s, 'Point P2');
      expect(show(c, s, 1)).assertEqual('Advantage P2');
      s = press(c, s, 'Point P2');
      expect(show(c, s, 0)).assertEqual('Games 0 - 1');
      expect(show(c, s, 1)).assertEqual('0 - 0');
    });

    it('resets the match and never mutates the old state', 0, () => {
      const c = load(TENNIS);
      const s0 = initialState(c);
      const s1 = pressAll(c, s0, ['Point P1', 'Point P1', 'Point P1', 'Point P1']);
      expect(s0['g1']).assertEqual(0);
      expect(s1['g1']).assertEqual(1);
      const s2 = press(c, s1, 'Reset match');
      expect(show(c, s2, 0)).assertEqual('Games 0 - 0');
    });
  });

  describe('Schema v1: live bill split', () => {
    it('updates the share as inputs change', 0, () => {
      const c = load(BILL);
      let s = initialState(c);
      expect(show(c, s, 3)).assertEqual('Each pays 0');
      s = typed(c, s, 'total', '84');
      s = typed(c, s, 'people', '4');
      expect(show(c, s, 3)).assertEqual('Each pays 21');
      s = typed(c, s, 'tip', '10');
      expect(show(c, s, 3)).assertEqual('Each pays 23.1');
      s = typed(c, s, 'people', '3');
      expect(show(c, s, 3)).assertEqual('Each pays 30.8');
      expect(inputText(s, 'total')).assertEqual('84');
    });

    it('guards against zero people and bad input', 0, () => {
      const c = load(BILL);
      let s = typed(c, initialState(c), 'total', '50');
      s = typed(c, s, 'people', '0');
      expect(show(c, s, 3)).assertEqual('Each pays 0');
      expect(isShown(c, s, c.ui[4] as WhenComponent)).assertTrue();
      const bad = setInput(c, s, 'total', 'abc');
      expect(bad.ok).assertFalse();
      expect(bad.error).assertContain('not a number');
      expect(bad.state['total']).assertEqual(50);
      expect(setInput(c, s, 'total', '').ok).assertFalse();
    });
  });

  describe('Schema v1: interpreter', () => {
    it('pushes, pops and respects enabledIf on a shopping list', 0, () => {
      const c = load(SHOPPING);
      let s = initialState(c);
      expect(isEnabled(c, s, button(c, 'Add'))).assertFalse();
      expect(applyActions(c, s, button(c, 'Add')).error).assertContain('disabled');
      s = typed(c, s, 'item', 'milk');
      s = press(c, s, 'Add');
      s = typed(c, s, 'item', 'eggs');
      s = press(c, s, 'Add');
      expect(listItems(s, 'items').join('|')).assertEqual('milk|eggs');
      expect(s['item']).assertEqual('');
      expect(renderTemplate(c, s, '{len(items)} items')).assertEqual('2 items');
      s = press(c, s, 'Undo');
      expect(listItems(s, 'items').join('|')).assertEqual('milk');
    });

    it('is all-or-nothing when a step fails', 0, () => {
      const c = load(v1(NUM, '{}', '[{"type":"button","label":"Go","do":[{"set":"n","to":"n + 1"},' +
        '{"set":"n","to":"n / 0"}]}]'));
      const s = initialState(c);
      const r: ApplyResult = applyActions(c, s, c.ui[0] as ButtonComponent);
      expect(r.ok).assertFalse();
      expect(r.error).assertEqual('division by zero');
      expect(r.state['n']).assertEqual(0);
    });

    it('returns v0 actions in order for the runtime to dispatch', 0, () => {
      const c = load(v1(NUM, '{}', '[{"type":"timer","id":"t","label":"T","minutes":1},' +
        '{"type":"button","label":"Go","action":"startTimer:t","do":[{"set":"n","to":"n + 1"},"notify:Started"]}]',
        '["reminders","notifications"]'));
      const r = applyActions(c, initialState(c), c.ui[1] as ButtonComponent);
      expect(r.actions.join('|')).assertEqual('startTimer:t|notify:Started');
      expect(r.state['n']).assertEqual(1);
    });

    it('shows ? for a failing expression in a display', 0, () => {
      const c = load(v1(NUM, '{}', '[{"type":"display","text":"{n} / {10 / n}"}]'));
      expect(show(c, initialState(c), 0)).assertEqual('0 / ?');
    });

    it('restores saved state, dropping stale or mistyped values', 0, () => {
      const c = load(v1(NUM, '{}', '[]'));
      const saved: StateValues = {};
      saved['n'] = 5;
      saved['t'] = 42;
      saved['gone'] = 1;
      const s = restoreState(c, saved);
      expect(s['n']).assertEqual(5);
      expect(s['t']).assertEqual('hi');
      expect(Object.keys(s).includes('gone')).assertFalse();
    });

    it('evaluates computed values that use other computed values', 0, () => {
      const c = load(v1(NUM, '{"a":"n + 1","b":"a * 2"}', '[]'));
      expect(evaluate(c, initialState(c), 'b').value).assertEqual(2);
    });
  });

  describe('Schema v1: validator', () => {
    it('keeps v0 capsules valid and needs schemaVersion 1 for v1 features', 0, () => {
      expect(validateCapsule('{"schemaVersion":0,"id":"x","name":"X","permissions":[],"ui":[]}').ok).assertTrue();
      expect(errorsOf('{"schemaVersion":0,"id":"x","name":"X","permissions":[],"ui":[],"state":{}}'))
        .assertContain('unknown field "state"');
      expect(errorsOf('{"schemaVersion":0,"id":"x","name":"X","permissions":[],"ui":[{"type":"display","text":"a"}]}'))
        .assertContain('"display" needs "schemaVersion": 1');
    });

    it('survives a JSON round trip, including do-only buttons', 0, () => {
      const c = load(TENNIS);
      const again = validateCapsule(JSON.stringify(c));
      expect(again.errors.join('\n')).assertEqual('');
      expect(JSON.stringify(again.capsule)).assertEqual(JSON.stringify(c));
    });

    it('rejects unknown names and type mismatches in expressions', 0, () => {
      expect(errorsOf(v1(NUM, '{}', '[{"type":"display","text":"{missing}"}]')))
        .assertContain('$.ui[0].text: unknown name "missing"');
      expect(errorsOf(v1(NUM, '{}', '[{"type":"button","label":"Go","do":[{"set":"n","to":"t"}]}]')))
        .assertContain('"n" is number, but the expression is text');
      expect(errorsOf(v1(NUM, '{}', '[{"type":"when","if":"n + 1","show":[]}]')))
        .assertContain('must be a bool expression, got number');
      expect(errorsOf(v1(NUM, '{}', '[{"type":"button","label":"Go","enabledIf":"t","do":[{"pop":"xs"}]}]')))
        .assertContain('$.ui[0].enabledIf: must be a bool expression, got text');
      expect(errorsOf(v1(NUM, '{}', '[{"type":"display","text":"{n +}"}]'))).assertContain('unexpected the end');
    });

    it('checks bindings, list sources and step targets', 0, () => {
      expect(errorsOf(v1(NUM, '{}', '[{"type":"input","bind":"t","kind":"number","label":"L"}]')))
        .assertContain('a number input cannot bind "t", which is text');
      expect(errorsOf(v1(NUM, '{}', '[{"type":"list","source":"n"}]'))).assertContain('"n" is number, not a list');
      expect(errorsOf(v1(NUM, '{"c":"n + 1"}', '[{"type":"button","label":"Go","do":[{"set":"c","to":"1"}]}]')))
        .assertContain('"c" is a computed value; use a state variable');
      expect(errorsOf(v1(NUM, '{}', '[{"type":"button","label":"Go","do":[{"push":"xs","value":"xs"}]}]')))
        .assertContain('a list cannot be pushed into a list');
      expect(errorsOf(v1(NUM, '{}', '[{"type":"button","label":"Go","do":[{"jump":"n"}]}]')))
        .assertContain('unknown step');
      expect(errorsOf(v1(NUM, '{}', '[{"type":"button","label":"Go"}]'))).assertContain('needs "action" or "do"');
    });

    it('rejects computed cycles, bad names and wrong initial values', 0, () => {
      expect(errorsOf(v1(NUM, '{"a":"b + 1","b":"a + 1"}', '[]'))).assertContain('cycle: a -> b -> a');
      expect(errorsOf(v1('{"if":{"type":"number","initial":0}}', '{}', '[]'))).assertContain('not a valid name');
      expect(errorsOf(v1('{"n":{"type":"number","initial":"0"}}', '{}', '[]'))).assertContain('$.state.n.initial');
      expect(errorsOf(v1('{"n":{"type":"date","initial":0}}', '{}', '[]'))).assertContain('must be one of number');
      expect(errorsOf(v1(NUM, '{"n":"1"}', '[]'))).assertContain('already a state variable');
    });

    it('enforces the 30 variable, 60 component and nesting limits', 0, () => {
      const vars: string[] = [];
      for (let i = 0; i < 31; i++) {
        vars.push(`"v${i}":{"type":"number","initial":0}`);
      }
      expect(errorsOf(v1(`{${vars.join(',')}}`, '{}', '[]'))).assertContain('has 31 variables (max 30)');
      const many: string[] = [];
      for (let i = 0; i < 61; i++) {
        many.push('{"type":"text","text":"x"}');
      }
      expect(errorsOf(v1(NUM, '{}', `[${many.join(',')}]`))).assertContain('has 61 components');
      let nested = '{"type":"text","text":"deep"}';
      for (let i = 0; i < 6; i++) {
        nested = `{"type":"row","items":[${nested}]}`;
      }
      expect(errorsOf(v1(NUM, '{}', `[${nested}]`))).assertContain('nested too deeply');
    });

    it('rejects {name} placeholders outside display components, which would show literally', 0, () => {
      const streak = '{"streak":{"type":"number","initial":0}}';
      expect(errorsOf(v1(streak, '{}', '[{"type":"text","text":"Reading Streak: {streak}"}]')))
        .assertContain('$.ui[0].text: "{streak}" would be shown literally; only a "display" component fills in');
      expect(errorsOf(v1(streak, '{}', '[{"type":"display","text":"Reading Streak: {streak}"}]'))).assertEqual('');
      expect(errorsOf(v1(streak, '{}', '[{"type":"display","text":"Reading Streak: {streek}"}]')))
        .assertContain('unknown name "streek"');
      expect(errorsOf(v1(streak, '{}', '[{"type":"row","items":[{"type":"button","label":"+1 {streak}",' +
        '"do":[{"set":"streak","to":"streak + 1"}]}]}]'))).assertContain('$.ui[0].items[0].label: "{streak}"');
      expect(errorsOf('{"schemaVersion":0,"id":"x","name":"X","permissions":[],' +
        '"ui":[{"type":"checklist","id":"c","items":["Day {n}"]}]}')).assertContain('$.ui[0].items[0]: "{n}"');
      expect(errorsOf(v1(streak, '{}', '[{"type":"text","text":"Use {{braces}} and {} freely"}]'))).assertEqual('');
    });

    it('v1.1: accepts daily time and motion-start triggers and keeps them through a round trip', 0, () => {
      const json = v1Triggers('["reminders","motion","notifications"]', '[' +
        '{"on":"time","at":"07:30","label":"Morning reset","do":[{"reset":"n"},"notify:New day"]},' +
        '{"on":"motion","do":[{"set":"n","to":"n + 1"}]}]');
      const r = validateCapsule(json);
      expect(r.errors.join('\n')).assertEqual('');
      const triggers = r.capsule?.triggers ?? [];
      expect(triggers.length).assertEqual(2);
      expect(triggers[0].on).assertEqual('time');
      expect(triggers[0].at).assertEqual('07:30');
      expect(triggers[0].label).assertEqual('Morning reset');
      expect(triggers[1].at).assertUndefined();
      expect(JSON.stringify(validateCapsule(JSON.stringify(r.capsule)).capsule)).assertEqual(JSON.stringify(r.capsule));
      expect(validateCapsule(v1(NUM, '{}', '[]')).capsule?.triggers).assertUndefined();
    });

    it('v1.1: rejects bad trigger kinds, times and fields', 0, () => {
      const perms = '["reminders","motion"]';
      expect(errorsOf(v1Triggers(perms, '[{"on":"time","at":"25:00","do":[{"reset":"n"}]}]')))
        .assertContain('$.triggers[0].at: must be a 24-hour time "HH:MM"');
      expect(errorsOf(v1Triggers(perms, '[{"on":"time","at":"7:30","do":[{"reset":"n"}]}]'))).assertContain('"HH:MM"');
      expect(errorsOf(v1Triggers(perms, '[{"on":"time","do":[{"reset":"n"}]}]')))
        .assertContain('$.triggers[0]: missing required field "at"');
      expect(errorsOf(v1Triggers(perms, '[{"on":"motion","at":"08:00","do":[{"reset":"n"}]}]')))
        .assertContain('unknown field "at"');
      expect(errorsOf(v1Triggers(perms, '[{"on":"sunrise","do":[{"reset":"n"}]}]')))
        .assertContain('$.triggers[0].on: must be one of time, motion');
      expect(errorsOf(v1Triggers(perms, '[{"on":"motion","do":[]}]'))).assertContain('$.triggers[0].do: must be a non-empty');
      expect(errorsOf(v1Triggers(perms, '{"on":"motion"}'))).assertContain('$.triggers: must be an array');
      const many: string[] = [];
      for (let i = 0; i < 6; i++) {
        many.push('{"on":"motion","do":[{"reset":"n"}]}');
      }
      expect(errorsOf(v1Triggers(perms, `[${many.join(',')}]`))).assertContain('has 6 triggers (max 5)');
      const long = 'x'.repeat(61);
      expect(errorsOf(v1Triggers(perms, `[{"on":"motion","label":"${long}","do":[{"reset":"n"}]}]`)))
        .assertContain('is 61 characters (max 60)');
      expect(errorsOf('{"schemaVersion":0,"id":"x","name":"X","permissions":[],"ui":[],' +
        '"triggers":[{"on":"motion","do":["notify:x"]}]}')).assertContain('unknown field "triggers"');
    });

    it('v1.1: needs the trigger permission and checks trigger steps like button steps', 0, () => {
      expect(errorsOf(v1Triggers('[]', '[{"on":"time","at":"08:00","do":[{"reset":"n"}]}]')))
        .assertContain('$.triggers[0]: a "time" trigger needs permission "reminders"');
      expect(errorsOf(v1Triggers('["reminders"]', '[{"on":"motion","do":[{"reset":"n"}]}]')))
        .assertContain('a "motion" trigger needs permission "motion"');
      expect(errorsOf(v1Triggers('["motion"]', '[{"on":"motion","do":[{"set":"missing","to":"1"}]}]')))
        .assertContain('$.triggers[0].do[0]');
      expect(errorsOf(v1Triggers('["motion"]', '[{"on":"motion","do":[{"set":"n","to":"t"}]}]')))
        .assertContain('"n" is number, but the expression is text');
      expect(errorsOf(v1Triggers('["motion"]', '[{"on":"motion","do":["notify:hi"]}]')))
        .assertContain('$.triggers[0].do[0]: action "notify:hi" needs permission "notifications"');
      expect(errorsOf(v1Triggers('["motion"]', '[{"on":"motion","do":["increment:nope"]}]')))
        .assertContain('refers to id "nope"');
    });

    it('applies permissions and ids to nested components and do-actions', 0, () => {
      expect(errorsOf(v1(NUM, '{}', '[{"type":"row","items":[{"type":"timer","id":"t","label":"T","minutes":1}]}]')))
        .assertContain('needs permission "reminders"');
      expect(errorsOf(v1(NUM, '{}', '[{"type":"button","label":"Go","do":["notify:hi"]}]')))
        .assertContain('$.ui[0].do[0]: action "notify:hi" needs permission "notifications"');
      expect(errorsOf(v1(NUM, '{}', '[{"type":"button","label":"Go","do":["increment:nope"]}]')))
        .assertContain('refers to id "nope"');
    });
  });

  describe('Schema v1: renderer runtime', () => {
    it('presses buttons through the interpreter and updates values', 0, () => {
      const rt = new CapsuleRuntime(load(TENNIS));
      const p1 = button(rt.capsule, 'Point P1');
      for (let i = 0; i < 4; i++) {
        rt.press(p1);
      }
      expect(rt.values['g1']).assertEqual(1);
      expect(rt.values['p1']).assertEqual(0);
      expect(rt.display('Games {g1} - {g2}')).assertEqual('Games 1 - 0');
      expect(rt.message).assertEqual('');
    });

    it('enabledIf disables a button, and pressing it changes nothing', 0, () => {
      const rt = new CapsuleRuntime(load(TENNIS));
      const reset = button(rt.capsule, 'Reset match');
      expect(rt.enabled(reset)).assertFalse();
      rt.press(reset);
      expect(rt.message.length > 0).assertTrue();
      rt.press(button(rt.capsule, 'Point P2'));
      expect(rt.enabled(reset)).assertTrue();
      rt.press(reset);
      expect(rt.values['p2']).assertEqual(0);
    });

    it('a blocked v0 action inside "do" cancels the whole press', 0, () => {
      const c = load(v1('{"n":{"type":"number","initial":0}}', '{}',
        '[{"type":"row","items":[{"type":"counter","id":"k","label":"K","source":"manual"},' +
        '{"type":"button","label":"Go","do":[{"set":"n","to":"n + 1"},"increment:k"]}]}]'));
      const rt = new CapsuleRuntime(c);
      rt.guard = new DenyAll();
      rt.press(button(c, 'Go'));
      expect(rt.values['n']).assertEqual(0);
      expect(rt.counter('k')?.value).assertEqual(0);
      expect(rt.message).assertContain('increment:k');
      rt.guard = undefined;
      rt.press(button(c, 'Go'));
      expect(rt.values['n']).assertEqual(1);
      expect(rt.counter('k')?.value).assertEqual(1);
    });

    it('finds nested components and their block reasons in allComponents order', 0, () => {
      const c = load(TENNIS);
      const rt = new CapsuleRuntime(c);
      const all = allComponents(c.ui);
      rt.blockReasons = all.map((x: CapsuleComponent, i: number) => i === all.length - 1 ? 'denied' : '');
      expect(rt.blockReason(all[all.length - 1])).assertEqual('denied');
      expect(rt.blockReason(button(c, 'Point P1'))).assertEqual('');
    });

    it('inputs keep what is typed and only accept valid numbers', 0, () => {
      const rt = new CapsuleRuntime(load(BILL));
      rt.setInputValue('total', '12.');
      expect(rt.inputValue('total')).assertEqual('12.');
      rt.setInputValue('total', 'abc');
      expect(rt.inputError('total').length > 0).assertTrue();
      expect(rt.values['total']).assertEqual(12);
      rt.setInputValue('total', '90');
      expect(rt.inputError('total')).assertEqual('');
      expect(rt.display('Each pays {each}')).assertEqual('Each pays 45');
      expect(rt.summary()).assertEqual('Each pays 45');
    });
  });
}
