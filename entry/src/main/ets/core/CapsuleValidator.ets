/**
 * Strict validator for SCHEMA.md (schema v0).
 * Unknown fields, unknown component types and unknown actions are rejected.
 * A component or action that needs a permission missing from "permissions" is rejected.
 */
import {
  ActionKind,
  ButtonComponent,
  Capsule,
  CapsuleComponent,
  ChecklistComponent,
  COMPONENT_TYPES,
  COUNTER_SOURCES,
  CounterComponent,
  CounterSource,
  NumberComponent,
  ParsedAction,
  Permission,
  PERMISSIONS,
  SCHEMA_VERSION,
  TextComponent,
  TimerComponent,
  ValidationResult
} from './CapsuleTypes';

type JsonValue = Object | null | undefined;
type JsonRecord = Record<string, Object | null>;

const CAPSULE_FIELDS: string[] = ['schemaVersion', 'id', 'name', 'permissions', 'ui'];

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
  if (head === 'startTimer' || head === 'increment' || head === 'reset' || head === 'notify') {
    return { kind: head as ActionKind, arg: arg };
  }
  return null;
}

/** The component's id, or undefined for text and button. */
export function componentId(c: CapsuleComponent): string | undefined {
  if (c.type === 'text' || c.type === 'button') {
    return undefined;
  }
  return (c as NumberComponent).id;
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

/** Permission an action needs, or null. Starting timers needs reminders; notify needs notifications. */
export function permissionForAction(a: ParsedAction): Permission | null {
  if (a.kind === 'startTimer' || a.kind === 'startAllTimers') {
    return 'reminders';
  }
  if (a.kind === 'notify') {
    return 'notifications';
  }
  return null;
}

class Checker {
  errors: string[] = [];

  add(path: string, message: string): void {
    this.errors.push(`${path}: ${message}`);
  }

  /** Reports unknown and missing fields. Returns false if any were found. */
  checkFields(obj: JsonRecord, allowed: string[], path: string): boolean {
    let clean = true;
    for (const key of Object.keys(obj)) {
      if (!allowed.includes(key)) {
        this.add(path, `unknown field "${key}" (allowed: ${allowed.join(', ')})`);
        clean = false;
      }
    }
    for (const key of allowed) {
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

  component(raw: JsonValue, path: string): CapsuleComponent | null {
    if (!isRecord(raw)) {
      this.add(path, `component must be an object, got ${describe(raw)}`);
      return null;
    }
    const obj = raw as JsonRecord;
    const typeValue: JsonValue = obj['type'];
    if (typeof typeValue !== 'string') {
      this.add(`${path}.type`, `missing or not a string (allowed: ${COMPONENT_TYPES.join(', ')})`);
      return null;
    }
    const type = typeValue as string;
    if (!COMPONENT_TYPES.includes(type)) {
      this.add(`${path}.type`, `unknown component type "${type}" (allowed: ${COMPONENT_TYPES.join(', ')})`);
      return null;
    }
    const before = this.errors.length;
    this.checkFields(obj, fieldsFor(type), path);
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
      default: {
        const t: ButtonComponent = {
          type: 'button', label: this.str(obj, 'label', path), action: this.str(obj, 'action', path)
        };
        c = t;
        break;
      }
    }
    return this.errors.length === before ? c : null;
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
  ck.checkFields(obj, CAPSULE_FIELDS, '$');

  const version: JsonValue = obj['schemaVersion'];
  if (version !== undefined && version !== SCHEMA_VERSION) {
    ck.add('$.schemaVersion', `must be ${SCHEMA_VERSION}, got ${JSON.stringify(version)}`);
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

  // ui
  const ui: CapsuleComponent[] = [];
  const paths: string[] = [];
  const rawUi: JsonValue = obj['ui'];
  if (rawUi !== undefined) {
    if (!Array.isArray(rawUi)) {
      ck.add('$.ui', `must be an array, got ${describe(rawUi)}`);
    } else {
      (rawUi as JsonValue[]).forEach((raw: JsonValue, i: number) => {
        const c = ck.component(raw, `$.ui[${i}]`);
        if (c !== null) {
          ui.push(c);
          paths.push(`$.ui[${i}]`);
        }
      });
    }
  }

  // ids must be unique
  const byId = new Map<string, CapsuleComponent>();
  ui.forEach((c: CapsuleComponent, i: number) => {
    const id = componentId(c);
    if (id !== undefined) {
      if (byId.has(id)) {
        ck.add(`${paths[i]}.id`, `duplicate id "${id}"`);
      } else {
        byId.set(id, c);
      }
    }
  });

  // actions and permissions
  ui.forEach((c: CapsuleComponent, i: number) => {
    const needed = permissionForComponent(c);
    if (needed !== null && !permissions.includes(needed)) {
      ck.add(paths[i], `${c.type} "${componentId(c) ?? ''}" needs permission "${needed}", which is not listed in "permissions"`);
    }
    if (c.type !== 'button') {
      return;
    }
    const raw = (c as ButtonComponent).action;
    const path = `${paths[i]}.action`;
    const action = parseAction(raw);
    if (action === null) {
      ck.add(path, `unknown action "${raw}" (allowed: startTimer:<id>, startAllTimers, increment:<id>, ` +
        'reset:<id>, notify:<text>)');
      return;
    }
    const actionPerm = permissionForAction(action);
    if (actionPerm !== null && !permissions.includes(actionPerm)) {
      ck.add(path, `action "${raw}" needs permission "${actionPerm}", which is not listed in "permissions"`);
    }
    if (action.kind === 'notify' || action.kind === 'startAllTimers') {
      if (action.kind === 'startAllTimers' && !ui.some((x: CapsuleComponent) => x.type === 'timer')) {
        ck.add(path, 'action "startAllTimers" but the capsule has no timer');
      }
      return;
    }
    const target = byId.get(action.arg);
    if (target === undefined) {
      ck.add(path, `action "${raw}" refers to id "${action.arg}", which does not exist`);
    } else if (action.kind === 'startTimer' && target.type !== 'timer') {
      ck.add(path, `action "${raw}" needs a timer, but "${action.arg}" is a ${target.type}`);
    } else if (action.kind === 'increment' && target.type !== 'counter') {
      ck.add(path, `action "${raw}" needs a counter, but "${action.arg}" is a ${target.type}`);
    }
  });

  if (ck.errors.length > 0) {
    return { ok: false, errors: ck.errors };
  }
  const capsule: Capsule = { schemaVersion: SCHEMA_VERSION, id: id, name: name, permissions: permissions, ui: ui };
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
