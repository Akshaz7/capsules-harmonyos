import { describe, it, expect } from '@ohos/hypium';
import { Capsule } from '../main/ets/core/CapsuleTypes';
import { BILL_SPLIT_CAPSULE, TENNIS_CAPSULE } from '../main/ets/core/V1Fixtures';
import { CORE_TEMPLATES } from '../main/ets/core/templates/CoreTemplates';
import { fillTemplate } from '../main/ets/core/templates/TemplateLibrary';
import { countOf, detectPattern, PatternPlan } from '../main/ets/renderer/patterns/Detect';

// Shapes from the shipped library and the live "Tasks with weather" capsule (docs/ui-redesign-plan.md section e).
const KM_TO_MILES: string = '{"schemaVersion": 1, "id": "km-to-miles", "name": "Kilometres to miles", "permissions": [], "state": {"km": {"type": "number", "initial": "5"}, "mi": {"type": "number", "initial": 0}}, "computed": {"miles": "round(km * 0.621371, 2)", "kmBack": "round(mi * 1.609344, 2)"}, "ui": [{"type": "input", "bind": "km", "kind": "number", "label": "Kilometres"}, {"type": "display", "text": "{km} km = {miles} miles"}, {"type": "input", "bind": "mi", "kind": "number", "label": "Miles"}, {"type": "display", "text": "{mi} miles = {kmBack} km"}]}';
const VITAMINS: string = '{"schemaVersion": 0, "id": "vitamins-checklist", "name": "Vitamins & medication", "permissions": [], "ui": [{"type": "text", "text": "Morning"}, {"type": "checklist", "id": "morning-list", "items": ["Vitamin D","Iron"]}, {"type": "text", "text": "Evening"}, {"type": "checklist", "id": "evening-list", "items": ["Magnesium"]}]}';
const CAPITALS: string = '{"schemaVersion": 1, "id": "capital-cities-quiz", "name": "Capital cities quiz", "permissions": [], "state": {"q": {"type": "number", "initial": 0}, "score": {"type": "number", "initial": 0}, "last": {"type": "text", "initial": ""}}, "computed": {"country": "if(q == 0, \'France\', if(q == 1, \'Germany\', if(q == 2, \'Italy\', if(q == 3, \'Spain\', if(q == 4, \'Poland\', \'\')))))", "status": "if(q >= 5, \'Finished! Your score: \' + score + \'/5\', \'Question \' + (q + 1) + \'/5: what is the capital of \' + country + \'?\')"}, "ui": [{"type": "display", "text": "{status}"}, {"type": "when", "if": "q == 0", "show": [{"type": "button", "label": "Paris", "do": [{"set": "score", "to": "score + 1"}, {"set": "last", "to": "\'Correct!\'"}, {"set": "q", "to": "q + 1"}]}, {"type": "button", "label": "Berlin", "do": [{"set": "last", "to": "\'Wrong, it was Paris\'"}, {"set": "q", "to": "q + 1"}]}, {"type": "button", "label": "Madrid", "do": [{"set": "last", "to": "\'Wrong, it was Paris\'"}, {"set": "q", "to": "q + 1"}]}]}, {"type": "when", "if": "q == 1", "show": [{"type": "button", "label": "Munich", "do": [{"set": "last", "to": "\'Wrong, it was Berlin\'"}, {"set": "q", "to": "q + 1"}]}, {"type": "button", "label": "Berlin", "do": [{"set": "score", "to": "score + 1"}, {"set": "last", "to": "\'Correct!\'"}, {"set": "q", "to": "q + 1"}]}, {"type": "button", "label": "Hamburg", "do": [{"set": "last", "to": "\'Wrong, it was Berlin\'"}, {"set": "q", "to": "q + 1"}]}]}, {"type": "when", "if": "q == 2", "show": [{"type": "button", "label": "Milan", "do": [{"set": "last", "to": "\'Wrong, it was Rome\'"}, {"set": "q", "to": "q + 1"}]}, {"type": "button", "label": "Naples", "do": [{"set": "last", "to": "\'Wrong, it was Rome\'"}, {"set": "q", "to": "q + 1"}]}, {"type": "button", "label": "Rome", "do": [{"set": "score", "to": "score + 1"}, {"set": "last", "to": "\'Correct!\'"}, {"set": "q", "to": "q + 1"}]}]}, {"type": "when", "if": "q == 3", "show": [{"type": "button", "label": "Madrid", "do": [{"set": "score", "to": "score + 1"}, {"set": "last", "to": "\'Correct!\'"}, {"set": "q", "to": "q + 1"}]}, {"type": "button", "label": "Barcelona", "do": [{"set": "last", "to": "\'Wrong, it was Madrid\'"}, {"set": "q", "to": "q + 1"}]}, {"type": "button", "label": "Seville", "do": [{"set": "last", "to": "\'Wrong, it was Madrid\'"}, {"set": "q", "to": "q + 1"}]}]}, {"type": "when", "if": "q == 4", "show": [{"type": "button", "label": "Kraków", "do": [{"set": "last", "to": "\'Wrong, it was Warsaw\'"}, {"set": "q", "to": "q + 1"}]}, {"type": "button", "label": "Warsaw", "do": [{"set": "score", "to": "score + 1"}, {"set": "last", "to": "\'Correct!\'"}, {"set": "q", "to": "q + 1"}]}, {"type": "button", "label": "Gdańsk", "do": [{"set": "last", "to": "\'Wrong, it was Warsaw\'"}, {"set": "q", "to": "q + 1"}]}]}, {"type": "display", "text": "{last}"}, {"type": "display", "text": "Score: {score}"}, {"type": "button", "label": "Restart", "do": [{"reset": "q"}, {"reset": "score"}, {"reset": "last"}]}]}';
const TASKS: string = '{"schemaVersion": 1, "id": "task-weather", "name": "Tasks with weather", "permissions": [], "state": {"task1": {"type": "text", "initial": "Shop"}, "done1": {"type": "bool", "initial": false}, "task2": {"type": "text", "initial": "Run"}, "done2": {"type": "bool", "initial": false}}, "ui": [{"type": "display", "text": "My tasks"}, {"type": "row", "items": [{"type": "input", "bind": "task1", "kind": "text", "label": "Task 1"}, {"type": "button", "label": "Tick / untick", "do": [{"set": "done1", "to": "not done1"}]}, {"type": "display", "text": "{if(done1, \'[x]\', \'[ ]\')} {task1}"}]}, {"type": "row", "items": [{"type": "input", "bind": "task2", "kind": "text", "label": "Task 2"}, {"type": "button", "label": "Tick / untick", "do": [{"set": "done2", "to": "not done2"}]}, {"type": "display", "text": "{if(done2, \'[x]\', \'[ ]\')} {task2}"}]}]}';
const NOTE: string = '{"schemaVersion": 0, "id": "note", "name": "Note", "permissions": [], "ui": [{"type": "text", "text": "Hello"}, {"type": "counter", "id": "c", "label": "Taps"}]}';

