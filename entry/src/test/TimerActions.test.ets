import { describe, it, expect } from '@ohos/hypium';
import { CapsuleRuntime, TimerScheduler, TimerState } from '../main/ets/renderer/CapsuleRuntime';
import { parseAction, permissionForAction, validateCapsule } from '../main/ets/core/CapsuleValidator';
import { ButtonComponent, Capsule, CapsuleComponent, ParsedAction } from '../main/ets/core/CapsuleTypes';
import { allComponents } from '../main/ets/core/CapsuleProgram';

const POMODORO: string = '{"schemaVersion":1,"id":"pomo","name":"Pomodoro","permissions":["reminders"],' +
  '"state":{"rounds":{"type":"number","initial":0}},' +
  '"ui":[{"type":"timer","id":"focus","label":"Focus","minutes":25},{"type":"display","text":"Rounds {rounds}"},' +
  '{"type":"row","items":[{"type":"button","label":"Start","action":"startTimer:focus"},' +
  '{"type":"button","label":"Pause","action":"pauseTimer:focus"},' +
  '{"type":"button","label":"Stop","do":["stopTimer:focus"]},' +
  '{"type":"button","label":"Next round","do":[{"set":"rounds","to":"rounds + 1"},"resetTimer:focus"]}]}]}';

class RecordingScheduler implements TimerScheduler {
  calls: string[] = [];
  cancelTimer: (capsuleId: string, t: TimerState) => void = (capsuleId: string, t: TimerState) => {
    this.calls.push(`cancel:${t.timerId}`);
  };

  scheduleTimer(capsuleId: string, t: TimerState): void {
    this.calls.push(`schedule:${t.timerId}:${t.remainingSec}`);
  }
}

function errorsOf(json: string): string {
  return validateCapsule(json).errors.join('\n');
}

function withButton(permissions: string, action: string): string {
  return `{"schemaVersion":1,"id":"x","name":"X","permissions":${permissions},` +
    '"ui":[{"type":"timer","id":"t","label":"T","minutes":5},{"type":"counter","id":"c","label":"C","source":"manual"},' +
    `{"type":"button","label":"Go","do":["${action}"]}]}`;
}

export default function timerActionsTest() {
  describe('Timer controls: pauseTimer, stopTimer, resetTimer', () => {
    it('are schema actions on timers that need "reminders", in buttons and do steps', 0, () => {
      expect(errorsOf(POMODORO)).assertEqual('');
      ['pauseTimer', 'stopTimer', 'resetTimer'].forEach((kind: string) => {
        const a = parseAction(`${kind}:focus`) as ParsedAction;
        expect(a.kind).assertEqual(kind);
        expect(a.arg).assertEqual('focus');
        expect(permissionForAction(a)).assertEqual('reminders');
        expect(errorsOf(withButton('["reminders"]', `${kind}:t`))).assertEqual('');
        expect(errorsOf(withButton('["reminders"]', `${kind}:c`))).assertContain(`action "${kind}:c" needs a timer`);
        expect(errorsOf(withButton('["reminders"]', `${kind}:nope`))).assertContain('refers to id "nope"');
      });
      expect(errorsOf('{"schemaVersion":0,"id":"x","name":"X","permissions":[],"ui":[' +
        '{"type":"button","label":"P","action":"pauseTimer:t"}]}')).assertContain('refers to id "t"');
      expect(parseAction('pauseTimer:')).assertNull();
    });

    it('pause freezes a running timer and start resumes it; stop goes back to the full length', 0, () => {
      const c = validateCapsule(POMODORO).capsule as Capsule;
      const rt = new CapsuleRuntime(c);
      const sched = new RecordingScheduler();
      rt.scheduler = sched;
      const t = rt.timer('focus') as TimerState;
      rt.dispatch('startTimer:focus');
      expect(t.running).assertTrue();
      rt.dispatch('pauseTimer:focus');
      expect(t.running).assertFalse();
      expect(t.paused).assertTrue();
      expect(t.remainingSec >= 1499 && t.remainingSec <= 1500).assertTrue();
      t.remainingSec = 600; // as if paused after 15 minutes
      rt.dispatch('startTimer:focus');
      expect(t.running).assertTrue();
      expect(t.paused).assertFalse();
      expect(t.remainingSec).assertEqual(600);
      rt.dispatch('stopTimer:focus');
      expect(t.running).assertFalse();
      expect(t.paused).assertFalse();
      expect(t.remainingSec).assertEqual(1500);
      expect(sched.calls.join()).assertEqual('schedule:focus:1500,cancel:focus,schedule:focus:600,cancel:focus');
      rt.stop();
    });

    it('reset restarts a running timer from its full length, and only rewinds a stopped one', 0, () => {
      const c = validateCapsule(POMODORO).capsule as Capsule;
      const rt = new CapsuleRuntime(c);
      const t = rt.timer('focus') as TimerState;
      rt.dispatch('startTimer:focus');
      t.remainingSec = 30;
      rt.dispatch('resetTimer:focus');
      expect(t.running).assertTrue();
      expect(t.remainingSec).assertEqual(1500);
      rt.dispatch('stopTimer:focus');
      t.remainingSec = 10;
      rt.dispatch('resetTimer:focus');
      expect(t.running).assertFalse();
      expect(t.remainingSec).assertEqual(1500);
      rt.stop();
    });

    it('run from a v1 do step together with state changes', 0, () => {
      const c = validateCapsule(POMODORO).capsule as Capsule;
      const rt = new CapsuleRuntime(c);
      const t = rt.timer('focus') as TimerState;
      const next = allComponents(c.ui).find((x: CapsuleComponent) => x.type === 'button' &&
        (x as ButtonComponent).label === 'Next round') as ButtonComponent;
      rt.dispatch('startTimer:focus');
      t.remainingSec = 42;
      rt.press(next);
      expect(rt.values['rounds']).assertEqual(1);
      expect(t.running).assertTrue();
      expect(t.remainingSec).assertEqual(1500);
      rt.stop();
    });
  });
}
