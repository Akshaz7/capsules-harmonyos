/**
 * editCapsule: change a saved capsule with one English instruction ("make the timer 1 minute").
 *
 * Order: the English-only gate (nothing is sent anywhere), then the phone's own rules (durations, names,
 * goals, checklist items), then the cloud with the same routing as generateCapsule (an EU provider first,
 * non-EU only when allowed, never in on-device-only mode or when the cloud is not allowed). The cloud gets
 * the capsule's definition and the instruction, never its state values. Every result passed the validator
 * and keeps the capsule's id, so its grants, widgets and saved state stay attached.
 *
 * Nothing is saved here. The app shows `summary`, asks for consent again when `needsConsent`, saves on
 * Apply, and moves the user's state across with carryState(). `previous` is kept for "Undo last change".
 */
import { Capsule, CapsuleComponent, CapsuleOrigin, ChecklistComponent, CounterComponent, FailureKind, Permission,
  StateVar, TimerComponent } from '../CapsuleTypes';
import { validateCapsule } from '../CapsuleValidator';
import { allComponents, StateValues } from '../CapsuleProgram';
import { isNotEnglish, UNSUPPORTED_LANGUAGE_MESSAGE } from '../Language';
import { AI_NOT_CONFIGURED, CLOUD_OFF, GenerateOptions, ON_DEVICE_ONLY } from '../CapsuleGenerator';
import { extractJson, refusalIn, retryMessage, SYSTEM_PROMPT } from '../CapsuleModel';
import { ChatMessage, cloudOrigin, isEuProvider, ModelProvider } from '../ModelProvider';
import { CapsuleState, ChecklistTicks, CounterValue, TimerRun } from '../WidgetModel';
import { copyCapsule, ruleEdit } from './EditRules';

export const MAX_INSTRUCTION_LENGTH: number = 300;
export const EDIT_EMPTY: string = 'Say what to change, e.g. "make the timer 1 minute".';
export const EDIT_TOO_LONG: string = `Keep the change short (max ${MAX_INSTRUCTION_LENGTH} characters).`;
export const EDIT_NO_CHANGE: string = 'That would not change anything.';
export const EDIT_NEEDS_CLOUD: string = 'This change needs Cloud AI.';
const MAX_ATTEMPTS: number = 2;

export interface EditResult {
  ok: boolean;
  /** The edited, validated capsule (same id as `previous`); present only when ok. */
  capsule?: Capsule;
  /** The capsule before the change, for "Undo last change". */
  previous: Capsule;
  /** What changed, one line each: "Timer: 25 min → 1 min". Empty when not ok. */
  summary: string[];
  /** The edit asks for a permission the capsule did not have: run the consent again before applying. */
  needsConsent: boolean;
  /** 'rules' when the phone made the change, else the cloud provider. */
  origin?: CapsuleOrigin;
  /** One clear message when not ok. */
  error?: string;
  /** Validator errors behind `error`, if any. */
  details: string[];
  /** As GenerateResult.failure: 'unsupported-language' (not English) or 'not-an-app' (the model refused). */
  failure?: FailureKind;
  /** The rules could not do it and the cloud could, but this call did not allow it: ask, then retry. */
  needsCloud?: boolean;
}

/** Appended to the capsule system prompt for edits. */
export const EDIT_RULES: string = `
You are now changing an existing capsule, not making a new one.
- Apply only the requested change. Keep everything else exactly as it is: names, labels, order, texts.
- Keep "id" unchanged. Keep the id of every timer, counter and checklist that still exists, and keep v1 state
  names unchanged unless the change is about them.
- Update "permissions" so they match the new capsule.
- If the change cannot be done with capsule components, reply {"error": "<short reason>"}.`;

function fail(previous: Capsule, error: string, failure?: FailureKind): EditResult {
  const r: EditResult = { ok: false, previous: previous, summary: [], needsConsent: false, error: error, details: [] };
  if (failure !== undefined) {
    r.failure = failure;
  }
  return r;
}

/** "25 min", "1 min", "30 sec", "1.5 min". */
export function minutesText(minutes: number): string {
  if (minutes < 1) {
    return `${Math.round(minutes * 60)} sec`;
  }
  return `${Math.round(minutes * 100) / 100} min`;
}

function idOf(c: CapsuleComponent): string {
  const id = (c as TimerComponent).id;
  return typeof id === 'string' ? id : '';
}

function labelOf(c: CapsuleComponent): string {
  const label = (c as TimerComponent).label;
  return typeof label === 'string' ? label : '';
}

