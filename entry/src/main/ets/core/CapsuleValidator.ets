/**
 * Strict validator for SCHEMA.md (schema v0 and v1).
 * Unknown fields, unknown component types and unknown actions are rejected.
 * A component or action that needs a permission missing from "permissions" is rejected.
 * v1: every expression is parsed with our own grammar, every name must exist and types must fit.
 */
import {
  ActionKind,
  ButtonComponent,
  ButtonStep,
  Capsule,
  CapsuleComponent,
  ChecklistComponent,
  COMPONENT_TYPES,
  COUNTER_SOURCES,
  CounterComponent,
  CounterSource,
  DisplayComponent,
  InputComponent,
  InputKind,
  ListComponent,
  NumberComponent,
  ParsedAction,
  Permission,
  PERMISSIONS,
  RowComponent,
  Scalar,
  StateVar,
  StepObject,
  TextComponent,
  TIMER_ACTIONS,
  Trigger,
  TriggerKind,
  TRIGGER_KINDS,
  MAX_TRIGGERS,
  MAX_TRIGGER_LABEL,
  TimerComponent,
  V1_COMPONENT_TYPES,
  ValidationResult,
  Value,
  VarType,
  WhenComponent
} from './CapsuleTypes';
import {
  ExprError,
  isValidName,
  MAX_LIST_ITEMS,
  MAX_TEXT_LENGTH,
  parseExpr,
  parseTemplate,
  TemplatePart,
  typeOf
} from './Expr';
import { nameTypes } from './CapsuleProgram';

type JsonValue = Object | null | undefined;
type JsonRecord = Record<string, Object | null>;

const CAPSULE_FIELDS: string[] = ['schemaVersion', 'id', 'name', 'permissions', 'ui'];
const V1_CAPSULE_FIELDS: string[] = ['state', 'computed', 'triggers'];
const VAR_TYPES: string[] = ['number', 'text', 'bool', 'list'];
export const MAX_COMPONENTS: number = 60;
export const MAX_NESTING: number = 5;
export const MAX_VARS: number = 30;
export const MAX_STEPS: number = 20;

function fieldsFor(type: string): string[] {
  switch (type) {
    case 'text':
      return ['type', 'text'];
    case 'timer':
      return ['type', 'id', 'label', 'minutes'];
    case 'counter':
      return ['type', 'id', 'label', 'source'];
    case 'checklist':
      return ['type', 'id', 'items'];
    case 'number':
      return ['type', 'id', 'label'];
    case 'button':
      return ['type', 'label', 'action'];
    case 'display':
      return ['type', 'text'];
    case 'input':
      return ['type', 'bind', 'kind', 'label'];
    case 'list':
      return ['type', 'source'];
    case 'when':
      return ['type', 'if', 'show'];
    case 'row':
      return ['type', 'items'];
    default:
      return [];
  }
}

function isRecord(v: JsonValue): boolean {
  return v !== null && v !== undefined && typeof v === 'object' && !Array.isArray(v);
}

function isNonEmptyString(v: JsonValue): boolean {
  return typeof v === 'string' && (v as string).trim().length > 0;
}

function describe(v: JsonValue): string {
  if (v === null) {
    return 'null';
  }
  if (v === undefined) {
    return 'nothing';
  }
  if (Array.isArray(v)) {
    return 'an array';
  }
  return `a ${typeof v}`;
}

/** Parses an action string. Returns null if it is not one of the schema's actions. */
export function parseAction(action: string): ParsedAction | null {
  if (action === 'startAllTimers') {
    return { kind: 'startAllTimers', arg: '' };
  }
  const colon = action.indexOf(':');
  if (colon <= 0) {
    return null;
  }
  const head = action.substring(0, colon);
  const arg = action.substring(colon + 1);
  if (arg.trim().length === 0) {
    return null;
  }
  if (TIMER_ACTIONS.includes(head) || head === 'increment' || head === 'reset' || head === 'notify') {
    return { kind: head as ActionKind, arg: arg };
  }
  return null;
}

/** The component's id: timer, counter, checklist and number have one; other types return undefined. */
export function componentId(c: CapsuleComponent): string | undefined {
  if (c.type === 'timer' || c.type === 'counter' || c.type === 'checklist' || c.type === 'number') {
    return (c as NumberComponent).id;
  }
  return undefined;
}

