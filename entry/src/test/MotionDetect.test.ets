import { describe, it, expect } from '@ohos/hypium';
import {
  accelerationMagnitude, BURST_END_MS, MotionEvent, SHAKE_DEBOUNCE_MS, ShakeDetector
} from '../main/ets/capabilities/ShakeDetector';
import {
  activeMotionConsumers, motionCounterIds, motionTriggerIndices, MotionConsumer, usesMotion
} from '../main/ets/capabilities/MotionConsumers';
import { Capsule } from '../main/ets/core/CapsuleTypes';
import { validateCapsule } from '../main/ets/core/CapsuleValidator';

const RESTING: number = 9.81;
/** A sample far above the threshold (deviation ~20 m/s^2). */
const STRONG: number = 30;

const MOTION_COUNTER: string = '{"schemaVersion":0,"id":"shakes","name":"Shakes","permissions":["motion"],"ui":' +
  '[{"type":"counter","id":"shakes","label":"Shakes","source":"motion"}]}';

const MOTION_TRIGGER: string = '{"schemaVersion":1,"id":"run","name":"Run","permissions":["motion"],' +
  '"state":{"n":{"type":"number","initial":0}},' +
  '"ui":[{"type":"display","text":"{n}"}],' +
  '"triggers":[{"on":"motion","do":[{"set":"n","to":"n + 1"}]}]}';

const PLAIN_COUNTER: string = '{"schemaVersion":0,"id":"coffee","name":"Coffee","permissions":[],"ui":' +
  '[{"type":"counter","id":"coffee","label":"Coffee","source":"manual"}]}';

function capsule(json: string): Capsule {
  const v = validateCapsule(json);
  expect(v.errors.join('; ')).assertEqual('');
  return v.capsule as Capsule;
}

/** Feeds `count` samples `stepMs` apart, strong (a shake) or resting. Returns every event. */
function feed(d: ShakeDetector, count: number, startMs: number, stepMs: number, strong: boolean): MotionEvent[] {
  let out: MotionEvent[] = [];
  for (let i = 0; i < count; i++) {
    const v: number = strong ? STRONG : RESTING;
    out = out.concat(d.sample(v, 0, 0, startMs + i * stepMs));
  }
  return out;
}

function countKind(events: MotionEvent[], kind: string): number {
  return events.filter((e: MotionEvent) => e.kind === kind).length;
}

