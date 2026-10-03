import { describe, it, expect } from '@ohos/hypium';
import {
  applyWidgetMessage, buildWidgetView, CapsuleState, declaredAction, GateFacts, initialState, parseState,
  parseWidgetMessage, pickCapsuleForNewWidget, SavedCapsule, WidgetMessage, WidgetRow
} from '../main/ets/core/WidgetModel';
import { parseRequest } from '../main/ets/core/RuleParser';
import { validateCapsule } from '../main/ets/core/CapsuleValidator';
import { Capsule, Permission } from '../main/ets/core/CapsuleTypes';

const NOW: number = 1700000000000;

function rules(request: string): Capsule {
  return parseRequest(request) as Capsule;
}

function capsuleOf(json: string): Capsule {
  const r = validateCapsule(json);
  expect(r.errors.join('\n')).assertEqual('');
  return r.capsule as Capsule;
}

function gate(granted: Permission[], decided: boolean, removed: boolean): GateFacts {
  return { granted: granted, decided: decided, removed: removed };
}

function msg(op: string, id: string, index: number): WidgetMessage {
  return parseWidgetMessage(`{"op":"${op}","id":"${id}","index":${index}}`) as WidgetMessage;
}

export default function widgetModelTest() {
  describe('WidgetModel', () => {
    it('shows timers with start controls when reminders are granted', 0, () => {
      const c = rules('3 timers pasta 9 sauce 15 bread 6');
      const v = buildWidgetView(c, initialState(c), gate(['reminders'], true, false), NOW, false);
      expect(v.status).assertEqual('ok');
      expect(v.rows.length).assertEqual(3);
      expect(v.rows[0].kind).assertEqual('timer');
      expect(v.rows[0].canStart).assertTrue();
      expect(v.rows[1].minutes).assertEqual(15);
      expect(v.message).assertEqual('');
    });

    it('hides timers the gatekeeper has not allowed', 0, () => {
      const c = rules('3 timers pasta 9 sauce 15 bread 6');
      const denied = buildWidgetView(c, initialState(c), gate([], true, false), NOW, false);
      expect(denied.rows.length).assertEqual(0);
      expect(denied.message).assertEqual('3 items blocked by the gatekeeper.');
      const undecided = buildWidgetView(c, initialState(c), gate([], false, false), NOW, false);
      expect(undecided.message).assertEqual('Open the app to allow permissions.');
    });

    it('shows a + only for counters whose capsule declares increment', 0, () => {
      const c = rules('count coffees');
      const v = buildWidgetView(c, initialState(c), gate([], true, false), NOW, true);
      expect(v.rows[0].canIncrement).assertTrue();
      expect(v.wide).assertTrue();
      const noButton = capsuleOf('{"schemaVersion":0,"id":"k","name":"K","permissions":[],' +
        '"ui":[{"type":"counter","id":"k","label":"K","source":"manual"}]}');
      expect(buildWidgetView(noButton, initialState(noButton), gate([], true, false), NOW, false).rows[0].canIncrement)
        .assertFalse();
    });

    it('hides a motion counter without the motion grant', 0, () => {
      const c = rules('count my squats');
      expect(buildWidgetView(c, initialState(c), gate([], true, false), NOW, false).rows.length).assertEqual(0);
      expect(buildWidgetView(c, initialState(c), gate(['motion'], true, false), NOW, false).rows.length).assertEqual(1);
    });

    it('shows checklists and text, and marks removed capsules', 0, () => {
      const c = rules('medication 8am and 8pm');
      const v = buildWidgetView(c, initialState(c), gate([], true, false), NOW, false);
      expect(v.rows.map((r: WidgetRow) => r.kind).join(',')).assertEqual('text,checklist');
      expect(v.rows[1].items.length).assertEqual(2);
      expect(buildWidgetView(c, initialState(c), gate([], true, true), NOW, false).status).assertEqual('removed');
    });

    it('never draws a capsule that is not widget-suitable', 0, () => {
      const c = rules('4 timers a 1 b 2 c 3 d 4');
      const v = buildWidgetView(c, initialState(c), gate(['reminders'], true, false), NOW, false);
      expect(v.status).assertEqual('empty');
      expect(v.rows.length).assertEqual(0);
    });

    it('maps taps to declared actions only', 0, () => {
      const timers = rules('3 timers pasta 9 sauce 15 bread 6');
      expect(declaredAction(timers, msg('start', 'pasta', -1))).assertEqual('startTimer:pasta');
      expect(declaredAction(timers, msg('start', 'nope', -1))).assertNull();
      expect(declaredAction(timers, msg('increment', 'pasta', -1))).assertNull();
      const meds = rules('medication 8am and 8pm');
      expect(declaredAction(meds, msg('toggle', 'medication-doses', 1))).assertEqual('');
      expect(declaredAction(meds, msg('toggle', 'medication-doses', 2))).assertNull();
    });

    it('applies taps without mutating the old state', 0, () => {
      const c = rules('3 timers pasta 9 sauce 15 bread 6');
      const s0 = initialState(c);
      const s1 = applyWidgetMessage(c, s0, msg('start', 'pasta', -1), NOW);
      expect(s1.timers[0].endAt).assertEqual(NOW + 9 * 60000);
      expect(s0.timers[0].endAt).assertEqual(0);
      // starting a running timer again does not restart it
      expect(applyWidgetMessage(c, s1, msg('start', 'pasta', -1), NOW + 1000).timers[0].endAt).assertEqual(NOW + 540000);
      const k = rules('count coffees');
      expect(applyWidgetMessage(k, initialState(k), msg('increment', 'coffees', -1), NOW).counters[0].value).assertEqual(1);
      const m = rules('medication 8am and 8pm');
      expect(applyWidgetMessage(m, initialState(m), msg('toggle', 'medication-doses', 1), NOW).checklists[0].checked[1])
        .assertTrue();
    });

    it('restores saved state and ignores bad records', 0, () => {
      const c = rules('count coffees');
      const saved: CapsuleState = applyWidgetMessage(c, initialState(c), msg('increment', 'coffees', -1), NOW);
      expect(parseState(c, JSON.stringify(saved)).counters[0].value).assertEqual(1);
      expect(parseState(c, 'garbage').counters[0].value).assertEqual(0);
      expect(parseState(c, '{"capsuleId":"other","counters":[{"id":"coffees","value":5}]}').counters[0].value)
        .assertEqual(0);
      expect(parseState(c, '{"capsuleId":"count-coffees","counters":[{"id":"coffees","value":-3}]}').counters[0].value)
        .assertEqual(0);
    });

    it('rejects unknown widget messages', 0, () => {
      expect(parseWidgetMessage('{"op":"delete","id":"x"}')).assertNull();
      expect(parseWidgetMessage('nope')).assertNull();
      expect(parseWidgetMessage('{"op":"refresh"}')?.op).assertEqual('refresh');
    });

    it('picks the most recent widget-suitable, not-removed capsule for a new widget', 0, () => {
      const saved: SavedCapsule[] = [
        { capsule: rules('count coffees'), savedAt: 1 },
        { capsule: rules('water 8 glasses'), savedAt: 3 },
        { capsule: rules('4 timers a 1 b 2 c 3 d 4'), savedAt: 5 },
        { capsule: rules('split 84 between 4'), savedAt: 4 }
      ];
      expect(pickCapsuleForNewWidget(saved, (id: string) => false)?.id).assertEqual('split-84-4');
      expect(pickCapsuleForNewWidget(saved, (id: string) => id === 'split-84-4')?.id).assertEqual('goal-water');
      expect(pickCapsuleForNewWidget([], (id: string) => false)).assertNull();
    });
  });
}
