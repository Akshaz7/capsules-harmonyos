import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ButtonComponent,
  Capsule,
  CapsuleComponent,
  ChecklistComponent,
  CounterComponent,
  DisplayComponent,
  NumberComponent,
  TimerComponent,
  WhenComponent
} from '../core/CapsuleTypes';
import {
  allComponents,
  applyActions,
  ApplyResult,
  initialState,
  inputText,
  isEnabled,
  isShown,
  listItems,
  renderTemplate,
  restoreState,
  setInput,
  StateValues
} from '../core/CapsuleProgram';
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
  /** Paused by pauseTimer: remainingSec is kept and startTimer resumes from it. */
  @Trace paused: boolean = false;

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
  /** Cancels the system reminder of one timer (pause, stop, reset). Optional: without it the reminder still fires. */
  cancelTimer?: (capsuleId: string, t: TimerState) => void;
}

/** Told when a running timer reaches zero, e.g. to post a notification. */
export interface TimerAlert {
  timerFinished(capsuleId: string, t: TimerState): void;
}

/** Approves each action before it runs (the gatekeeper). */
export interface ActionGuard {
  allowAction(action: string): boolean;
}

function withKey(rec: Record<string, string>, key: string, value: string): Record<string, string> {
  const out: Record<string, string> = {};
  Object.keys(rec).forEach((k: string) => {
    out[k] = rec[k];
  });
  out[key] = value;
  return out;
}

/** Live state for one rendered capsule. Buttons go through press(), which uses core's interpreter. */
@ObservedV2
export class CapsuleRuntime {
  readonly capsule: Capsule;
  @Trace timers: TimerState[] = [];
  @Trace counters: CounterState[] = [];
  @Trace checklists: ChecklistState[] = [];
  @Trace numbers: NumberState[] = [];
  /** v1 state values. Replaced, never mutated, on each change so @Trace sees it. Empty for v0. */
  @Trace values: StateValues;
  /** What the user is typing into each v1 input, by bound var. Cleared when a button changes state. */
  @Trace drafts: Record<string, string> = {};
  /** Why the last text in an input was not accepted, by bound var. */
  @Trace inputErrors: Record<string, string> = {};
  /** Why the last button press did nothing; '' when it worked. */
  @Trace message: string = '';
  scheduler?: TimerScheduler;
  guard?: ActionGuard;
  alert?: TimerAlert;
  /** Called after the user changes persisted state (timers started, counts, ticks, v1 values). */
  onChange?: () => void;
  // Per component in allComponents(capsule.ui) order: '' if it may render, else why it is blocked.
  @Trace blockReasons: string[] = [];
  private tickHandle: number = -1;
  /** Every component, nested ones included, in the order the gatekeeper checks them. */
  private flat: CapsuleComponent[];

