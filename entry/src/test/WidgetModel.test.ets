import { describe, it, expect } from '@ohos/hypium';
import {
  applyWidgetMessage, buildWidgetView, CapsuleState, declaredAction, GateFacts, initialState, parseState,
  parseWidgetMessage, pickCapsuleForNewWidget, SavedCapsule, WidgetMessage, WidgetRow,
  BLANK_WIDGET_MESSAGE, emptyView, firstBlank, planWidgetAssignments, WidgetBindingFact
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

function blank(formId: string): WidgetBindingFact {
  return { formId: formId, capsuleId: '', wide: false };
}

function shown(bindings: WidgetBindingFact[]): string {
  return bindings.map((b: WidgetBindingFact) => `${b.formId}=${b.capsuleId.length > 0 ? b.capsuleId : '-'}`).join(' ');
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
        { capsule: rules('medication 8am and 8pm'), savedAt: 2 },
        { capsule: rules('water 8 glasses'), savedAt: 3 }, // v1: app only
        { capsule: rules('4 timers a 1 b 2 c 3 d 4'), savedAt: 5 }, // too many components
        { capsule: rules('split 84 between 4'), savedAt: 4 } // v1: app only
      ];
      expect(pickCapsuleForNewWidget(saved, (id: string) => false)?.id).assertEqual('schedule-medication');
      expect(pickCapsuleForNewWidget(saved, (id: string) => id === 'schedule-medication')?.id)
        .assertEqual('count-coffees');
      expect(pickCapsuleForNewWidget([], (id: string) => false)).assertNull();
    });
  });

  describe('Widget assignment', () => {
    const never = (id: string): boolean => false;

    it('fills blank widgets with new capsules, oldest new capsule first, in widget order', 0, () => {
      const coffees = rules('count coffees');
      const meds = rules('medication 8am and 8pm');
      // Two blank widgets; nothing seen yet except what existed before.
      const first = planWidgetAssignments([blank('20'), blank('9')], [coffees], [], never);
      expect(shown(first.bindings)).assertEqual('9=count-coffees 20=-');
      expect(first.changed.join()).assertEqual('9');
      // Second capsule created (saved list is newest first).
      const second = planWidgetAssignments(first.bindings, [meds, coffees], first.seen, never);
      expect(shown(second.bindings)).assertEqual('9=count-coffees 20=schedule-medication');
      expect(second.changed.join()).assertEqual('20');
      // Nothing new: nothing changes.
      const again = planWidgetAssignments(second.bindings, [meds, coffees], second.seen, never);
      expect(again.changed.length).assertEqual(0);
    });

    it('blanks a widget when its capsule is removed, and keeps it blank', 0, () => {
      const coffees = rules('count coffees');
      const meds = rules('medication 8am and 8pm');
      const bound: WidgetBindingFact[] = [{ formId: '1', capsuleId: 'count-coffees', wide: false },
        { formId: '2', capsuleId: 'schedule-medication', wide: true }];
      const gone = planWidgetAssignments(bound, [coffees], ['count-coffees', 'schedule-medication'], never);
      expect(shown(gone.bindings)).assertEqual('1=count-coffees 2=-');
      expect(gone.changed.join()).assertEqual('2');
      expect(gone.seen.join()).assertEqual('count-coffees');
      expect(gone.bindings[1].wide).assertTrue();
      // Undo marks a capsule removed while it is still in the saved list: the widget also goes blank.
      const undone = planWidgetAssignments(bound, [meds, coffees], ['count-coffees', 'schedule-medication'],
        (id: string) => id === 'count-coffees');
      expect(shown(undone.bindings)).assertEqual('1=- 2=schedule-medication');
      // An existing capsule is not pushed back onto the blank widget.
      const later = planWidgetAssignments(gone.bindings, [coffees], gone.seen, never);
      expect(later.changed.length).assertEqual(0);
    });

    it('skips app-only capsules, capsules already shown, and existing capsules on the first run', 0, () => {
      const water = rules('water 8 glasses'); // v1: app only
      const coffees = rules('count coffees');
      const appOnly = planWidgetAssignments([blank('1')], [water], [], never);
      expect(shown(appOnly.bindings)).assertEqual('1=-');
      const already = planWidgetAssignments([{ formId: '1', capsuleId: 'count-coffees', wide: false }, blank('2')],
        [coffees], [], never);
      expect(shown(already.bindings)).assertEqual('1=count-coffees 2=-');
      const firstRun = planWidgetAssignments([blank('1')], [coffees], null, never);
      expect(shown(firstRun.bindings)).assertEqual('1=-');
      expect(firstRun.seen.join()).assertEqual('count-coffees');
    });

    it('finds the first blank widget and says "Tap to choose a capsule"', 0, () => {
      expect(firstBlank([{ formId: '30', capsuleId: 'x', wide: false }, blank('31'), blank('4')])?.formId)
        .assertEqual('4');
      expect(firstBlank([{ formId: '1', capsuleId: 'x', wide: false }])).assertNull();
      expect(emptyView(false).message).assertEqual(BLANK_WIDGET_MESSAGE);
      expect(BLANK_WIDGET_MESSAGE).assertEqual('Tap to choose a capsule');
    });
  });
}
