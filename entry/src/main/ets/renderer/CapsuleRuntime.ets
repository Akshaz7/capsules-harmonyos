import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  Capsule,
  CapsuleComponent,
  ChecklistComponent,
  CounterComponent,
  NumberComponent,
  TimerComponent
} from '../core/CapsuleTypes';

const DOMAIN = 0x0001;
const TAG = 'CapsuleRuntime';

@ObservedV2
export class TimerState {
  timerId: string;
  label: string;
  minutes: number;
  endAt: number = 0;
  @Trace remainingSec: number;
  @Trace running: boolean = false;
  @Trace done: boolean = false;

  constructor(c: TimerComponent) {
    this.timerId = c.id;
    this.label = c.label;
    this.minutes = c.minutes;
    this.remainingSec = Math.round(c.minutes * 60);
  }
}

@ObservedV2
export class CounterState {
  counterId: string;
  @Trace value: number = 0;

  constructor(c: CounterComponent) {
    this.counterId = c.id;
  }
}

@ObservedV2
export class ChecklistState {
  listId: string;
  @Trace checked: boolean[];

  constructor(c: ChecklistComponent) {
    this.listId = c.id;
    this.checked = c.items.map((): boolean => false);
  }
}

@ObservedV2
export class NumberState {
  numberId: string;
  @Trace value: string = '';

  constructor(c: NumberComponent) {
    this.numberId = c.id;
  }
}

/** Receives timer starts, e.g. to schedule a system reminder. */
export interface TimerScheduler {
  scheduleTimer(capsuleId: string, t: TimerState): void;
}

/** Live state for one rendered capsule. Actions from buttons go through dispatch(). */
@ObservedV2
export class CapsuleRuntime {
  readonly capsule: Capsule;
  @Trace timers: TimerState[] = [];
  @Trace counters: CounterState[] = [];
  @Trace checklists: ChecklistState[] = [];
  @Trace numbers: NumberState[] = [];
  scheduler?: TimerScheduler;
  private tickHandle: number = -1;

  constructor(capsule: Capsule) {
    this.capsule = capsule;
    capsule.ui.forEach((c: CapsuleComponent) => {
      if (c.type === 'timer') {
        this.timers.push(new TimerState(c as TimerComponent));
      } else if (c.type === 'counter') {
        this.counters.push(new CounterState(c as CounterComponent));
      } else if (c.type === 'checklist') {
        this.checklists.push(new ChecklistState(c as ChecklistComponent));
      } else if (c.type === 'number') {
        this.numbers.push(new NumberState(c as NumberComponent));
      }
    });
  }

  timer(timerId: string): TimerState | undefined {
    return this.timers.find((t: TimerState) => t.timerId === timerId);
  }

  counter(counterId: string): CounterState | undefined {
    return this.counters.find((c: CounterState) => c.counterId === counterId);
  }

  checklist(listId: string): ChecklistState | undefined {
    return this.checklists.find((c: ChecklistState) => c.listId === listId);
  }

  numberField(numberId: string): NumberState | undefined {
    return this.numbers.find((n: NumberState) => n.numberId === numberId);
  }

  /** Runs one schema action string, e.g. "startTimer:pasta" or "startAllTimers". */
  dispatch(action: string): void {
    const sep = action.indexOf(':');
    const kind = sep < 0 ? action : action.substring(0, sep);
    const arg = sep < 0 ? '' : action.substring(sep + 1);
    hilog.info(DOMAIN, TAG, 'dispatch %{public}s', action);
    switch (kind) {
      case 'startTimer': {
        const t = this.timer(arg);
        if (t) {
          this.startTimer(t);
        }
        break;
      }
      case 'startAllTimers':
        this.timers.forEach((t: TimerState) => this.startTimer(t));
        break;
      case 'increment': {
        const c = this.counter(arg);
        if (c) {
          c.value += 1;
        }
        break;
      }
      case 'reset': {
        const c = this.counter(arg);
        if (c) {
          c.value = 0;
        }
        break;
      }
      case 'notify':
        // Delivered by the notification adapter (step 4).
        break;
      default:
        hilog.warn(DOMAIN, TAG, 'unknown action %{public}s', action);
    }
  }

  stop(): void {
    if (this.tickHandle >= 0) {
      clearInterval(this.tickHandle);
      this.tickHandle = -1;
    }
  }

  private startTimer(t: TimerState): void {
    if (t.running) {
      return;
    }
    t.endAt = Date.now() + Math.round(t.minutes * 60) * 1000;
    t.remainingSec = Math.round(t.minutes * 60);
    t.running = true;
    t.done = false;
    this.ensureTicking();
    this.scheduler?.scheduleTimer(this.capsule.id, t);
  }

  private ensureTicking(): void {
    if (this.tickHandle >= 0) {
      return;
    }
    this.tickHandle = setInterval(() => this.tick(), 1000);
  }

  private tick(): void {
    const now = Date.now();
    let anyRunning = false;
    this.timers.forEach((t: TimerState) => {
      if (!t.running) {
        return;
      }
      const left = Math.max(0, Math.ceil((t.endAt - now) / 1000));
      t.remainingSec = left;
      if (left === 0) {
        t.running = false;
        t.done = true;
      } else {
        anyRunning = true;
      }
    });
    if (!anyRunning) {
      this.stop();
    }
  }
}