/** Permission a component needs, or null. */
export function permissionForComponent(c: CapsuleComponent): Permission | null {
  if (c.type === 'timer') {
    return 'reminders';
  }
  if (c.type === 'counter' && (c as CounterComponent).source === 'motion') {
    return 'motion';
  }
  return null;
}

/** Permission an action needs, or null. Timer actions need reminders; notify needs notifications. */
export function permissionForAction(a: ParsedAction): Permission | null {
  if (TIMER_ACTIONS.includes(a.kind) || a.kind === 'startAllTimers') {
    return 'reminders';
  }
  if (a.kind === 'notify') {
    return 'notifications';
  }
  return null;
}

const ACTIONS_HINT: string =
  '(allowed: startTimer:<id>, pauseTimer:<id>, stopTimer:<id>, resetTimer:<id>, startAllTimers, increment:<id>, ' +
  'reset:<id>, notify:<text>)';

/** A component with its JSON path, for checks that run after the structure is known. */
class Placed {
  c: CapsuleComponent;
  path: string;

  constructor(c: CapsuleComponent, path: string) {
    this.c = c;
    this.path = path;
  }
}

class Checker {
  errors: string[] = [];
  v1: boolean = false;
  count: number = 0;
  placed: Placed[] = [];
  /** Each valid trigger's steps as a stand-in button, checked like a button's "do". */
  triggerSteps: Placed[] = [];

  add(path: string, message: string): void {
    this.errors.push(`${path}: ${message}`);
  }

  /** Reports unknown and missing fields. `optional` fields may be absent. Returns false on problems. */
  checkFields(obj: JsonRecord, required: string[], path: string, optional?: string[]): boolean {
    const opt = optional ?? [];
    const allowed = required.concat(opt);
    let clean = true;
    for (const key of Object.keys(obj)) {
      if (!allowed.includes(key)) {
        this.add(path, `unknown field "${key}" (allowed: ${allowed.join(', ')})`);
        clean = false;
      }
    }
    for (const key of required) {
      if (!Object.keys(obj).includes(key)) {
        this.add(path, `missing required field "${key}"`);
        clean = false;
      }
    }
    return clean;
  }

  str(obj: JsonRecord, key: string, path: string): string {
    const v: JsonValue = obj[key];
    if (!isNonEmptyString(v)) {
      if (v !== undefined) {
        this.add(`${path}.${key}`, `must be a non-empty string, got ${describe(v)}`);
      }
      return '';
    }
    return v as string;
  }

  children(raw: JsonValue, path: string, depth: number): CapsuleComponent[] {
    const out: CapsuleComponent[] = [];
    if (raw === undefined) {
      return out;
    }
    if (!Array.isArray(raw)) {
      this.add(path, `must be an array of components, got ${describe(raw)}`);
      return out;
    }
    (raw as JsonValue[]).forEach((item: JsonValue, i: number) => {
      const c = this.component(item, `${path}[${i}]`, depth);
      if (c !== null) {
        out.push(c);
      }
    });
    return out;
  }

