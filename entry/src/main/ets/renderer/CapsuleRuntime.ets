import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  Capsule,
  CapsuleComponent,
  ChecklistComponent,
  CounterComponent,
  NumberComponent,
  TimerComponent
} from '../core/CapsuleTypes';
import { CapsuleState, ChecklistTicks, CounterValue, TimerRun } from '../core/WidgetModel';

const DOMAIN = 0x0001;
const TAG = 'CapsuleRuntime';

/** m:ss */
export function formatClock(total: number): string {
  const m = Math.floor(total / 60);
  const s = total % 60;
  return `${m}:${s < 10 ? '0' : ''}${s}`;
}

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
  label: string;
  @Trace value: number = 0;

  constructor(c: CounterComponent) {
    this.counterId = c.id;
    this.label = c.label;
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

/** Told when a running timer reaches zero, e.g. to post a notification. */
export interface TimerAlert {
  timerFinished(capsuleId: string, t: TimerState): void;
}

/** Approves each action before it runs (the gatekeeper). */
export interface ActionGuard {
  allowAction(action: string): boolean;
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
  guard?: ActionGuard;
  alert?: TimerAlert;
  /** Called after the user changes persisted state (timers started, counts, ticks). */
  onChange?: () => void;
  // Per ui index: '' if the component may render, else why it is blocked.
  @Trace blockReasons: string[] = [];
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

  blockReason(index: number): string {
    return index < this.blockReasons.length ? this.blockReasons[index] : '';
  }

  numberField(numberId: string): NumberState | undefined {
    return this.numbers.find((n: NumberState) => n.numberId === numberId);
  }

  /** One-line live state for cards: time left, counts, items ticked. */
  summary(): string {
    const parts: string[] = [];
    const running = this.timers.filter((t: TimerState) => t.running);
    if (running.length > 0) {
      const next = running.reduce((a: TimerState, b: TimerState) => a.remainingSec <= b.remainingSec ? a : b);
      parts.push(`${next.label} ${formatClock(next.remainingSec)} left`);
    } else if (this.timers.length > 0) {
      const done = this.timers.filter((t: TimerState) => t.done).length;
      parts.push(done > 0 ? `${done}/${this.timers.length} timers done` :
        `${this.timers.length} timer${this.timers.length > 1 ? 's' : ''} ready`);
    }
    this.counters.forEach((c: CounterState) => parts.push(`${c.label} ${c.value}`));
    this.checklists.forEach((c: ChecklistState) => {
      const ticked = c.checked.filter((v: boolean) => v).length;
      parts.push(`${ticked}/${c.checked.length} ticked`);
    });
    return parts.length > 0 ? parts.join(' · ') : 'Tap to open';
  }

  /** Runs one schema action string, e.g. "startTimer:pasta" or "startAllTimers". */
  dispatch(action: string): void {
    const sep = action.indexOf(':');
    const kind = sep < 0 ? action : action.substring(0, sep);
    const arg = sep < 0 ? '' : action.substring(sep + 1);
    hilog.info(DOMAIN, TAG, 'dispatch %{public}s', action);
    if (this.guard && !this.guard.allowAction(action)) {
      return;
    }
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
        return;
    }
    if (kind !== 'notify') {
      this.onChange?.();
    }
  }

  /** Ticks or unticks one checklist item (user tap). */
  setChecked(listId: string, index: number, value: boolean): void {
    const list = this.checklist(listId);
    if (!list || index < 0 || index >= list.checked.length) {
      return;
    }
    const next = list.checked.slice();
    next[index] = value;
    list.checked = next;
    this.onChange?.();
  }

  /** Persistable state shared with the home-screen widget (core/WidgetModel). */
  exportState(): CapsuleState {
    const timers: TimerRun[] = this.timers.map((t: TimerState): TimerRun => {
      const run: TimerRun = { id: t.timerId, endAt: t.running || t.done ? t.endAt : 0 };
      return run;
    });
    const counters: CounterValue[] = this.counters.map((c: CounterState): CounterValue => {
      const v: CounterValue = { id: c.counterId, value: c.value };
      return v;
    });
    const checklists: ChecklistTicks[] = this.checklists.map((l: ChecklistState): ChecklistTicks => {
      const ticks: ChecklistTicks = { id: l.listId, checked: l.checked.slice() };
      return ticks;
    });
    const state: CapsuleState = {
      capsuleId: this.capsule.id, timers: timers, counters: counters, checklists: checklists
    };
    return state;
  }

  /** Adopts saved state (e.g. after the widget changed it). Does not call onChange. */
  applyState(state: CapsuleState): void {
    if (state.capsuleId !== this.capsule.id) {
      return;
    }
    const now = Date.now();
    state.timers.forEach((run: TimerRun) => {
      const t = this.timer(run.id);
      if (!t) {
        return;
      }
      t.endAt = run.endAt;
      if (run.endAt === 0) {
        t.running = false;
        t.done = false;
        t.remainingSec = Math.round(t.minutes * 60);
      } else if (run.endAt > now) {
        t.running = true;
        t.done = false;
        t.remainingSec = Math.ceil((run.endAt - now) / 1000);
      } else {
        t.running = false;
        t.done = true;
        t.remainingSec = 0;
      }
    });
    state.counters.forEach((v: CounterValue) => {
      const c = this.counter(v.id);
      if (c) {
        c.value = v.value;
      }
    });
    state.checklists.forEach((ticks: ChecklistTicks) => {
      const l = this.checklist(ticks.id);
      if (l && ticks.checked.length === l.checked.length) {
        l.checked = ticks.checked.slice();
      }
    });
    if (this.timers.some((t: TimerState) => t.running)) {
      this.ensureTicking();
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
        this.alert?.timerFinished(this.capsule.id, t);
      } else {
        anyRunning = true;
      }
    });
    if (!anyRunning) {
      this.stop();
    }
  }
}