function kindName(type: string): string {
  return type === 'checklist' ? 'list' : type;
}

/** "Timer" when it is the only one of its kind, else "Timer Focus". */
function partName(c: CapsuleComponent, onlyOne: boolean): string {
  const kind = kindName(c.type);
  const title = kind.charAt(0).toUpperCase() + kind.substring(1);
  const label = labelOf(c);
  return onlyOne || label.length === 0 ? title : `${title} ${label}`;
}

function withId(capsule: Capsule): CapsuleComponent[] {
  return allComponents(capsule.ui).filter((c: CapsuleComponent) => idOf(c).length > 0);
}

function withoutId(capsule: Capsule): string {
  return JSON.stringify(allComponents(capsule.ui).filter((c: CapsuleComponent) => idOf(c).length === 0 &&
    c.type !== 'when' && c.type !== 'row'));
}

function listDiff(before: string[], after: string[]): string[] {
  const lower = (s: string) => s.toLowerCase();
  const added = after.filter((i: string) => !before.map(lower).includes(i.toLowerCase()));
  const removed = before.filter((i: string) => !after.map(lower).includes(i.toLowerCase()));
  const out: string[] = [];
  if (added.length > 0) {
    out.push(`added ${added.join(', ')}`);
  }
  if (removed.length > 0) {
    out.push(`removed ${removed.join(', ')}`);
  }
  return out;
}

function varText(v: StateVar): string {
  return JSON.stringify(v.initial);
}

/** What changed between two versions of a capsule, in plain English, one line each. */
export function editSummary(before: Capsule, after: Capsule): string[] {
  const out: string[] = [];
  if (before.name !== after.name) {
    out.push(`Name: ${before.name} → ${after.name}`);
  }
  const old = withId(before);
  const now = withId(after);
  const count = (list: CapsuleComponent[], type: string) =>
    list.filter((c: CapsuleComponent) => c.type === type).length;
  now.forEach((c: CapsuleComponent) => {
    const was = old.find((o: CapsuleComponent) => idOf(o) === idOf(c) && o.type === c.type);
    const only = count(now, c.type) === 1 && (was === undefined || count(old, c.type) === 1);
    if (was === undefined) {
      const extra = c.type === 'timer' ? ` (${minutesText((c as TimerComponent).minutes)})` : '';
      out.push(`Added ${kindName(c.type)}${labelOf(c).length > 0 ? ` ${labelOf(c)}` : ''}${extra}`);
      return;
    }
    const name = partName(was, only);
    if (labelOf(was) !== labelOf(c)) {
      out.push(`${name}: ${labelOf(was)} → ${labelOf(c)}`);
    }
    if (c.type === 'timer' && (was as TimerComponent).minutes !== (c as TimerComponent).minutes) {
      out.push(`${partName(c, only)}: ${minutesText((was as TimerComponent).minutes)} → ${minutesText(
        (c as TimerComponent).minutes)}`);
    }
    if (c.type === 'counter' && (was as CounterComponent).source !== (c as CounterComponent).source) {
      out.push(`${partName(c, only)}: counts ${(c as CounterComponent).source === 'motion' ? 'by itself' : 'by tap'}`);
    }
    if (c.type === 'checklist') {
      listDiff((was as ChecklistComponent).items, (c as ChecklistComponent).items).forEach((d: string) => {
        out.push(`${partName(c, only)}: ${d}`);
      });
    }
  });
  old.filter((o: CapsuleComponent) => !now.some((c: CapsuleComponent) => idOf(c) === idOf(o) && c.type === o.type))
    .forEach((o: CapsuleComponent) => {
      out.push(`Removed ${kindName(o.type)}${labelOf(o).length > 0 ? ` ${labelOf(o)}` : ''}`);
    });
  if (withoutId(before) !== withoutId(after)) {
    out.push('Buttons and text updated');
  }
  const was: Record<string, StateVar> = before.state ?? {};
  const is: Record<string, StateVar> = after.state ?? {};
  Object.keys(is).forEach((n: string) => {
    if (was[n] === undefined) {
      out.push(`Added value ${n}`);
    } else if (varText(was[n]) !== varText(is[n])) {
      out.push(`Starting ${n}: ${varText(was[n])} → ${varText(is[n])}`);
    }
  });
  Object.keys(was).filter((n: string) => is[n] === undefined).forEach((n: string) => {
    out.push(`Removed value ${n}`);
  });
  if (JSON.stringify(before.computed ?? {}) !== JSON.stringify(after.computed ?? {})) {
    out.push('Calculations updated');
  }
  if (JSON.stringify(before.triggers ?? []) !== JSON.stringify(after.triggers ?? [])) {
    out.push('Runs by itself: updated');
  }
  after.permissions.filter((p: Permission) => !before.permissions.includes(p)).forEach((p: Permission) => {
    out.push(`Needs permission: ${p}`);
  });
  before.permissions.filter((p: Permission) => !after.permissions.includes(p)).forEach((p: Permission) => {
    out.push(`No longer needs: ${p}`);
  });
  if (out.length === 0 && JSON.stringify(before) !== JSON.stringify(after)) {
    out.push('Small changes');
  }
  return out;
}