  component(raw: JsonValue, path: string, depth: number): CapsuleComponent | null {
    this.count++;
    if (!isRecord(raw)) {
      this.add(path, `component must be an object, got ${describe(raw)}`);
      return null;
    }
    const obj = raw as JsonRecord;
    const typeValue: JsonValue = obj['type'];
    const allowedTypes = this.v1 ? COMPONENT_TYPES.concat(V1_COMPONENT_TYPES) : COMPONENT_TYPES;
    if (typeof typeValue !== 'string') {
      this.add(`${path}.type`, `missing or not a string (allowed: ${allowedTypes.join(', ')})`);
      return null;
    }
    const type = typeValue as string;
    if (!allowedTypes.includes(type)) {
      const hint = !this.v1 && V1_COMPONENT_TYPES.includes(type) ? ` - "${type}" needs "schemaVersion": 1` : '';
      this.add(`${path}.type`, `unknown component type "${type}" (allowed: ${allowedTypes.join(', ')})${hint}`);
      return null;
    }
    const before = this.errors.length;
    if (type === 'button' && this.v1) {
      this.checkFields(obj, ['type', 'label'], path, ['action', 'do', 'enabledIf']);
    } else {
      this.checkFields(obj, fieldsFor(type), path);
    }
    let c: CapsuleComponent;
    switch (type) {
      case 'text': {
        const t: TextComponent = { type: 'text', text: this.str(obj, 'text', path) };
        c = t;
        break;
      }
      case 'timer': {
        const t: TimerComponent = {
          type: 'timer', id: this.str(obj, 'id', path), label: this.str(obj, 'label', path), minutes: 0
        };
        const m: JsonValue = obj['minutes'];
        if (typeof m !== 'number' || !Number.isFinite(m as number) || (m as number) <= 0) {
          if (m !== undefined) {
            this.add(`${path}.minutes`, `must be a positive number, got ${describe(m)} ${JSON.stringify(m)}`);
          }
        } else {
          t.minutes = m as number;
        }
        c = t;
        break;
      }
      case 'counter': {
        const t: CounterComponent = {
          type: 'counter', id: this.str(obj, 'id', path), label: this.str(obj, 'label', path), source: 'manual'
        };
        const s: JsonValue = obj['source'];
        if (typeof s !== 'string' || !COUNTER_SOURCES.includes(s as string)) {
          if (s !== undefined) {
            this.add(`${path}.source`, `must be one of ${COUNTER_SOURCES.join(', ')}, got ${JSON.stringify(s)}`);
          }
        } else {
          t.source = s as CounterSource;
        }
        c = t;
        break;
      }
      case 'checklist': {
        const t: ChecklistComponent = { type: 'checklist', id: this.str(obj, 'id', path), items: [] };
        const items: JsonValue = obj['items'];
        if (!Array.isArray(items)) {
          if (items !== undefined) {
            this.add(`${path}.items`, `must be an array of strings, got ${describe(items)}`);
          }
        } else {
          const list = items as JsonValue[];
          if (list.length === 0) {
            this.add(`${path}.items`, 'must contain at least one item');
          }
          list.forEach((item: JsonValue, i: number) => {
            if (!isNonEmptyString(item)) {
              this.add(`${path}.items[${i}]`, `must be a non-empty string, got ${describe(item)}`);
            } else {
              t.items.push(item as string);
            }
          });
        }
        c = t;
        break;
      }
      case 'number': {
        const t: NumberComponent = { type: 'number', id: this.str(obj, 'id', path), label: this.str(obj, 'label', path) };
        c = t;
        break;
      }
      case 'button':
        c = this.button(obj, path);
        break;
      case 'display': {
        const t: DisplayComponent = { type: 'display', text: this.str(obj, 'text', path) };
        c = t;
        break;
      }
      case 'input': {
        const t: InputComponent = {
          type: 'input', bind: this.str(obj, 'bind', path), kind: 'number', label: this.str(obj, 'label', path)
        };
        const k: JsonValue = obj['kind'];
        if (k !== 'number' && k !== 'text') {
          if (k !== undefined) {
            this.add(`${path}.kind`, `must be "number" or "text", got ${JSON.stringify(k)}`);
          }
        } else {
          t.kind = k as InputKind;
        }
        c = t;
        break;
      }
      case 'list': {
        const t: ListComponent = { type: 'list', source: this.str(obj, 'source', path) };
        c = t;
        break;
      }
      case 'when':
      case 'row': {
        const key = type === 'when' ? 'show' : 'items';
        if (depth >= MAX_NESTING) {
          this.add(path, `${type} is nested too deeply (max ${MAX_NESTING} levels)`);
          return null;
        }
        const kids = this.children(obj[key], `${path}.${key}`, depth + 1);
        if (type === 'when') {
          const t: WhenComponent = { type: 'when', if: this.str(obj, 'if', path), show: kids };
          c = t;
        } else {
          const t: RowComponent = { type: 'row', items: kids };
          c = t;
        }
        break;
      }
      default:
        return null;
    }
    if (this.errors.length !== before) {
      return null;
    }
    this.placed.push(new Placed(c, path));
    return c;
  }

  button(obj: JsonRecord, path: string): ButtonComponent {
    const b: ButtonComponent = { type: 'button', label: this.str(obj, 'label', path), action: '' };
    const rawAction: JsonValue = obj['action'];
    const hasDo = obj['do'] !== undefined;
    if (!this.v1 || !hasDo || rawAction !== '') {
      b.action = this.str(obj, 'action', path); // v1 do-buttons may omit action or keep ''
    }
    if (!this.v1) {
      return b;
    }
    if (rawAction === undefined && !hasDo) {
      this.add(path, 'a button needs "action" or "do"');
    }
    if (obj['enabledIf'] !== undefined) {
      b.enabledIf = this.str(obj, 'enabledIf', path);
    }
    if (hasDo) {
      const steps = this.steps(obj['do'], path);
      if (steps !== null) {
        b.do = steps;
      }
    }
    return b;
  }

