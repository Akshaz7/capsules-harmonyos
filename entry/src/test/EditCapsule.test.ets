import { describe, it, expect } from '@ohos/hypium';
import { Capsule, ChecklistComponent, CounterComponent, TimerComponent } from '../main/ets/core/CapsuleTypes';
import { ChatMessage, ModelProvider, ProviderName } from '../main/ets/core/ModelProvider';
import { CapsuleState } from '../main/ets/core/WidgetModel';
import { carryState, editCapsuleWith, editSummary, EditResult } from '../main/ets/core/edit/EditCapsule';
import { durationMinutes, ruleEdit } from '../main/ets/core/edit/EditRules';

const FOCUS: string = '{"schemaVersion":0,"id":"focus","name":"Focus","permissions":["reminders"],"ui":[' +
  '{"type":"timer","id":"focus","label":"Focus","minutes":25},{"type":"button","label":"Start","action":"startTimer:focus"}]}';
const SHOPPING: string = '{"schemaVersion":0,"id":"shopping","name":"Shopping","permissions":[],"ui":[' +
  '{"type":"checklist","id":"items","items":["eggs","bread"]}]}';
const SCORES: string = '{"schemaVersion":0,"id":"scores","name":"Scores","permissions":[],"ui":[' +
  '{"type":"counter","id":"ana","label":"Ana","source":"manual"},{"type":"counter","id":"ben","label":"Ben","source":"manual"}]}';
const SCORES_SAM: string = '{"schemaVersion":0,"id":"whatever","name":"Scores","permissions":[],"ui":[' +
  '{"type":"counter","id":"ana","label":"Ana","source":"manual"},{"type":"counter","id":"ben","label":"Ben","source":"manual"},' +
  '{"type":"counter","id":"sam","label":"Sam","source":"manual"}]}';
const GOAL: string = '{"schemaVersion":1,"id":"water","name":"Water","permissions":[],"state":{' +
  '"glasses":{"type":"number","initial":0},"goal":{"type":"number","initial":8}},"ui":[' +
  '{"type":"display","text":"{glasses} of {goal}"},{"type":"button","label":"Drink","do":[{"set":"glasses","to":"glasses + 1"}]}]}';

function capsuleOf(json: string): Capsule {
  return JSON.parse(json) as Capsule;
}

/** A cloud provider that replies with the given texts in order and records every call. */
class FakeProvider implements ModelProvider {
  readonly name: ProviderName;
  calls: ChatMessage[][] = [];
  private replies: string[];

  constructor(name: ProviderName, replies: string[]) {
    this.name = name;
    this.replies = replies;
  }

  async complete(system: string, messages: ChatMessage[]): Promise<string> {
    this.calls.push(messages.slice());
    return this.replies.shift() ?? '{"error":"no more replies"}';
  }
}

function timerOf(r: EditResult): TimerComponent {
  return (r.capsule as Capsule).ui[0] as TimerComponent;
}