  constructor(capsule: Capsule) {
    this.capsule = capsule;
    this.values = initialState(capsule);
    this.flat = allComponents(capsule.ui);
    this.flat.forEach((c: CapsuleComponent) => {
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

  /** '' if the component may render, else why the gatekeeper blocked it. Works for nested components. */
  blockReason(c: CapsuleComponent): string {
    const index = this.flat.indexOf(c);
    return index >= 0 && index < this.blockReasons.length ? this.blockReasons[index] : '';
  }

  // ---- v1 ----

  /** A display template with each {expr} evaluated ("?" where one fails). */
  display(template: string): string {
    return renderTemplate(this.capsule, this.values, template);
  }

  shown(w: WhenComponent): boolean {
    return isShown(this.capsule, this.values, w);
  }

  enabled(b: ButtonComponent): boolean {
    return isEnabled(this.capsule, this.values, b);
  }

  items(source: string): string[] {
    return listItems(this.values, source);
  }

  /** What the user has typed into an input since the last button press; '' if nothing. */
  inputDraft(name: string): string {
    const draft = this.drafts[name];
    return draft !== undefined ? draft : '';
  }

  /** The bound state value as text, shown as the input's placeholder until the user types. */
  inputPlaceholder(name: string): string {
    return inputText(this.values, name);
  }

  /** The text an input shows: what the user is typing, else the bound state value. */
  inputValue(name: string): string {
    const draft = this.drafts[name];
    return draft !== undefined ? draft : inputText(this.values, name);
  }

  inputError(name: string): string {
    return this.inputErrors[name] ?? '';
  }

  /** User typed into an input bound to `name`. State changes only when the text is valid. */
  setInputValue(name: string, raw: string): void {
    this.drafts = withKey(this.drafts, name, raw);
    const r: ApplyResult = setInput(this.capsule, this.values, name, raw);
    if (!r.ok) {
      this.inputErrors = withKey(this.inputErrors, name, r.error ?? 'Not accepted');
      return;
    }
    this.inputErrors = withKey(this.inputErrors, name, '');
    this.values = r.state;
    this.onChange?.();
  }

  /** Replaces v1 values with saved ones (names and types that no longer match fall back to initial). */
  restoreValues(saved: StateValues): void {
    this.values = restoreState(this.capsule, saved);
  }

  /**
   * Presses a button (v0 or v1). Core's interpreter runs the do-steps all-or-nothing and returns
   * the v0 actions; the gatekeeper must allow every one of them, or nothing changes.
   */
  press(b: ButtonComponent): void {
    const r: ApplyResult = applyActions(this.capsule, this.values, b);
    if (!r.ok) {
      this.message = r.error ?? 'That did not work.';
      hilog.warn(DOMAIN, TAG, 'press "%{public}s" failed: %{public}s', b.label, this.message);
      return;
    }
    for (const action of r.actions) {
      if (this.guard && !this.guard.allowAction(action)) {
        this.message = `Blocked: "${action}" needs a permission you didn't allow.`;
        return;
      }
    }
    this.message = '';
    this.values = r.state;
    if (b.do !== undefined && b.do.length > 0) {
      this.drafts = {};
      this.inputErrors = {};
    }
    r.actions.forEach((action: string) => this.run(action));
    this.onChange?.();
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
    if (parts.length === 0) {
      // v1: the first display line, e.g. "Score 15-30".
      const first = this.flat.find((c: CapsuleComponent) => c.type === 'display');
      if (first !== undefined) {
        parts.push(this.display((first as DisplayComponent).text));
      }
    }
    return parts.length > 0 ? parts.join(' · ') : 'Tap to open';
  }

  /** Runs one schema action string, e.g. "startTimer:pasta" or "startAllTimers", after the gatekeeper. */
  dispatch(action: string): void {
    hilog.info(DOMAIN, TAG, 'dispatch %{public}s', action);
    if (this.guard && !this.guard.allowAction(action)) {
      return;
    }
    if (this.run(action) && !action.startsWith('notify')) {
      this.onChange?.();
    }
  }

  /** Runs an action the gatekeeper already allowed. False if the action is unknown. */
  private run(action: string): boolean {
    const sep = action.indexOf(':');
    const kind = sep < 0 ? action : action.substring(0, sep);
    const arg = sep < 0 ? '' : action.substring(sep + 1);
    switch (kind) {
      case 'startTimer': {
        const t = this.timer(arg);
        if (t) {
          this.startTimer(t);
        }
        break;
      }
      case 'pauseTimer': {
        const t = this.timer(arg);
        if (t) {
          this.pauseTimer(t);
        }
        break;
      }
      case 'stopTimer': {
        const t = this.timer(arg);
        if (t) {
          this.stopTimer(t);
        }
        break;
      }
      case 'resetTimer': {
        const t = this.timer(arg);
        if (t) {
          this.resetTimer(t);
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
        return false;
    }
    return true;
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

  /** Starts a timer from its full length, or resumes it after pauseTimer. */
  private startTimer(t: TimerState): void {
    if (t.running) {
      return;
    }
    const seconds = t.paused && t.remainingSec > 0 ? t.remainingSec : Math.round(t.minutes * 60);
    t.endAt = Date.now() + seconds * 1000;
    t.remainingSec = seconds;
    t.running = true;
    t.paused = false;
    t.done = false;
    this.ensureTicking();
    this.scheduler?.scheduleTimer(this.capsule.id, t);
  }

  /** Freezes a running timer; startTimer resumes it. */
  private pauseTimer(t: TimerState): void {
    if (!t.running) {
      return;
    }
    t.remainingSec = Math.max(0, Math.ceil((t.endAt - Date.now()) / 1000));
    t.running = false;
    t.paused = t.remainingSec > 0;
    this.scheduler?.cancelTimer?.(this.capsule.id, t);
  }

  /** Stops a timer and puts it back to its full length. */
  private stopTimer(t: TimerState): void {
    const wasRunning = t.running;
    t.running = false;
    t.paused = false;
    t.done = false;
    t.remainingSec = Math.round(t.minutes * 60);
    if (wasRunning) {
      this.scheduler?.cancelTimer?.(this.capsule.id, t);
    }
  }

  /** Puts a timer back to its full length; a running timer keeps running from there. */
  private resetTimer(t: TimerState): void {
    const wasRunning = t.running;
    this.stopTimer(t);
    if (wasRunning) {
      this.startTimer(t);
    }
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