  /** A "do" list (button or trigger): 1 to MAX_STEPS steps. Null if it is not a non-empty array. */
  steps(raw: JsonValue, path: string): ButtonStep[] | null {
    if (!Array.isArray(raw) || (raw as JsonValue[]).length === 0) {
      this.add(`${path}.do`, `must be a non-empty array of steps, got ${describe(raw)}`);
      return null;
    }
    const list = raw as JsonValue[];
    if (list.length > MAX_STEPS) {
      this.add(`${path}.do`, `has ${list.length} steps (max ${MAX_STEPS})`);
    }
    const steps: ButtonStep[] = [];
    list.forEach((item: JsonValue, i: number) => {
      const step = this.step(item, `${path}.do[${i}]`);
      if (step !== null) {
        steps.push(step);
      }
    });
    return steps;
  }

  /** v1.1 triggers. Returns the valid ones; each also gets a stand-in button so its steps are checked like one. */
  triggers(raw: JsonValue, permissions: Permission[]): Trigger[] {
    const out: Trigger[] = [];
    if (raw === undefined) {
      return out;
    }
    if (!Array.isArray(raw)) {
      this.add('$.triggers', `must be an array, got ${describe(raw)}`);
      return out;
    }
    const list = raw as JsonValue[];
    if (list.length > MAX_TRIGGERS) {
      this.add('$.triggers', `has ${list.length} triggers (max ${MAX_TRIGGERS})`);
    }
    list.forEach((item: JsonValue, i: number) => {
      const path = `$.triggers[${i}]`;
      if (!isRecord(item)) {
        this.add(path, `must be an object, got ${describe(item)}`);
        return;
      }
      const obj = item as JsonRecord;
      const before = this.errors.length;
      const on: JsonValue = obj['on'];
      if (typeof on !== 'string' || !TRIGGER_KINDS.includes(on as string)) {
        this.add(`${path}.on`, `must be one of ${TRIGGER_KINDS.join(', ')}, got ${describe(on)}`);
        return;
      }
      const t: Trigger = { on: on as TriggerKind, do: [] };
      if (t.on === 'time') {
        this.checkFields(obj, ['on', 'at', 'do'], path, ['label']);
        const at = this.str(obj, 'at', path);
        if (at.length > 0 && !/^([01]\d|2[0-3]):[0-5]\d$/.test(at)) {
          this.add(`${path}.at`, `must be a 24-hour time "HH:MM" (00:00-23:59), got ${JSON.stringify(at)}`);
        }
        t.at = at;
      } else {
        this.checkFields(obj, ['on', 'do'], path, ['label']);
      }
      if (obj['label'] !== undefined) {
        const label = this.str(obj, 'label', path);
        if (label.length > MAX_TRIGGER_LABEL) {
          this.add(`${path}.label`, `is ${label.length} characters (max ${MAX_TRIGGER_LABEL})`);
        }
        t.label = label;
      }
      t.do = this.steps(obj['do'], path) ?? [];
      const needed: Permission = t.on === 'time' ? 'reminders' : 'motion';
      if (!permissions.includes(needed)) {
        this.add(path, `a "${t.on}" trigger needs permission "${needed}", which is not listed in "permissions"`);
      }
      if (this.errors.length === before) {
        out.push(t);
        const standIn: ButtonComponent = { type: 'button', label: '', action: '', do: t.do };
        this.triggerSteps.push(new Placed(standIn, path));
      }
    });
    return out;
  }