function plan(json: string): PatternPlan {
  return detectPattern(JSON.parse(json) as Capsule);
}

function filled(id: string): Capsule {
  const t = CORE_TEMPLATES.find(x => x.id === id);
  return fillTemplate(t!, t!.name).capsule as Capsule;
}

/** Layout pattern detection (redesign section 6). Pure: no UI, no runtime. */
export default function templatesPatternsTest() {
  describe('TemplatesPatterns', () => {
    it('record_list_from_toggle_rows', 0, () => {
      const p = plan(TASKS);
      expect(p.kind).assertEqual('record-list');
      expect(p.records.length).assertEqual(2);
      expect(p.records[0].boolVar).assertEqual('done1');
      expect(p.records[0].parts.length).assertEqual(2);
    });
    it('versus_tennis', 0, () => {
      const p = plan(TENNIS_CAPSULE);
      expect(p.kind).assertEqual('versus');
      expect(p.sides.length).assertEqual(2);
      expect(p.sides[0].pointsVar).assertEqual('p1');
      expect(p.sides[1].gamesVar).assertEqual('g2');
      expect(p.chips.length).assertEqual(2);
    });
    it('form_bill_split', 0, () => {
      const p = plan(BILL_SPLIT_CAPSULE);
      expect(p.kind).assertEqual('form');
      expect(p.hero !== undefined).assertTrue();
      expect(p.inputs.length >= 2).assertTrue();
    });
    it('converter_before_form', 0, () => {
      const p = plan(KM_TO_MILES);
      expect(p.kind).assertEqual('converter');
      expect(p.pairs.length).assertEqual(2);
      expect(p.pairs[1].input.bind).assertEqual('mi');
    });
    it('timer_ring_pomodoro', 0, () => {
      const p = detectPattern(filled('pomodoro'));
      expect(p.kind).assertEqual('timer-ring');
      expect(p.timers.length).assertEqual(2);
    });
    it('goal_ring_pushups', 0, () => {
      const p = detectPattern(filled('pushups'));
      expect(p.kind).assertEqual('goal-ring');
      expect(p.goal!.countVar).assertEqual('n');
      expect(p.goal!.add!.label).assertEqual('+1');
    });
    it('quiz_before_goal', 0, () => {
      const p = plan(CAPITALS);
      expect(p.kind).assertEqual('quiz');
      expect(p.quiz!.steps.length).assertEqual(5);
      expect(p.quiz!.buttonsInSteps).assertTrue();
    });
    it('grouped_checklist', 0, () => {
      const p = plan(VITAMINS);
      expect(p.kind).assertEqual('grouped-checklist');
      expect(p.groups.length).assertEqual(2);
      expect(p.groups[0].title.text).assertEqual('Morning');
    });
    it('generic_fallback_consumes_nothing', 0, () => {
      const p = plan(NOTE);
      expect(p.kind).assertEqual('generic');
      expect(p.consumed.length).assertEqual(0);
    });
    it('count_of_for_progress_bars', 0, () => {
      expect(countOf('3 of 8 glasses')!.join(',')).assertEqual('3,8');
      expect(countOf('Score 4/5')!.join(',')).assertEqual('4,5');
      expect(countOf('Total 12') === null).assertTrue();
    });
  });
}