/** True when `after` asks for a permission `before` did not have. */
export function needsNewConsent(before: Capsule, after: Capsule): boolean {
  return after.permissions.some((p: Permission) => !before.permissions.includes(p));
}

/**
 * The user's state moved to the edited capsule, where ids still match: a timer keeps running only if its
 * length did not change, counters keep their counts, list ticks follow their item text, v1 values stay unless
 * their variable's type or starting value changed (so "set the goal to 10" shows 10).
 */
export function carryState(before: Capsule, after: Capsule, state: CapsuleState): CapsuleState {
  const timers: TimerRun[] = [];
  state.timers.forEach((run: TimerRun) => {
    const was = withId(before).find((c: CapsuleComponent) => c.type === 'timer' && idOf(c) === run.id);
    const is = withId(after).find((c: CapsuleComponent) => c.type === 'timer' && idOf(c) === run.id);
    if (was !== undefined && is !== undefined &&
      (was as TimerComponent).minutes === (is as TimerComponent).minutes) {
      timers.push(run);
    }
  });
  const counters: CounterValue[] = state.counters.filter((v: CounterValue) =>
    withId(after).some((c: CapsuleComponent) => c.type === 'counter' && idOf(c) === v.id));
  const checklists: ChecklistTicks[] = [];
  withId(after).filter((c: CapsuleComponent) => c.type === 'checklist').forEach((c: CapsuleComponent) => {
    const list = c as ChecklistComponent;
    const oldList = withId(before).find((o: CapsuleComponent) => o.type === 'checklist' && idOf(o) === list.id);
    const ticks = state.checklists.find((t: ChecklistTicks) => t.id === list.id);
    if (oldList === undefined || ticks === undefined) {
      return;
    }
    const oldItems = (oldList as ChecklistComponent).items;
    const used: boolean[] = oldItems.map(() => false);
    const checked = list.items.map((item: string) => {
      const i = oldItems.findIndex((o: string, k: number) => !used[k] && o.toLowerCase() === item.toLowerCase());
      if (i < 0) {
        return false;
      }
      used[i] = true;
      return i < ticks.checked.length ? ticks.checked[i] : false;
    });
    const moved: ChecklistTicks = { id: list.id, checked: checked };
    checklists.push(moved);
  });
  const out: CapsuleState = { capsuleId: after.id, timers: timers, counters: counters, checklists: checklists };
  if (state.values !== undefined) {
    out.values = carryValues(before, after, state.values);
  }
  return out;
}

/** v1 values whose variable still exists with the same type and starting value. */
export function carryValues(before: Capsule, after: Capsule, values: StateValues): StateValues {
  const was: Record<string, StateVar> = before.state ?? {};
  const is: Record<string, StateVar> = after.state ?? {};
  const out: StateValues = {};
  Object.keys(values).forEach((n: string) => {
    if (was[n] !== undefined && is[n] !== undefined && was[n].type === is[n].type &&
      varText(was[n]) === varText(is[n])) {
      out[n] = values[n];
    }
  });
  return out;
}

/** The cloud provider under generateCapsule's policy: the first EU one, else the default only if allowed. */
export function pickEditProvider(providers: ModelProvider[], allowNonEu: boolean): ModelProvider | null {
  const eu = providers.find((p: ModelProvider) => isEuProvider(p.name));
  if (eu !== undefined) {
    return eu;
  }
  return allowNonEu && providers.length > 0 ? providers[0] : null;
}

/** The message the cloud gets: the capsule definition (no state values) and the instruction. */
export function editMessage(capsule: Capsule, instruction: string): string {
  return `Current capsule:\n${JSON.stringify(capsule)}\n\nChange: ${instruction}`;
}