  step(raw: JsonValue, path: string): ButtonStep | null {
    if (typeof raw === 'string') {
      return raw as string; // a v0 action; checked with the other actions later
    }
    if (!isRecord(raw)) {
      this.add(path, `a step must be an object or a v0 action string, got ${describe(raw)}`);
      return null;
    }
    const obj = raw as JsonRecord;
    const keys = Object.keys(obj);
    const before = this.errors.length;
    const s: StepObject = {};
    if (keys.includes('set')) {
      this.checkFields(obj, ['set', 'to'], path);
      s.set = this.str(obj, 'set', path);
      s.to = this.str(obj, 'to', path);
    } else if (keys.includes('push')) {
      this.checkFields(obj, ['push', 'value'], path);
      s.push = this.str(obj, 'push', path);
      s.value = this.str(obj, 'value', path);
    } else if (keys.includes('pop')) {
      this.checkFields(obj, ['pop'], path);
      s.pop = this.str(obj, 'pop', path);
    } else if (keys.includes('reset')) {
      this.checkFields(obj, ['reset'], path);
      s.reset = this.str(obj, 'reset', path);
    } else {
      this.add(path, 'unknown step (allowed: {set, to}, {push, value}, {pop}, {reset} or a v0 action)');
    }
    return this.errors.length === before ? s : null;
  }
}

function initialMatches(type: VarType, v: JsonValue): boolean {
  switch (type) {
    case 'number':
      return typeof v === 'number' && Number.isFinite(v as number);
    case 'text':
      return typeof v === 'string' && (v as string).length <= MAX_TEXT_LENGTH;
    case 'bool':
      return typeof v === 'boolean';
    default: {
      if (!Array.isArray(v) || (v as JsonValue[]).length > MAX_LIST_ITEMS) {
        return false;
      }
      return (v as JsonValue[]).every((x: JsonValue) => (typeof x === 'number' && Number.isFinite(x as number)) ||
        typeof x === 'boolean' || (typeof x === 'string' && (x as string).length <= MAX_TEXT_LENGTH));
    }
  }
}

function copyInitial(v: JsonValue): Value {
  return Array.isArray(v) ? (v as Scalar[]).slice() : v as Value;
}

/** Parses "state". Returns null when absent. */
function readState(ck: Checker, raw: JsonValue): Record<string, StateVar> | null {
  if (raw === undefined) {
    return null;
  }
  const out: Record<string, StateVar> = {};
  if (!isRecord(raw)) {
    ck.add('$.state', `must be an object of variables, got ${describe(raw)}`);
    return out;
  }
  const obj = raw as JsonRecord;
  const names = Object.keys(obj);
  if (names.length > MAX_VARS) {
    ck.add('$.state', `has ${names.length} variables (max ${MAX_VARS})`);
  }
  names.forEach((name: string) => {
    const path = `$.state.${name}`;
    if (!isValidName(name)) {
      ck.add(path, `"${name}" is not a valid name (letters, digits, _; not a keyword)`);
      return;
    }
    const def: JsonValue = obj[name];
    if (!isRecord(def)) {
      ck.add(path, `must be { "type", "initial" }, got ${describe(def)}`);
      return;
    }
    const d = def as JsonRecord;
    if (!ck.checkFields(d, ['type', 'initial'], path)) {
      return;
    }
    const t: JsonValue = d['type'];
    if (typeof t !== 'string' || !VAR_TYPES.includes(t as string)) {
      ck.add(`${path}.type`, `must be one of ${VAR_TYPES.join(', ')}, got ${JSON.stringify(t)}`);
      return;
    }
    const type = t as VarType;
    if (!initialMatches(type, d['initial'])) {
      const want = type === 'list' ? `a list of up to ${MAX_LIST_ITEMS} numbers, texts or bools` :
        (type === 'text' ? `text up to ${MAX_TEXT_LENGTH} characters` : `a ${type}`);
      ck.add(`${path}.initial`, `must be ${want}, got ${JSON.stringify(d['initial'])}`);
      return;
    }
    out[name] = { type: type, initial: copyInitial(d['initial']) };
  });
  return out;
}

/** Parses "computed". Returns null when absent. */
function readComputed(ck: Checker, raw: JsonValue, state: Record<string, StateVar> | null): Record<string, string> |
  null {
  if (raw === undefined) {
    return null;
  }
  const out: Record<string, string> = {};
  if (!isRecord(raw)) {
    ck.add('$.computed', `must be an object of name: expression, got ${describe(raw)}`);
    return out;
  }
  const obj = raw as JsonRecord;
  const names = Object.keys(obj);
  if (names.length > MAX_VARS) {
    ck.add('$.computed', `has ${names.length} values (max ${MAX_VARS})`);
  }
  names.forEach((name: string) => {
    const path = `$.computed.${name}`;
    if (!isValidName(name)) {
      ck.add(path, `"${name}" is not a valid name (letters, digits, _; not a keyword)`);
    } else if (state !== null && state[name] !== undefined) {
      ck.add(path, `"${name}" is already a state variable`);
    } else if (!isNonEmptyString(obj[name])) {
      ck.add(path, `must be an expression string, got ${describe(obj[name])}`);
    } else {
      out[name] = obj[name] as string;
    }
  });
  return out;
}

