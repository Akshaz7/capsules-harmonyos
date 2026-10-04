/**
 * Simple edits made on the phone, without a model: durations, names, goals and checklist items.
 * Each rule returns the edited copy, or null when it does not understand the instruction (the caller then
 * asks the cloud). Never mutates its input. The result is not validated here; editCapsule does that.
 */
import { Capsule, CapsuleComponent, ChecklistComponent, ListComponent, Scalar, StateVar, TimerComponent } from '../CapsuleTypes';
import { allComponents } from '../CapsuleProgram';

const NUMBER_WORDS: Record<string, number> = {
  'a': 1, 'an': 1, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'seven': 7, 'eight': 8,
  'nine': 9, 'ten': 10, 'fifteen': 15, 'twenty': 20, 'thirty': 30, 'forty': 40, 'forty-five': 45, 'sixty': 60
};

const DURATION: RegExp =
  /\b(\d+(?:\.\d+)?|a|an|one|two|three|four|five|six|seven|eight|nine|ten|fifteen|twenty|thirty|forty|forty-five|sixty)\s*(seconds?|secs?|s|minutes?|mins?|m|hours?|hrs?|h)\b/i;

/** Words that mean the instruction is about a component, not a list item ("add a timer ..."). */
const COMPONENT_WORDS: RegExp =
  /\b(timers?|counters?|buttons?|players?|scores?|teams?|inputs?|fields?|minutes?|seconds?|hours?|triggers?|reminders?|notifications?)\b/i;

/** The capsule itself, not one of its parts. */
const SELF_WORDS: string[] = ['it', 'this', 'capsule', 'the capsule', 'this capsule', 'app', 'the app', 'this app'];

/** A deep copy, so a rule never changes the capsule the app is showing. */
export function copyCapsule(capsule: Capsule): Capsule {
  return JSON.parse(JSON.stringify(capsule)) as Capsule;
}

function amount(word: string): number {
  const known = NUMBER_WORDS[word.toLowerCase()];
  return known !== undefined ? known : Number(word);
}

/** "1 minute" -> 1, "90 seconds" -> 1.5, "1 hour" -> 60; null when the text names no duration. */
export function durationMinutes(text: string): number | null {
  const m = text.match(DURATION);
  if (m === null) {
    return null;
  }
  const n = amount(m[1]);
  if (!Number.isFinite(n) || n <= 0) {
    return null;
  }
  const unit = m[2].toLowerCase();
  const minutes = unit.startsWith('s') ? n / 60 : unit.startsWith('h') ? n * 60 : n;
  return Math.round(minutes * 1000) / 1000;
}