/** Validates an edited capsule, puts the original id back, and builds the result. */
function finish(previous: Capsule, edited: Capsule, origin: CapsuleOrigin): EditResult {
  // Compare like with like: the validator normalises what it returns, so normalise the original too.
  const base = validateCapsule(JSON.stringify(previous));
  const before = base.ok && base.capsule !== undefined ? base.capsule : previous;
  const fixed = copyCapsule(edited);
  fixed.id = previous.id;
  const v = validateCapsule(JSON.stringify(fixed));
  if (!v.ok || v.capsule === undefined) {
    const bad = fail(previous, "That change didn't make a valid capsule.");
    bad.details = v.errors;
    return bad;
  }
  const capsule = v.capsule;
  if (JSON.stringify(capsule) === JSON.stringify(before)) {
    return fail(previous, EDIT_NO_CHANGE);
  }
  return {
    ok: true, capsule: capsule, previous: previous, summary: editSummary(before, capsule),
    needsConsent: needsNewConsent(before, capsule), origin: origin, details: []
  };
}

async function cloudEdit(previous: Capsule, instruction: string, provider: ModelProvider): Promise<EditResult> {
  const system = `${SYSTEM_PROMPT}\n${EDIT_RULES}`;
  const messages: ChatMessage[] = [{ role: 'user', content: editMessage(previous, instruction) }];
  let last: EditResult = fail(previous, `The model did not produce a valid capsule after ${MAX_ATTEMPTS} attempts.`);
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    let reply: string;
    try {
      reply = await provider.complete(system, messages);
    } catch (e) {
      const reason = e instanceof Error ? e.message : String(e);
      return fail(previous, `The model request failed: ${reason}`);
    }
    const refusal = refusalIn(reply);
    if (refusal !== null) {
      return fail(previous, refusal.length > 0 ? refusal : "That change can't be made with a capsule.", 'not-an-app');
    }
    const parsed = validateCapsule(extractJson(reply));
    if (parsed.ok && parsed.capsule !== undefined) {
      return finish(previous, parsed.capsule, cloudOrigin(provider.name));
    }
    last = fail(previous, `The model did not produce a valid capsule after ${MAX_ATTEMPTS} attempts.`);
    last.details = parsed.errors;
    messages.push({ role: 'assistant', content: reply });
    messages.push({ role: 'user', content: retryMessage(parsed.errors) });
  }
  return last;
}

/**
 * Pure core of editCapsule: `providers` are the configured cloud providers, default first (tests pass fakes).
 * `unavailableReason`: why there are none, if a config exists but could not be used.
 */
export async function editCapsuleWith(capsule: Capsule, instruction: string, providers: ModelProvider[],
  options?: GenerateOptions, unavailableReason?: string): Promise<EditResult> {
  const text = instruction.trim();
  if (text.length === 0) {
    return fail(capsule, EDIT_EMPTY);
  }
  if (text.length > MAX_INSTRUCTION_LENGTH) {
    return fail(capsule, EDIT_TOO_LONG);
  }
  if (isNotEnglish(text)) {
    return fail(capsule, UNSUPPORTED_LANGUAGE_MESSAGE, 'unsupported-language'); // nothing is sent anywhere
  }
  const byRule = ruleEdit(capsule, text);
  if (byRule !== null) {
    const r = finish(capsule, byRule, 'rules');
    if (r.ok) {
      return r;
    }
    // A rule made something invalid (e.g. a name over the limit): let the cloud try instead.
  }
  if (options?.mode === 'on-device-only') {
    return fail(capsule, `${EDIT_NEEDS_CLOUD} ${ON_DEVICE_ONLY}`);
  }
  const provider = pickEditProvider(providers, options?.allowNonEu ?? false);
  if (provider === null) {
    if (providers.length > 0) {
      return fail(capsule, `${EDIT_NEEDS_CLOUD} The configured cloud provider (${providers[0].name}) is outside ` +
        'the EU; allow non-EU providers in settings to use it.');
    }
    const why = unavailableReason !== undefined && unavailableReason.length > 0 ?
      `AI fallback unavailable: ${unavailableReason}` : AI_NOT_CONFIGURED;
    return fail(capsule, `${EDIT_NEEDS_CLOUD} ${why}`);
  }
  if (options?.allowCloud === false) {
    const ask = fail(capsule, `${EDIT_NEEDS_CLOUD} ${CLOUD_OFF}`);
    ask.needsCloud = true;
    return ask;
  }
  return cloudEdit(capsule, text, provider);
}
