import { describe, it, expect } from '@ohos/hypium';
import {
  applyWidgetMessage, buildWidgetView, CapsuleState, declaredAction, GateFacts, initialState, parseState,
  parseWidgetMessage, pickCapsuleForNewWidget, SavedCapsule, WidgetMessage, WidgetRow,
  BLANK_WIDGET_MESSAGE, emptyView, firstBlank, planWidgetAssignments, WidgetBindingFact,
  accentFor, capsuleForNewWidget, displayFor, PENDING_TTL_MS, PendingCapsule, pickColorTag, pressWidgetButton, applyV0Action, TimerRun, stableColorTag, WidgetButton, WidgetDisplay, WIDGET_PALETTE, withColor
} from '../main/ets/core/WidgetModel';
import { TENNIS_CAPSULE } from '../main/ets/core/V1Fixtures';
import { StateValues } from '../main/ets/core/CapsuleProgram';
import { parseRequest } from '../main/ets/core/RuleParser';
import { routeCapsule } from '../main/ets/core/CapsuleRouter';
import { validateCapsule } from '../main/ets/core/CapsuleValidator';
import { Capsule, ChecklistComponent, Permission } from '../main/ets/core/CapsuleTypes';

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

function blank(formId: string, addedAt?: number): WidgetBindingFact {
  return { formId: formId, capsuleId: '', wide: false, addedAt: addedAt };
}

function shown(bindings: WidgetBindingFact[]): string {
  return bindings.map((b: WidgetBindingFact) => `${b.formId}=${b.capsuleId.length > 0 ? b.capsuleId : '-'}`).join(' ');
}

function allowAll(action: string): boolean {
  return true;
}

function denyTimers(action: string): boolean {
  return !action.startsWith('startTimer') && !action.startsWith('stopTimer');
}

function runningIds(state: CapsuleState, now: number): string {
  return state.timers.filter((t: TimerRun) => t.endAt > now).map((t: TimerRun) => t.id).join(',');
}

function availableExceptGone(id: string): boolean {
  return id !== 'gone';
}

function noneRemoved(id: string): boolean {
  return false;
}

function displaySummary(d: WidgetDisplay): string {
  return d.kind === 'score' ? `${d.label}[${d.left}|${d.right}]` : d.text;
}

function goalValues(count: number): StateValues {
  const v: StateValues = {};
  v['count'] = count;
  return v;
}