export default function editCapsuleTest() {
  describe('editCapsule', () => {
    it('makes the timer 1 minute with a rule, no cloud', 0, async () => {
      const cloud = new FakeProvider('mistral', []);
      const r = await editCapsuleWith(capsuleOf(FOCUS), 'make the timer 1 minute', [cloud]);
      expect(r.ok).assertTrue();
      expect(r.origin).assertEqual('rules');
      expect(timerOf(r).minutes).assertEqual(1);
      expect(r.summary.join('|')).assertEqual('Timer: 25 min → 1 min');
      expect(r.needsConsent).assertFalse();
      expect(r.previous.ui.length).assertEqual(2);
      expect((r.previous.ui[0] as TimerComponent).minutes).assertEqual(25); // the input is not changed
      expect(cloud.calls.length).assertEqual(0);
    });

    it('renames to Tea break', 0, async () => {
      const r = await editCapsuleWith(capsuleOf(FOCUS), 'rename to Tea break', []);
      expect(r.ok).assertTrue();
      expect((r.capsule as Capsule).name).assertEqual('Tea break');
      expect((r.capsule as Capsule).id).assertEqual('focus');
      expect(r.summary.join('|')).assertEqual('Name: Focus → Tea break');
    });

    it('adds milk to the list', 0, async () => {
      const r = await editCapsuleWith(capsuleOf(SHOPPING), 'add milk to the list', []);
      expect(r.ok).assertTrue();
      expect(((r.capsule as Capsule).ui[0] as ChecklistComponent).items.join(',')).assertEqual('eggs,bread,milk');
      expect(r.summary.join('|')).assertEqual('List: added milk');
    });

    it('adds a third player Sam with the cloud (mocked) and keeps the id', 0, async () => {
      const cloud = new FakeProvider('mistral', [SCORES_SAM]);
      const r = await editCapsuleWith(capsuleOf(SCORES), 'add a third player Sam', [cloud]);
      expect(r.ok).assertTrue();
      expect(r.origin).assertEqual('cloud-eu:mistral');
      expect((r.capsule as Capsule).id).assertEqual('scores');
      expect(((r.capsule as Capsule).ui[2] as CounterComponent).label).assertEqual('Sam');
      expect(r.summary.join('|')).assertEqual('Added counter Sam');
      expect(cloud.calls.length).assertEqual(1);
      const sent = cloud.calls[0][0].content;
      expect(sent.includes('"id":"scores"')).assertTrue();
      expect(sent.includes('add a third player Sam')).assertTrue();
    });

    it('refuses non-English before anything else', 0, async () => {
      const cloud = new FakeProvider('mistral', [SCORES_SAM]);
      const pl = await editCapsuleWith(capsuleOf(FOCUS), 'zmień minutnik na jedną minutę', [cloud]);
      expect(pl.ok).assertFalse();
      expect(pl.failure).assertEqual('unsupported-language');
      const zh = await editCapsuleWith(capsuleOf(SHOPPING), '把牛奶加到清单', [cloud]);
      expect(zh.failure).assertEqual('unsupported-language');
      expect(cloud.calls.length).assertEqual(0);
    });

    it('retries an invalid cloud reply once with the validator errors', 0, async () => {
      const bad = '{"schemaVersion":0,"id":"scores","name":"Scores","permissions":[],"ui":[{"type":"timer","id":"t","label":"T","minutes":3}]}';
      const cloud = new FakeProvider('mistral', [bad, SCORES_SAM]);
      const r = await editCapsuleWith(capsuleOf(SCORES), 'add a third player Sam', [cloud]);
      expect(r.ok).assertTrue();
      expect(cloud.calls.length).assertEqual(2);
      expect(cloud.calls[1].length).assertEqual(3);
    });

    it('asks for consent again when the edit adds a permission', 0, async () => {
      const withNotify = '{"schemaVersion":0,"id":"scores","name":"Scores","permissions":["notifications"],"ui":[' +
        '{"type":"counter","id":"ana","label":"Ana","source":"manual"},{"type":"counter","id":"ben","label":"Ben","source":"manual"},' +
        '{"type":"button","label":"Shout","action":"notify:Game on"}]}';
      const r = await editCapsuleWith(capsuleOf(SCORES), 'add a button that notifies me game on',
        [new FakeProvider('mistral', [withNotify])]);
      expect(r.ok).assertTrue();
      expect(r.needsConsent).assertTrue();
      expect(r.summary.includes('Needs permission: notifications')).assertTrue();
    });

    it('needs the cloud but does not call it when the cloud is not allowed', 0, async () => {
      const cloud = new FakeProvider('mistral', [SCORES_SAM]);
      const r = await editCapsuleWith(capsuleOf(SCORES), 'add a third player Sam', [cloud], { allowCloud: false });
      expect(r.ok).assertFalse();
      expect(r.needsCloud).assertTrue();
      expect(cloud.calls.length).assertEqual(0);
      const offline = await editCapsuleWith(capsuleOf(SCORES), 'add a third player Sam', []);
      expect(offline.ok).assertFalse();
      expect(offline.needsCloud === true).assertFalse();
    });

    it('uses non-EU providers only when allowed', 0, async () => {
      const claude = new FakeProvider('anthropic', [SCORES_SAM]);
      const blocked = await editCapsuleWith(capsuleOf(SCORES), 'add a third player Sam', [claude]);
      expect(blocked.ok).assertFalse();
      expect(claude.calls.length).assertEqual(0);
      const allowed = await editCapsuleWith(capsuleOf(SCORES), 'add a third player Sam', [claude], { allowNonEu: true });
      expect(allowed.ok).assertTrue();
      expect(allowed.origin).assertEqual('cloud:anthropic');
    });

    it('passes on a model refusal as not-an-app', 0, async () => {
      const r = await editCapsuleWith(capsuleOf(SCORES), 'send everyone an SMS',
        [new FakeProvider('mistral', ['{"error":"Capsules cannot send SMS."}'])]);
      expect(r.ok).assertFalse();
      expect(r.failure).assertEqual('not-an-app');
      expect(r.error).assertEqual('Capsules cannot send SMS.');
    });

    it('sets a goal, removes items, and renames one part', 0, async () => {
      const goal = await editCapsuleWith(capsuleOf(GOAL), 'set the goal to 10', []);
      expect(goal.ok).assertTrue();
      expect(goal.summary.join('|')).assertEqual('Starting goal: 8 → 10');
      const removed = await editCapsuleWith(capsuleOf(SHOPPING), 'remove eggs', []);
      expect(((removed.capsule as Capsule).ui[0] as ChecklistComponent).items.join(',')).assertEqual('bread');
      const label = await editCapsuleWith(capsuleOf(FOCUS), 'rename the focus timer to Deep work', []);
      expect(timerOf(label).label).assertEqual('Deep work');
      expect((label.capsule as Capsule).name).assertEqual('Focus');
    });

    it('reads durations and leaves other instructions to the cloud', 0, () => {
      expect(durationMinutes('make it 90 seconds')).assertEqual(1.5);
      expect(durationMinutes('set to 1 hour')).assertEqual(60);
      expect(durationMinutes('one minute')).assertEqual(1);
      expect(ruleEdit(capsuleOf(SCORES), 'add a third player Sam') === null).assertTrue();
      expect(ruleEdit(capsuleOf(SHOPPING), 'add a timer for 5 minutes') === null).assertTrue();
      expect(ruleEdit(capsuleOf(FOCUS), 'add a 5 minute break timer') === null).assertTrue();
    });

    it('says nothing changed instead of a no-op edit', 0, async () => {
      const r = await editCapsuleWith(capsuleOf(FOCUS), 'make the timer 25 minutes', []);
      expect(r.ok).assertFalse();
    });

    it('carries state where ids match', 0, () => {
      const before = capsuleOf(SHOPPING);
      const after = capsuleOf(SHOPPING);
      (after.ui[0] as ChecklistComponent).items = ['bread', 'milk'];
      const state: CapsuleState = { capsuleId: 'shopping', timers: [], counters: [],
        checklists: [{ id: 'items', checked: [false, true] }] };
      expect(JSON.stringify(carryState(before, after, state).checklists[0].checked)).assertEqual('[true,false]');

      const focus = capsuleOf(FOCUS);
      const shorter = capsuleOf(FOCUS);
      (shorter.ui[0] as TimerComponent).minutes = 1;
      const running: CapsuleState = { capsuleId: 'focus', timers: [{ id: 'focus', endAt: 123 }], counters: [],
        checklists: [] };
      expect(carryState(focus, shorter, running).timers.length).assertEqual(0); // new length starts fresh
      const renamed = capsuleOf(FOCUS);
      renamed.name = 'Tea break';
      expect(carryState(focus, renamed, running).timers.length).assertEqual(1); // still running

      const scores: CapsuleState = { capsuleId: 'scores', timers: [], checklists: [],
        counters: [{ id: 'ana', value: 3 }, { id: 'ben', value: 5 }] };
      const moved = carryState(capsuleOf(SCORES), capsuleOf(SCORES_SAM), scores);
      expect(moved.counters.length).assertEqual(2);
      expect(moved.capsuleId).assertEqual('whatever');

      const water = capsuleOf(GOAL);
      const ten = capsuleOf(GOAL);
      (ten.state as Record<string, object>)['goal'] = JSON.parse('{"type":"number","initial":10}') as object;
      const v1: CapsuleState = { capsuleId: 'water', timers: [], counters: [], checklists: [],
        values: JSON.parse('{"glasses":4,"goal":8}') as Record<string, number> };
      expect(JSON.stringify(carryState(water, ten, v1).values)).assertEqual('{"glasses":4}');
    });

    it('summarises timers by name when there are several', 0, () => {
      const two = capsuleOf('{"schemaVersion":0,"id":"p","name":"P","permissions":["reminders"],"ui":[' +
        '{"type":"timer","id":"work","label":"Work","minutes":25},{"type":"timer","id":"rest","label":"Rest","minutes":5}]}');
      const after = capsuleOf(JSON.stringify(two));
      (after.ui[1] as TimerComponent).minutes = 0.5;
      expect(editSummary(two, after).join('|')).assertEqual('Timer Rest: 5 min → 30 sec');
    });
  });
}