function exprType(ck: Checker, src: string, path: string, types: Map<string, VarType>): VarType | null {
  try {
    return typeOf(parseExpr(src), (n: string) => types.get(n) ?? null);
  } catch (e) {
    ck.add(path, `${e instanceof ExprError ? (e as ExprError).message : String(e)} in "${src}"`);
    return null;
  }
}

function stateType(state: Record<string, StateVar>, name: string): VarType | null {
  const v = state[name];
  return v === undefined ? null : v.type;
}

/** A "{name}" placeholder; "{{" and "}}" are literal braces. */
const PLACEHOLDER: RegExp = /(^|[^{])\{\s*([A-Za-z_][^{}]*?)\s*\}(?!\})/;

/**
 * Only "display" text fills in {expressions}; anywhere else a placeholder would be shown literally
 * (e.g. a text component "Reading Streak: {streak}"), so it is rejected.
 */
function checkLiteralPlaceholders(ck: Checker, placed: Placed[]): void {
  const check = (value: string, path: string): void => {
    const m = value.match(PLACEHOLDER);
    if (m !== null) {
      ck.add(path, `"{${m[2]}}" would be shown literally; only a "display" component fills in {...} ` +
        '(it needs "schemaVersion": 1 and a state or computed value with that name)');
    }
  };
  placed.forEach((p: Placed) => {
    const c = p.c;
    if (c.type === 'text') {
      check((c as TextComponent).text, `${p.path}.text`);
    } else if (c.type === 'checklist') {
      (c as ChecklistComponent).items.forEach((item: string, i: number) => check(item, `${p.path}.items[${i}]`));
    } else if (c.type === 'timer') {
      check((c as TimerComponent).label, `${p.path}.label`);
    } else if (c.type === 'counter') {
      check((c as CounterComponent).label, `${p.path}.label`);
    } else if (c.type === 'number') {
      check((c as NumberComponent).label, `${p.path}.label`);
    } else if (c.type === 'input') {
      check((c as InputComponent).label, `${p.path}.label`);
    } else if (c.type === 'button') {
      check((c as ButtonComponent).label, `${p.path}.label`);
    }
  });
}

/** Checks every v1 expression, binding and step against the declared names and types. */
function checkV1(ck: Checker, placed: Placed[], state: Record<string, StateVar>, types: Map<string, VarType>): void {
  const isComputed = (n: string): boolean => types.has(n) && stateType(state, n) === null;
  const needState = (name: string, path: string, what: string): VarType | null => {
    const t = stateType(state, name);
    if (t === null) {
      ck.add(path, isComputed(name) ? `${what} "${name}" is a computed value; use a state variable` :
        `${what} "${name}" is not a state variable`);
    }
    return t;
  };
  placed.forEach((p: Placed) => {
    const c = p.c;
    if (c.type === 'display') {
      const d = c as DisplayComponent;
      try {
        parseTemplate(d.text).forEach((part: TemplatePart) => {
          if (part.isExpr) {
            exprType(ck, part.expr, `${p.path}.text`, types);
          }
        });
      } catch (e) {
        ck.add(`${p.path}.text`, (e as ExprError).message);
      }
    } else if (c.type === 'input') {
      const inp = c as InputComponent;
      const t = needState(inp.bind, `${p.path}.bind`, 'bind');
      if (t !== null && t !== inp.kind) {
        ck.add(`${p.path}.kind`, `a ${inp.kind} input cannot bind "${inp.bind}", which is ${t}`);
      }
    } else if (c.type === 'list') {
      const l = c as ListComponent;
      const t = needState(l.source, `${p.path}.source`, 'source');
      if (t !== null && t !== 'list') {
        ck.add(`${p.path}.source`, `"${l.source}" is ${t}, not a list`);
      }
    } else if (c.type === 'when') {
      const w = c as WhenComponent;
      const t = exprType(ck, w.if, `${p.path}.if`, types);
      if (t !== null && t !== 'bool') {
        ck.add(`${p.path}.if`, `must be a bool expression, got ${t}`);
      }
    } else if (c.type === 'button') {
      const b = c as ButtonComponent;
      if (b.enabledIf !== undefined) {
        const t = exprType(ck, b.enabledIf, `${p.path}.enabledIf`, types);
        if (t !== null && t !== 'bool') {
          ck.add(`${p.path}.enabledIf`, `must be a bool expression, got ${t}`);
        }
      }
      (b.do ?? []).forEach((step: ButtonStep, i: number) => {
        if (typeof step === 'string') {
          return;
        }
        const s = step as StepObject;
        const path = `${p.path}.do[${i}]`;
        if (s.set !== undefined) {
          const t = needState(s.set, `${path}.set`, 'set');
          const vt = exprType(ck, s.to ?? '', `${path}.to`, types);
          if (t !== null && vt !== null && t !== vt) {
            ck.add(`${path}.to`, `"${s.set}" is ${t}, but the expression is ${vt}`);
          }
        } else if (s.push !== undefined) {
          const t = needState(s.push, `${path}.push`, 'push');
          if (t !== null && t !== 'list') {
            ck.add(`${path}.push`, `"${s.push}" is ${t}, not a list`);
          }
          const vt = exprType(ck, s.value ?? '', `${path}.value`, types);
          if (vt === 'list') {
            ck.add(`${path}.value`, 'a list cannot be pushed into a list');
          }
        } else if (s.pop !== undefined) {
          const t = needState(s.pop, `${path}.pop`, 'pop');
          if (t !== null && t !== 'list') {
            ck.add(`${path}.pop`, `"${s.pop}" is ${t}, not a list`);
          }
        } else if (s.reset !== undefined) {
          needState(s.reset, `${path}.reset`, 'reset');
        }
      });
    }
  });
}