function tennisValues(): StateValues {
  const v: StateValues = {};
  v['p1'] = 2;
  v['p2'] = 1;
  v['g1'] = 3;
  v['g2'] = 2;
  return v;
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

    it('never draws a motion capsule: motion runs only while the capsule is open in the app', 0, () => {
      const c = rules('count my shakes');
      const route = routeCapsule(c);
      expect(route.widget).assertFalse();
      expect(route.reason).assertContain('motion');
      const view = buildWidgetView(c, initialState(c), gate([], true, false), NOW, false);
      expect(view.rows.length).assertEqual(0);
      // App-only capsules end with "Tap to open" (the motion widget also says why).
      expect(view.message).assertContain('Tap to open');
      expect(buildWidgetView(c, initialState(c), gate(['motion'], true, false), NOW, false).rows.length).assertEqual(0);
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
        { capsule: rules('split 84 between 4'), savedAt: 3 }, // v1 with inputs: app only
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
      // Form ids are not ordered: '20' was added first even though '3428806' is shorter.
      const first = planWidgetAssignments([blank('3428806', 200), blank('20', 100)], [coffees], [], never);
      expect(shown(first.bindings)).assertEqual('20=count-coffees 3428806=-');
      expect(first.changed.join()).assertEqual('20');
      // Second capsule created (saved list is newest first).
      const second = planWidgetAssignments(first.bindings, [meds, coffees], first.seen, never);
      expect(shown(second.bindings)).assertEqual('20=count-coffees 3428806=schedule-medication');
      expect(second.changed.join()).assertEqual('3428806');
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
      const water = rules('split 84 between 4'); // v1 with inputs: app only
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
      expect(firstBlank([{ formId: '30', capsuleId: 'x', wide: false }, blank('4', 9), blank('31', 5)])?.formId)
        .assertEqual('31');
      expect(firstBlank([blank('4', 9), blank('77')])?.formId).assertEqual('77'); // no addedAt: oldest
      expect(firstBlank([{ formId: '1', capsuleId: 'x', wide: false }])).assertNull();
      expect(emptyView(false).message).assertEqual(BLANK_WIDGET_MESSAGE);
      expect(BLANK_WIDGET_MESSAGE).assertEqual('Tap to choose a capsule');
    });

    it('fills the card with one main element per v0 type (T4-15)', 0, () => {
      const all = gate(['reminders', 'motion', 'notifications'], true, false);
      const counter = rules('count coffees');
      const cv = buildWidgetView(counter, initialState(counter), all, 0, false);
      expect(`${cv.layout} ${cv.icon}`).assertEqual('counter counter');
      const timer = rules('tea 4 min');
      expect(buildWidgetView(timer, initialState(timer), all, 0, false).layout).assertEqual('timer');
      const list = rules('checklist: passport, keys, charger');
      const ticked = applyWidgetMessage(list, initialState(list), msg('toggle', list.ui[0].type === 'checklist' ?
        (list.ui[0] as ChecklistComponent).id : '', 1), 0);
      const lv = buildWidgetView(list, ticked, all, 0, true);
      expect(`${lv.layout} ${lv.icon} ${lv.caption}`).assertEqual('checklist checklist 1 / 3 done');
      const three = rules('3 timers pasta 9 sauce 15 bread 6');
      expect(buildWidgetView(three, initialState(three), all, 0, false).layout).assertEqual('rows');
      const blank = emptyView(false);
      expect(`${blank.layout} ${blank.icon} ${blank.message}`).assertEqual('message blank Tap to choose a capsule');
    });

    it('a v1 goal counter becomes a ring with its value, goal and what is left (T4-15)', 0, () => {
      const water = rules('water 8 glasses');
      const v = buildWidgetView(water, initialState(water), gate([], true, false), 0, false, goalValues(3));
      expect(`${v.layout} ${v.icon} ${v.value}/${v.goal}`).assertEqual('goal goal 3/8');
      expect(v.caption).assertEqual('5 to go');
      expect(v.buttons.map((b: WidgetButton) => `${b.index}:${b.label}:${b.enabled}`).join(' ')).assertEqual('0:+1 glass:true 1:Reset:true');
      const done = buildWidgetView(water, initialState(water), gate([], true, false), 0, false, goalValues(8));
      expect(done.caption).assertEqual('0 to go · Goal reached!');
    });

    it('tennis becomes score lines and point buttons (T4-15, wired by T4-14)', 0, () => {
      const tennis = capsuleOf(TENNIS_CAPSULE);
      const v = buildWidgetView(tennis, initialState(tennis), gate([], true, false), 0, true, tennisValues());
      expect(`${v.layout} ${v.icon}`).assertEqual('logic logic');
      expect(v.displays.map(displaySummary).join(' | ')).assertEqual('Games[3|2] | [30|15] | P1 leads');
      expect(v.buttons.map((b: WidgetButton) => b.label).join(',')).assertEqual('Point P1,Point P2,Reset match');
      const fresh = buildWidgetView(tennis, initialState(tennis), gate([], true, false), 0, false, {});
      expect(fresh.displays.length).assertEqual(2); // "P1 leads" is hidden until a game is won
      expect(fresh.buttons[2].enabled).assertFalse(); // Reset match: enabledIf
    });

    it('score lines only for short values on both sides', 0, () => {
      expect(displaySummary(displayFor('a', 'Games 2 - 1'))).assertEqual('Games[2|1]');
      expect(displaySummary(displayFor('b', 'Deuce'))).assertEqual('Deuce');
      expect(displaySummary(displayFor('c', 'Each pays: 21'))).assertEqual('Each pays: 21');
      expect(displaySummary(displayFor('d', 'Advantage P1'))).assertEqual('Advantage P1');
    });

    it('each widget keeps its own accent colour (colorTag)', 0, () => {
      expect(pickColorTag([], '5')).assertEqual(0);
      expect(pickColorTag([0, 1], '5')).assertEqual(2);
      const full = WIDGET_PALETTE.map((c: string, i: number) => i);
      expect(pickColorTag(full, '12345')).assertEqual(stableColorTag('12345'));
      expect(stableColorTag('12345')).assertEqual(stableColorTag('12345'));
      expect(accentFor(WIDGET_PALETTE.length + 1)).assertEqual(WIDGET_PALETTE[1]);
      const v = withColor(emptyView(false), 3);
      expect(`${v.colorTag} ${v.accent}`).assertEqual(`3 ${WIDGET_PALETTE[3]}`);
      const kept = planWidgetAssignments([{ formId: '1', capsuleId: '', wide: false, colorTag: 4 }], [], [], noneRemoved);
      expect(kept.bindings[0].colorTag).assertEqual(4);
    });

    it('pomodoro buttons run on the widget: Start break stops focus, Start focus stops break (T4-14)', 0, () => {
      const pomodoro = rules('pomodoro 50/10');
      const s0 = initialState(pomodoro);
      expect(declaredAction(pomodoro, msg('press', '', 0))).assertEqual('');
      const focus = pressWidgetButton(pomodoro, s0, 0, 1000, allowAll);
      expect(focus.ok).assertTrue();
      expect(runningIds(focus.state, 1000)).assertEqual('focus');
      expect(focus.state.timers[0].endAt).assertEqual(1000 + 50 * 60000);
      const brk = pressWidgetButton(pomodoro, focus.state, 1, 5000, allowAll);
      expect(brk.actions.join(', ')).assertEqual('stopTimer:focus, startTimer:break');
      expect(runningIds(brk.state, 5000)).assertEqual('break');
      const back = pressWidgetButton(pomodoro, brk.state, 0, 9000, allowAll);
      expect(runningIds(back.state, 9000)).assertEqual('focus');
      const view = buildWidgetView(pomodoro, back.state, gate(['reminders'], true, false), 9000, false);
      expect(`${view.layout} ${view.icon} ${view.rows.length} ${view.buttons.length}`).assertEqual('logic timer 2 2');
    });

    it('a blocked action or a disabled button changes nothing (T4-14)', 0, () => {
      const pomodoro = rules('pomodoro');
      const s0 = initialState(pomodoro);
      const blocked = pressWidgetButton(pomodoro, s0, 0, 1000, denyTimers);
      expect(blocked.ok).assertFalse();
      expect(blocked.blocked).assertContain('stopTimer:break');
      expect(runningIds(blocked.state, 1000)).assertEqual('');
      const tennis = capsuleOf(TENNIS_CAPSULE);
      const reset = pressWidgetButton(tennis, initialState(tennis), 2, 0, allowAll); // Reset match: enabledIf false
      expect(reset.ok).assertFalse();
      expect(pressWidgetButton(tennis, initialState(tennis), 9, 0, allowAll).error).assertEqual('no button 9');
    });

    it('tennis point and goal +1 update v1 values that survive a save and load (T4-14)', 0, () => {
      const tennis = capsuleOf(TENNIS_CAPSULE);
      let s = initialState(tennis);
      for (let i = 0; i < 4; i++) {
        s = pressWidgetButton(tennis, s, 0, 0, allowAll).state; // four points to P1: one game
      }
      const loaded = parseState(tennis, JSON.stringify(s));
      expect(`${loaded.values?.['g1']} ${loaded.values?.['p1']}`).assertEqual('1 0');
      const v = buildWidgetView(tennis, loaded, gate([], true, false), 0, true);
      expect(v.displays.map(displaySummary).join(' | ')).assertEqual('Games[1|0] | [0|0] | P1 leads');
      const water = rules('water 8 glasses');
      const plus = pressWidgetButton(water, initialState(water), 0, 0, allowAll);
      const wv = buildWidgetView(water, plus.state, gate([], true, false), 0, false);
      expect(`${wv.value}/${wv.goal}`).assertEqual('1/8');
    });

    it('pause keeps the time left and start resumes from it', 0, () => {
      const timer = rules('tea 4 min');
      const s = initialState(timer);
      applyV0Action(timer, s, 'startTimer:tea', 0);
      applyV0Action(timer, s, 'pauseTimer:tea', 60000);
      expect(`${s.timers[0].endAt} ${s.timers[0].pausedLeft}`).assertEqual('0 180000');
      const reloaded = parseState(timer, JSON.stringify(s));
      applyV0Action(timer, reloaded, 'startTimer:tea', 100000);
      expect(reloaded.timers[0].endAt).assertEqual(280000);
      applyV0Action(timer, reloaded, 'stopTimer:tea', 110000);
      expect(reloaded.timers[0].endAt).assertEqual(0);
    });

    it('Add to home screen: a new widget shows the pending capsule, never the latest one', 0, () => {
      const older: PendingCapsule = { capsuleId: 'count-coffees', at: 1000 };
      expect(capsuleForNewWidget(older, 5000, availableExceptGone)).assertEqual('count-coffees');
      expect(capsuleForNewWidget(null, 5000, availableExceptGone)).assertEqual(''); // blank, not "latest"
      expect(capsuleForNewWidget(older, 1000 + PENDING_TTL_MS + 1, availableExceptGone)).assertEqual(''); // expired
      const gone: PendingCapsule = { capsuleId: 'gone', at: 1000 };
      expect(capsuleForNewWidget(gone, 2000, availableExceptGone)).assertEqual(''); // removed meanwhile
      const future: PendingCapsule = { capsuleId: 'count-coffees', at: 9000 };
      expect(capsuleForNewWidget(future, 2000, availableExceptGone)).assertEqual(''); // clock went back
    });

    it('a long checklist builds checklist rows on the widget, not the "Tap to open" view (T4-20)', 0, () => {
      const chicken = capsuleOf('{"schemaVersion":0,"id":"chicken","name":"Chicken and rice","permissions":[],' +
        '"ui":[{"type":"checklist","id":"steps","items":["Rinse rice","Boil water","Season chicken","Fry chicken",' +
        '"Cook rice","Chop onions","Serve"]}]}');
      const v = buildWidgetView(chicken, initialState(chicken), gate([], true, false), NOW, false);
      expect(`${v.status} ${v.layout} ${v.caption}`).assertEqual('ok checklist 0 / 7 done');
      expect(v.rows[0].items.length).assertEqual(7);
      const packing = capsuleOf('{"schemaVersion":0,"id":"pack","name":"Packing list","permissions":[],"ui":[' +
        '{"type":"text","text":"Clothes"},{"type":"checklist","id":"clothes","items":["Jumper","Socks","Boots","Hat"]},' +
        '{"type":"text","text":"Documents"},{"type":"checklist","id":"docs","items":["Passport","Wallet","Tickets"]}]}');
      const pv = buildWidgetView(packing, initialState(packing), gate([], true, false), NOW, true);
      expect(`${pv.status} ${pv.layout}`).assertEqual('ok rows');
      expect(pv.rows.filter((r: WidgetRow) => r.kind === 'checklist').length).assertEqual(2);
    });
  });
}