export default function motionDetectTest() {
  describe('ShakeDetector', () => {
    it('reads a resting phone as no motion', 0, () => {
      const d = new ShakeDetector();
      expect(countKind(feed(d, 100, 0, 60, false), 'shake')).assertEqual(0);
      expect(countKind(feed(d, 100, 0, 60, false), 'burstStart')).assertEqual(0);
      expect(Math.round(accelerationMagnitude(0, 0, RESTING))).assertEqual(10);
    });

    it('starts a burst once and counts shakes at the debounce rate', 0, () => {
      const d = new ShakeDetector();
      const events = feed(d, 21, 0, 60, true); // 0 .. 1200 ms of shaking
      expect(countKind(events, 'burstStart')).assertEqual(1);
      const shakes = events.filter((e: MotionEvent) => e.kind === 'shake');
      expect(shakes.length >= 3).assertTrue();
      for (let i = 1; i < shakes.length; i++) {
        expect(shakes[i].atMs - shakes[i - 1].atMs >= SHAKE_DEBOUNCE_MS).assertTrue();
      }
      expect(events[0].kind).assertEqual('burstStart');
      expect(events[1].kind).assertEqual('shake');
    });

    it('needs three high samples: two bumps never fire', 0, () => {
      const d = new ShakeDetector();
      expect(feed(d, 2, 0, 60, true).length).assertEqual(0);
      expect(feed(d, 1, 120, 60, true).length > 0).assertTrue();
    });

    it('ends a burst after a quiet gap, then a new burst fires the trigger again', 0, () => {
      const d = new ShakeDetector();
      const first = feed(d, 11, 0, 60, true); // 0 .. 600 ms
      const quiet = feed(d, 15, 660, 60, false); // 660 .. 1500 ms, more than BURST_END_MS of quiet
      const second = feed(d, 3, 1620, 60, true);
      expect(countKind(first, 'burstStart')).assertEqual(1);
      expect(countKind(quiet, 'burstStart')).assertEqual(0);
      expect(countKind(second, 'burstStart')).assertEqual(1);
      expect(second[0].atMs).assertEqual(1620 + 2 * 60);
    });

    it('ignores NaN samples and stays bounded over long shaking', 0, () => {
      const d = new ShakeDetector();
      expect(d.sample(NaN, 0, 0, 0).length).assertEqual(0);
      expect(d.sample(0, 0, Infinity, 10).length).assertEqual(0);
      const events = feed(d, 10000, 0, 5, true);
      expect(countKind(events, 'burstStart')).assertEqual(1);
      expect(countKind(events, 'shake') <= Math.ceil(10000 * 5 / SHAKE_DEBOUNCE_MS) + 1).assertTrue();
    });

    it('forgets the burst on reset', 0, () => {
      const d = new ShakeDetector();
      expect(countKind(feed(d, 3, 0, 60, true), 'burstStart')).assertEqual(1);
      d.reset();
      expect(feed(d, 2, 2000, 60, true).length).assertEqual(0);
    });

    it('BURST_END_MS is longer than the debounce', 0, () => {
      expect(BURST_END_MS > SHAKE_DEBOUNCE_MS).assertTrue();
    });
  });

  describe('MotionConsumers', () => {
    it('finds motion counters and motion triggers', 0, () => {
      const counter = capsule(MOTION_COUNTER);
      const trigger = capsule(MOTION_TRIGGER);
      expect(motionCounterIds(counter).join()).assertEqual('shakes');
      expect(motionTriggerIndices(counter).length).assertEqual(0);
      expect(motionCounterIds(trigger).length).assertEqual(0);
      expect(motionTriggerIndices(trigger).join()).assertEqual('0');
      expect(usesMotion(counter)).assertTrue();
      expect(usesMotion(trigger)).assertTrue();
      expect(usesMotion(capsule(PLAIN_COUNTER))).assertFalse();
    });

    it('scope "capsule" feeds only the open page', 0, () => {
      const capsules: Capsule[] = [capsule(MOTION_COUNTER), capsule(MOTION_TRIGGER)];
      const yes = (c: Capsule): boolean => true;
      expect(activeMotionConsumers(capsules, 'capsule', '', yes).length).assertEqual(0);
      const open = activeMotionConsumers(capsules, 'capsule', 'shakes', yes);
      expect(open.length).assertEqual(1);
      expect(open[0].counterIds.join()).assertEqual('shakes');
    });

    it('scope "app" feeds every granted capsule in front', 0, () => {
      const capsules: Capsule[] = [capsule(MOTION_COUNTER), capsule(MOTION_TRIGGER), capsule(PLAIN_COUNTER)];
      const consumers: MotionConsumer[] = activeMotionConsumers(capsules, 'app', '', (c: Capsule) => true);
      expect(consumers.length).assertEqual(2);
      expect(consumers[1].triggerIndices.join()).assertEqual('0');
    });

    it('a denied or revoked grant removes the consumer, and non-motion capsules never appear', 0, () => {
      const capsules: Capsule[] = [capsule(MOTION_COUNTER)];
      const denied = (c: Capsule): boolean => false;
      expect(activeMotionConsumers(capsules, 'app', '', denied).length).assertEqual(0);
      expect(activeMotionConsumers([capsule(PLAIN_COUNTER)], 'app', 'coffee', (c: Capsule) => true).length)
        .assertEqual(0);
    });
  });
}