/** Checks a v0 action string (from a button's action or a do-step). */
function checkAction(ck: Checker, raw: string, path: string, permissions: Permission[], byId: Map<string,
  CapsuleComponent>, hasTimer: boolean): void {
  const action = parseAction(raw);
  if (action === null) {
    ck.add(path, `unknown action "${raw}" ${ACTIONS_HINT}`);
    return;
  }
  const actionPerm = permissionForAction(action);
  if (actionPerm !== null && !permissions.includes(actionPerm)) {
    ck.add(path, `action "${raw}" needs permission "${actionPerm}", which is not listed in "permissions"`);
  }
  if (action.kind === 'notify' || action.kind === 'startAllTimers') {
    if (action.kind === 'startAllTimers' && !hasTimer) {
      ck.add(path, 'action "startAllTimers" but the capsule has no timer');
    }
    return;
  }
  const target = byId.get(action.arg);
  if (target === undefined) {
    ck.add(path, `action "${raw}" refers to id "${action.arg}", which does not exist`);
  } else if (TIMER_ACTIONS.includes(action.kind) && target.type !== 'timer') {
    ck.add(path, `action "${raw}" needs a timer, but "${action.arg}" is a ${target.type}`);
  } else if (action.kind === 'increment' && target.type !== 'counter') {
    ck.add(path, `action "${raw}" needs a counter, but "${action.arg}" is a ${target.type}`);
  }
}