/** Strips quotes, a trailing full stop and "please" from a name the user typed. */
function cleanName(raw: string): string {
  let s = raw.trim().replace(/[.!]+$/, '').trim();
  s = s.replace(/^["'“‘]+/, '').replace(/["'”’]+$/, '').trim();
  return s.replace(/\s+please$/i, '').trim();
}

function timersOf(capsule: Capsule): TimerComponent[] {
  return allComponents(capsule.ui).filter((c: CapsuleComponent) => c.type === 'timer') as TimerComponent[];
}

function checklistsOf(capsule: Capsule): ChecklistComponent[] {
  return allComponents(capsule.ui).filter((c: CapsuleComponent) => c.type === 'checklist') as ChecklistComponent[];
}

/** The words of a label or id, lowercased: "Tea-timer" -> ["tea", "timer"]. */
function words(text: string): string[] {
  return text.toLowerCase().split(/[^a-z0-9]+/).filter((w: string) => w.length > 0);
}

/** The timer the instruction names by label or id; the only timer when it names none. */
function targetTimer(capsule: Capsule, instruction: string): TimerComponent | null {
  const timers = timersOf(capsule);
  const said = words(instruction);
  const named = timers.filter((t: TimerComponent) => {
    const own = words(t.label).concat(words(t.id)).filter((w: string) => w !== 'timer');
    return own.length > 0 && own.some((w: string) => said.includes(w));
  });
  if (named.length === 1) {
    return named[0];
  }
  return named.length === 0 && timers.length === 1 ? timers[0] : null;
}

/** "make the timer 1 minute", "set focus to 30 min", "change the break timer to 10 minutes". */
export function editDuration(capsule: Capsule, instruction: string): Capsule | null {
  if (!/\b(make|set|change|switch|turn|shorten|lengthen|should be|to)\b/i.test(instruction) ||
    /\b(add|new|another|remove|delete)\b/i.test(instruction)) {
    return null;
  }
  const minutes = durationMinutes(instruction);
  if (minutes === null) {
    return null;
  }
  const target = targetTimer(capsule, instruction);
  if (target === null) {
    return null;
  }
  const next = copyCapsule(capsule);
  const timer = timersOf(next).find((t: TimerComponent) => t.id === target.id);
  if (timer === undefined) {
    return null;
  }
  timer.minutes = minutes;
  return next;
}

/** The component whose label the user named: "the focus timer" -> the timer labelled "Focus". */
function componentNamed(capsule: Capsule, name: string): CapsuleComponent | null {
  const wanted = words(name).filter((w: string) => !['the', 'my', 'timer', 'counter', 'list', 'checklist'].includes(w));
  if (wanted.length === 0) {
    return null;
  }
  const found = allComponents(capsule.ui).filter((c: CapsuleComponent) => {
    const label = (c as TimerComponent).label;
    if (typeof label !== 'string') {
      return false;
    }
    const own = words(label);
    return wanted.every((w: string) => own.includes(w));
  });
  return found.length === 1 ? found[0] : null;
}

/**
 * "rename to Tea break", "call it Tea break", "change the name to Tea break" rename the capsule;
 * "rename the focus timer to Deep work" renames that component's label.
 */
export function editName(capsule: Capsule, instruction: string): Capsule | null {
  const text = instruction.trim();
  const part = text.match(/^(?:please\s+)?(?:rename|call)\s+(.+?)\s+(?:to|as)\s+(.+)$/i);
  if (part !== null && !SELF_WORDS.includes(part[1].toLowerCase())) {
    const target = componentNamed(capsule, part[1]);
    const label = cleanName(part[2]);
    if (target === null || label.length === 0) {
      return null;
    }
    const next = copyCapsule(capsule);
    const index = allComponents(capsule.ui).indexOf(target);
    const copy = allComponents(next.ui)[index] as TimerComponent; // every labelled component has a label field
    copy.label = label;
    return next;
  }
  const whole = text.match(/^(?:please\s+)?(?:rename|call)\s+(?:it\s+|this\s+|the capsule\s+|the app\s+)?(?:to\s+|as\s+)?(.+)$/i) ??
    text.match(/^(?:please\s+)?(?:change|set)\s+(?:the|its)\s+(?:name|title)\s+to\s+(.+)$/i) ??
    text.match(/^(?:please\s+)?name\s+it\s+(.+)$/i);
  if (whole === null) {
    return null;
  }
  const name = cleanName(whole[1]);
  if (name.length === 0 || name === capsule.name) {
    return null;
  }
  const next = copyCapsule(capsule);
  next.name = name;
  return next;
}

/** "set the goal to 10", "make the target 8": a v1 number state named goal or target. */
export function editGoal(capsule: Capsule, instruction: string): Capsule | null {
  const m = instruction.match(/\b(goal|target)\b\D*?(\d+(?:\.\d+)?)\b/i);
  if (m === null || capsule.state === undefined) {
    return null;
  }
  const state = capsule.state;
  const names = Object.keys(state).filter((n: string) => /goal|target/i.test(n) && state[n].type === 'number');
  if (names.length !== 1) {
    return null;
  }
  const next = copyCapsule(capsule);
  const v: StateVar = (next.state as Record<string, StateVar>)[names[0]];
  v.initial = Number(m[2]);
  return next;
}

/** "milk, eggs and bread" -> ["milk", "eggs", "bread"]. */
function splitItems(text: string): string[] {
  return text.split(/\s*,\s*|\s+and\s+|\s*&\s*/i).map((s: string) => cleanName(s))
    .filter((s: string) => s.length > 0);
}

/**
 * "add milk to the list", "add milk and eggs", "remove eggs", "take bread off the list".
 * Only with exactly one checklist; "add a timer ..." is never read as a list item.
 */
export function editChecklist(capsule: Capsule, instruction: string): Capsule | null {
  const lists = checklistsOf(capsule);
  if (lists.length !== 1) {
    return null;
  }
  const text = instruction.trim().replace(/[.!]+$/, '');
  const add = text.match(/^(?:please\s+)?(?:add|put)\s+(.+?)(?:\s+(?:to|on|onto|in|into)\s+(?:the\s+|my\s+|this\s+|a\s+)?(?:[a-z]+\s+)?(?:check)?list)?$/i);
  const remove = text.match(/^(?:please\s+)?(?:remove|delete|drop|take|cross)\s+(.+?)(?:\s+(?:off|from|out of)(?:\s+(?:the|my|this))?(?:\s+[a-z]+)?\s+(?:check)?list|\s+off|\s+out)?$/i);
  const explicit = /\blist\b/i.test(text);
  const next = copyCapsule(capsule);
  const list = checklistsOf(next)[0];
  if (add !== null) {
    const items = splitItems(add[1]);
    if (items.length === 0 || (!explicit && COMPONENT_WORDS.test(add[1]))) {
      return null;
    }
    const fresh = items.filter((i: string) =>
      !list.items.some((have: string) => have.toLowerCase() === i.toLowerCase()));
    if (fresh.length === 0) {
      return null;
    }
    // Match the list's style: rule-made lists start each item with a capital ("Eggs", so "milk" -> "Milk").
    const capitalised = list.items.every((i: string) => i.charAt(0) !== i.charAt(0).toLowerCase());
    list.items = list.items.concat(capitalised ?
      fresh.map((i: string) => i.charAt(0).toUpperCase() + i.substring(1)) : fresh);
    return next;
  }
  if (remove !== null) {
    const gone = splitItems(remove[1]).map((s: string) => s.toLowerCase());
    const kept = list.items.filter((i: string) => !gone.includes(i.toLowerCase()));
    if (kept.length === list.items.length || kept.length === 0) {
      return null; // nothing matched, or the list would be empty (the validator needs one item)
    }
    list.items = kept;
    return next;
  }
  return null;
}

/**
 * The same "add X" / "remove X" for a v1 list (a task list or packing list, T4-29): only with exactly one list
 * component and no checklist. "add" only appends to the list's starting items (the app adds them to the
 * current list too, see carryValues); "remove" never empties it.
 */
export function editTaskList(capsule: Capsule, instruction: string): Capsule | null {
  const lists = allComponents(capsule.ui).filter((c: CapsuleComponent) => c.type === 'list') as ListComponent[];
  const source = lists.length === 1 ? lists[0].source : '';
  const v = source.length > 0 ? (capsule.state ?? {})[source] : undefined;
  if (v === undefined || v.type !== 'list' || checklistsOf(capsule).length > 0) {
    return null;
  }
  const text = instruction.trim().replace(/[.!]+$/, '');
  const add = text.match(/^(?:please\s+)?(?:add|put)\s+(.+?)(?:\s+(?:to|on|onto|in|into)\s+(?:the\s+|my\s+|this\s+|a\s+)?(?:[a-z]+\s+)?(?:check)?list)?$/i);
  const remove = text.match(/^(?:please\s+)?(?:remove|delete|drop|take|cross)\s+(.+?)(?:\s+(?:off|from|out of)(?:\s+(?:the|my|this))?(?:\s+[a-z]+)?\s+(?:check)?list|\s+off|\s+out)?$/i);
  const explicit = /\blist\b/i.test(text);
  const items: string[] = Array.isArray(v.initial) ? (v.initial as Scalar[]).map((x: Scalar) => `${x}`) : [];
  const next = copyCapsule(capsule);
  const target = (next.state as Record<string, StateVar>)[source];
  if (add !== null) {
    const wanted = splitItems(add[1]);
    if (wanted.length === 0 || (!explicit && COMPONENT_WORDS.test(add[1]))) {
      return null;
    }
    const fresh = wanted.filter((i: string) => !items.some((have: string) => have.toLowerCase() === i.toLowerCase()))
      .map((i: string) => i.charAt(0).toUpperCase() + i.substring(1)); // tasks start with a capital
    if (fresh.length === 0) {
      return null;
    }
    target.initial = items.concat(fresh);
    return next;
  }
  if (remove !== null) {
    const gone = splitItems(remove[1]).map((t: string) => t.toLowerCase());
    const kept = items.filter((i: string) => !gone.includes(i.toLowerCase()));
    if (kept.length === items.length || kept.length === 0) {
      return null;
    }
    target.initial = kept;
    return next;
  }
  return null;
}

/** The first rule that understands the instruction, or null (then the cloud is asked). */
export function ruleEdit(capsule: Capsule, instruction: string): Capsule | null {
  return editName(capsule, instruction) ?? editChecklist(capsule, instruction) ??
    editTaskList(capsule, instruction) ?? editGoal(capsule, instruction) ?? editDuration(capsule, instruction);
}
