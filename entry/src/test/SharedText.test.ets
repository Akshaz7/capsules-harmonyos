import { describe, it, expect } from '@ohos/hypium';
import {
  capsuleFromSharedText, MAX_SHARED_TEXT, SHARED_EMPTY, SHARED_NOT_RECOGNISED, SHARED_TOO_LONG, SharedTextResult
} from '../main/ets/core/SharedText';
import { initialState, renderTemplate } from '../main/ets/core/CapsuleProgram';
import {
  Capsule, CapsuleComponent, ChecklistComponent, DisplayComponent, TextComponent, TimerComponent
} from '../main/ets/core/CapsuleTypes';

function shared(text: string, kind: string): Capsule {
  const r: SharedTextResult = capsuleFromSharedText(text);
  expect(r.error ?? '').assertEqual('');
  expect(r.kind).assertEqual(kind);
  return r.capsule as Capsule;
}

function timers(c: Capsule): string {
  return c.ui.filter((x: CapsuleComponent) => x.type === 'timer')
    .map((x: CapsuleComponent) => `${(x as TimerComponent).label} ${(x as TimerComponent).minutes}`).join('|');
}

function checklist(c: Capsule): string {
  const l = c.ui.find((x: CapsuleComponent) => x.type === 'checklist') as ChecklistComponent;
  return l.items.join('|');
}

function eachPays(c: Capsule): string {
  const d = c.ui.find((x: CapsuleComponent) => x.type === 'display') as DisplayComponent;
  return renderTemplate(c, initialState(c), d.text);
}

export default function sharedTextTest() {
  describe('Shared text -> capsule', () => {
    it('turns a recipe into one timer per timed step', 0, () => {
      const c = shared('Banana bread\nPreheat the oven to 180°C.\nMix the batter for 2 minutes.\n' +
        'Bake for 50-55 minutes.\nLet it cool for 10 minutes.', 'recipe');
      expect(c.name).assertEqual('Banana bread');
      expect(timers(c)).assertEqual('Mix 2|Bake 55|Cool 10');
      expect(c.permissions.join()).assertEqual('reminders');
      const stew = shared('Brown the beef for 5 minutes. Slow cook for 2 hours. Rest 15 min before serving.', 'recipe');
      expect(timers(stew)).assertEqual('Brown 5|Cook 120|Rest 15');
      expect(stew.name).assertEqual('Recipe timers');
    });

    it('turns a group chat with amounts into a live bill split', 0, () => {
      const c = shared('[18:02] Anna: I paid €45 for pizza\n[18:03] Ben: drinks were €30\n' +
        '[18:05] Carl: ok lets split it', 'bill');
      expect(c.schemaVersion).assertEqual(1);
      expect(eachPays(c)).assertEqual('Each pays: 25');
      const paid = c.ui.find((x: CapsuleComponent) => x.type === 'text') as TextComponent;
      expect(paid.text).assertEqual('Paid so far: Anna 45, Ben 30');
      const note = shared('Dinner total 120 zł, split between 4 people', 'bill');
      expect(eachPays(note)).assertEqual('Each pays: 30');
    });

    it('turns a workout into a checklist with timers for timed exercises', 0, () => {
      const c = shared('Leg day\n3x10 squats\n3x12 lunges\nplank 60s\nwall sit 45 s', 'workout');
      expect(c.name).assertEqual('Leg day');
      expect(checklist(c)).assertEqual('3×10 squats|3×12 lunges|Plank 60s|Wall sit 45 s');
      expect(timers(c)).assertEqual('Plank 1|Wall sit 0.75');
      expect(c.permissions.join()).assertEqual('reminders');
      const noTimers = shared('Workout: 20 push-ups', 'workout');
      expect(noTimers.permissions.length).assertEqual(0);
    });

    it('turns bullet, titled and comma lists into a checklist', 0, () => {
      const c = shared('Shopping:\n- milk\n- eggs\n- bread', 'list');
      expect(c.name).assertEqual('Shopping');
      expect(checklist(c)).assertEqual('Milk|Eggs|Bread');
      expect(checklist(shared('1. passport\n2) charger\n[ ] socks', 'list'))).assertEqual('Passport|Charger|Socks');
      const comma = shared('Packing: socks, charger, passport', 'list');
      expect(comma.name).assertEqual('Packing');
      expect(checklist(comma)).assertEqual('Socks|Charger|Passport');
      expect(checklist(shared('Todo:\ncall the bank\nbook dentist\nwater plants', 'list')))
        .assertEqual('Call the bank|Book dentist|Water plants');
    });

    it('rejects empty, too long and unrecognised text with clear errors', 0, () => {
      expect(capsuleFromSharedText('   ').error).assertEqual(SHARED_EMPTY);
      const long = capsuleFromSharedText('a'.repeat(MAX_SHARED_TEXT + 1));
      expect(long.ok).assertFalse();
      expect(long.error).assertEqual(SHARED_TOO_LONG);
      expect(SHARED_TOO_LONG).assertContain('2000');
      expect(capsuleFromSharedText('a '.repeat(999)).error).assertEqual(SHARED_NOT_RECOGNISED);
      expect(capsuleFromSharedText('Hey, are we still on for tomorrow?').error).assertEqual(SHARED_NOT_RECOGNISED);
    });
  });
}