/** Validates an already-parsed JSON value. */
export function validateCapsuleObject(root: JsonValue): ValidationResult {
  const ck = new Checker();
  if (!isRecord(root)) {
    ck.add('$', `capsule must be a JSON object, got ${describe(root)}`);
    return { ok: false, errors: ck.errors };
  }
  const obj = root as JsonRecord;
  const version: JsonValue = obj['schemaVersion'];
  ck.v1 = version === 1;
  ck.checkFields(obj, CAPSULE_FIELDS, '$', ck.v1 ? V1_CAPSULE_FIELDS : []);
  if (version !== undefined && version !== 0 && version !== 1) {
    ck.add('$.schemaVersion', `must be 0 or 1, got ${JSON.stringify(version)}`);
  }
  const id = ck.str(obj, 'id', '$');
  const name = ck.str(obj, 'name', '$');

  // permissions
  const permissions: Permission[] = [];
  const rawPerms: JsonValue = obj['permissions'];
  if (rawPerms !== undefined) {
    if (!Array.isArray(rawPerms)) {
      ck.add('$.permissions', `must be an array, got ${describe(rawPerms)}`);
    } else {
      (rawPerms as JsonValue[]).forEach((p: JsonValue, i: number) => {
        const path = `$.permissions[${i}]`;
        if (typeof p !== 'string' || !PERMISSIONS.includes(p as string)) {
          ck.add(path, `unknown permission ${JSON.stringify(p)} (allowed: ${PERMISSIONS.join(', ')})`);
        } else if (permissions.includes(p as Permission)) {
          ck.add(path, `duplicate permission "${p as string}"`);
        } else {
          permissions.push(p as Permission);
        }
      });
    }
  }

  // ui (recursively for v1 when/row)
  let ui: CapsuleComponent[] = [];
  const rawUi: JsonValue = obj['ui'];
  if (rawUi !== undefined) {
    if (!Array.isArray(rawUi)) {
      ck.add('$.ui', `must be an array, got ${describe(rawUi)}`);
    } else {
      ui = ck.children(rawUi, '$.ui', 1);
    }
  }
  if (ck.count > MAX_COMPONENTS) {
    ck.add('$.ui', `has ${ck.count} components including nested ones (max ${MAX_COMPONENTS})`);
  }

  // ids must be unique across all components, nested ones included
  const byId = new Map<string, CapsuleComponent>();
  ck.placed.forEach((p: Placed) => {
    const cid = componentId(p.c);
    if (cid !== undefined) {
      if (byId.has(cid)) {
        ck.add(`${p.path}.id`, `duplicate id "${cid}"`);
      } else {
        byId.set(cid, p.c);
      }
    }
  });
  const hasTimer = ck.placed.some((p: Placed) => p.c.type === 'timer');

  const triggers: Trigger[] = ck.v1 ? ck.triggers(obj['triggers'], permissions) : [];

  // permissions and v0 actions (trigger steps included)
  ck.placed.concat(ck.triggerSteps).forEach((p: Placed) => {
    const c = p.c;
    const needed = permissionForComponent(c);
    if (needed !== null && !permissions.includes(needed)) {
      ck.add(p.path, `${c.type} "${componentId(c) ?? ''}" needs permission "${needed}", which is not listed in "permissions"`);
    }
    if (c.type !== 'button') {
      return;
    }
    const b = c as ButtonComponent;
    if (b.action.length > 0) {
      checkAction(ck, b.action, `${p.path}.action`, permissions, byId, hasTimer);
    }
    (b.do ?? []).forEach((step: ButtonStep, i: number) => {
      if (typeof step === 'string') {
        checkAction(ck, step as string, `${p.path}.do[${i}]`, permissions, byId, hasTimer);
      }
    });
  });

  // v1 state, computed and expressions
  let state: Record<string, StateVar> | null = null;
  let computed: Record<string, string> | null = null;
  if (ck.v1) {
    state = readState(ck, obj['state']);
    computed = readComputed(ck, obj['computed'], state);
    let types: Map<string, VarType> | null = null;
    const probe: Capsule = {
      schemaVersion: 1, id: id, name: name, permissions: permissions, ui: [], state: state ?? {}, computed: computed ?? {}
    };
    try {
      types = nameTypes(probe);
    } catch (e) {
      ck.add('$.computed', e instanceof ExprError ? (e as ExprError).message : String(e));
    }
    if (types !== null) {
      checkV1(ck, ck.placed.concat(ck.triggerSteps), state ?? {}, types);
    }
  }

  checkLiteralPlaceholders(ck, ck.placed);

  if (ck.errors.length > 0) {
    return { ok: false, errors: ck.errors };
  }
  const capsule: Capsule = {
    schemaVersion: ck.v1 ? 1 : 0, id: id, name: name, permissions: permissions, ui: ui
  };
  if (state !== null) {
    capsule.state = state;
  }
  if (computed !== null) {
    capsule.computed = computed;
  }
  if (triggers.length > 0) {
    capsule.triggers = triggers;
  }
  return { ok: true, capsule: capsule, errors: [] };
}

/** Parses and validates capsule JSON text. */
export function validateCapsule(json: string): ValidationResult {
  let root: JsonValue;
  try {
    root = JSON.parse(json) as JsonValue;
  } catch (e) {
    const reason = e instanceof Error ? e.message : String(e);
    return { ok: false, errors: [`$: not valid JSON (${reason})`] };
  }
  return validateCapsuleObject(root);
}
