/**
 * Runs schema v1 capsules: state, computed values, display templates, when/enabledIf conditions,
 * inputs and button steps. Pure and deterministic. The validator has already checked names and
 * types; everything here still fails safely (an error result, never a crash or a partial update).
 *
 * v0 actions inside a button ("startTimer:pasta", "notify:...") are not run here: they are
 * returned in ApplyResult.actions, in order, for the runtime to dispatch through the gatekeeper.
 */
import {
  ButtonComponent,
  ButtonStep,
  Capsule,
  CapsuleComponent,
  RowComponent,
  Scalar,
  StateVar,
  StepObject,
  Value,
  VarType,
  WhenComponent
} from './CapsuleTypes';
import {
  evalExpr,
  ExprError,
  formatValue,
  MAX_LIST_ITEMS,
  MAX_TEXT_LENGTH,
  parseExpr,
  parseTemplate,
  StepBudget,
  TemplatePart,
  typeOf,
  typeOfValue
} from './Expr';

/** Current values of a capsule's state vars, by name. */
export type StateValues = Record<string, Value>;

export interface EvalResult {
  ok: boolean;
  value?: Value; // present when ok
  error?: string; // present when not ok
}

export interface ApplyResult {
  ok: boolean;
  /** The new state when ok; the unchanged input state when not. */
  state: StateValues;
  /** v0 actions to dispatch, in order (e.g. "startTimer:pasta"). Empty when not ok. */
  actions: string[];
  error?: string;
}

/** What a failed {expr} shows in a display. */
export const DISPLAY_ERROR: string = '?';

function errorText(e: Object): string {
  return e instanceof Error ? e.message : String(e);
}

function copyValue(v: Value): Value {
  return Array.isArray(v) ? (v as Scalar[]).slice() : v;
}

function copyState(state: StateValues): StateValues {
  const out: StateValues = {};
  Object.keys(state).forEach((k: string) => {
    out[k] = copyValue(state[k]);
  });
  return out;
}

function stateVars(capsule: Capsule): Record<string, StateVar> {
  return capsule.state ?? {};
}

function computedExprs(capsule: Capsule): Record<string, string> {
  return capsule.computed ?? {};
}

// ---- Types of names (used by the validator too) ----

/**
 * Types of every state and computed name. Computed types are inferred from their expressions.
 * Throws ExprError (message names the computed value) for cycles, unknown names or bad types.
 */
export function nameTypes(capsule: Capsule): Map<string, VarType> {
  const types = new Map<string, VarType>();
  const vars = stateVars(capsule);
  Object.keys(vars).forEach((name: string) => {
    types.set(name, vars[name].type);
  });
  const exprs = computedExprs(capsule);
  const visiting: string[] = [];
  const resolve = (name: string): VarType | null => {
    const known = types.get(name);
    if (known !== undefined) {
      return known;
    }
    if (exprs[name] === undefined) {
      return null;
    }
    if (visiting.includes(name)) {
      throw new ExprError(`computed values form a cycle: ${visiting.concat([name]).join(' -> ')}`);
    }
    visiting.push(name);
    let t: VarType;
    try {
      t = typeOf(parseExpr(exprs[name]), resolve);
    } catch (e) {
      const msg = errorText(e);
      throw new ExprError(msg.startsWith('computed values form a cycle') || msg.startsWith('computed "') ? msg :
        `computed "${name}": ${msg}`);
    }
    visiting.pop();
    types.set(name, t);
    return t;
  };
  Object.keys(exprs).forEach((name: string) => {
    resolve(name);
  });
  return types;
}

// ---- Evaluation scope ----

/** One snapshot of state: computed values are evaluated lazily and memoised. */
class Scope {
  private capsule: Capsule;
  private state: StateValues;
  private memo: Map<string, Value> = new Map<string, Value>();
  private visiting: string[] = [];
  budget: StepBudget;

  constructor(capsule: Capsule, state: StateValues, budget: StepBudget) {
    this.capsule = capsule;
    this.state = state;
    this.budget = budget;
  }

  lookup(name: string): Value {
    if (Object.keys(this.state).includes(name)) {
      return this.state[name];
    }
    const memo = this.memo.get(name);
    if (memo !== undefined) {
      return memo;
    }
    const src = computedExprs(this.capsule)[name];
    if (src === undefined) {
      throw new ExprError(`unknown name "${name}"`);
    }
    if (this.visiting.includes(name)) {
      throw new ExprError(`computed "${name}" depends on itself`);
    }
    this.visiting.push(name);
    const v = this.eval(src);
    this.visiting.pop();
    this.memo.set(name, v);
    return v;
  }

  eval(src: string): Value {
    return evalExpr(parseExpr(src), (n: string) => this.lookup(n), this.budget);
  }
}

// ---- Public API ----

/** Fresh state with every var at its initial value. */
export function initialState(capsule: Capsule): StateValues {
  const vars = stateVars(capsule);
  const out: StateValues = {};
  Object.keys(vars).forEach((name: string) => {
    out[name] = copyValue(vars[name].initial);
  });
  return out;
}

/**
 * Restores saved state: keeps values whose name and type still match the capsule, falls back to
 * initial values for the rest. Use when loading persisted state.
 */
export function restoreState(capsule: Capsule, saved: StateValues): StateValues {
  const out = initialState(capsule);
  const vars = stateVars(capsule);
  Object.keys(out).forEach((name: string) => {
    const v = saved[name];
    if (v !== undefined && v !== null && typeOfValue(v) === vars[name].type) {
      out[name] = copyValue(v);
    }
  });
  return out;
}

/** Evaluates one expression (state or computed names allowed). */
export function evaluate(capsule: Capsule, state: StateValues, expr: string): EvalResult {
  try {
    return { ok: true, value: new Scope(capsule, state, new StepBudget()).eval(expr) };
  } catch (e) {
    return { ok: false, error: errorText(e) };
  }
}

/** Every computed value for this state. A failing one has ok false. */
export function computedValues(capsule: Capsule, state: StateValues): Map<string, EvalResult> {
  const out = new Map<string, EvalResult>();
  Object.keys(computedExprs(capsule)).forEach((name: string) => {
    out.set(name, evaluate(capsule, state, name));
  });
  return out;
}

/** Text for a display component: each {expr} is replaced by its value, or "?" if it fails. */
export function renderTemplate(capsule: Capsule, state: StateValues, template: string): string {
  let parts: TemplatePart[];
  try {
    parts = parseTemplate(template);
  } catch (e) {
    return DISPLAY_ERROR;
  }
  const scope = new Scope(capsule, state, new StepBudget());
  return parts.map((p: TemplatePart) => {
    if (!p.isExpr) {
      return p.literal;
    }
    try {
      return formatValue(scope.eval(p.expr));
    } catch (e) {
      return DISPLAY_ERROR;
    }
  }).join('');
}

function truthy(capsule: Capsule, state: StateValues, expr: string): boolean {
  const r = evaluate(capsule, state, expr);
  return r.ok && r.value === true;
}

/** Whether a when component shows its children. False if the condition fails. */
export function isShown(capsule: Capsule, state: StateValues, when: WhenComponent): boolean {
  return truthy(capsule, state, when.if);
}

/** Whether a button can be pressed. True when it has no enabledIf; false if the condition fails. */
export function isEnabled(capsule: Capsule, state: StateValues, button: ButtonComponent): boolean {
  return button.enabledIf === undefined || truthy(capsule, state, button.enabledIf);
}

/** Items of a list var, formatted for display. */
export function listItems(state: StateValues, source: string): string[] {
  const v = state[source];
  return Array.isArray(v) ? (v as Scalar[]).map((x: Scalar) => formatValue(x)) : [];
}

/** The text an input bound to `name` should show. */
export function inputText(state: StateValues, name: string): string {
  const v = state[name];
  return v === undefined || v === null ? '' : formatValue(v);
}

function checkValue(name: string, type: VarType, v: Value): Value {
  const actual = typeOfValue(v);
  if (actual !== type) {
    throw new ExprError(`"${name}" is ${type}, but the value is ${actual}`);
  }
  if (typeof v === 'string' && (v as string).length > MAX_TEXT_LENGTH) {
    throw new ExprError(`"${name}" would be longer than ${MAX_TEXT_LENGTH} characters`);
  }
  return v;
}

function varType(capsule: Capsule, name: string): VarType {
  const v = stateVars(capsule)[name];
  if (v === undefined) {
    throw new ExprError(`"${name}" is not a state variable`);
  }
  return v.type;
}

function runStep(capsule: Capsule, state: StateValues, step: StepObject, budget: StepBudget): void {
  const scope = new Scope(capsule, state, budget);
  if (step.set !== undefined) {
    state[step.set] = checkValue(step.set, varType(capsule, step.set), scope.eval(step.to ?? ''));
  } else if (step.push !== undefined) {
    if (varType(capsule, step.push) !== 'list') {
      throw new ExprError(`"${step.push}" is not a list`);
    }
    const item = scope.eval(step.value ?? '');
    if (Array.isArray(item)) {
      throw new ExprError('a list cannot be pushed into a list');
    }
    if (typeof item === 'string' && (item as string).length > MAX_TEXT_LENGTH) {
      throw new ExprError(`list items are limited to ${MAX_TEXT_LENGTH} characters`);
    }
    const list = (state[step.push] as Scalar[]).slice();
    if (list.length >= MAX_LIST_ITEMS) {
      throw new ExprError(`"${step.push}" already has ${MAX_LIST_ITEMS} items`);
    }
    list.push(item as Scalar);
    state[step.push] = list;
  } else if (step.pop !== undefined) {
    if (varType(capsule, step.pop) !== 'list') {
      throw new ExprError(`"${step.pop}" is not a list`);
    }
    const list = (state[step.pop] as Scalar[]).slice();
    list.pop();
    state[step.pop] = list;
  } else if (step.reset !== undefined) {
    varType(capsule, step.reset);
    state[step.reset] = copyValue(stateVars(capsule)[step.reset].initial);
  } else {
    throw new ExprError('empty step');
  }
}

/**
 * Presses a button: runs its v0 action (if any) and then its do-steps in order, each step seeing
 * the state left by the previous one. All-or-nothing: on any error the input state is returned
 * unchanged with ok false. The input state object is never modified.
 */
export function applyActions(capsule: Capsule, state: StateValues, button: ButtonComponent): ApplyResult {
  if (!isEnabled(capsule, state, button)) {
    return { ok: false, state: state, actions: [], error: 'This button is disabled right now.' };
  }
  const next = copyState(state);
  const actions: string[] = [];
  const budget = new StepBudget();
  const steps: ButtonStep[] = (button.action.length > 0 ? [button.action as ButtonStep] : []).concat(button.do ?? []);
  try {
    for (const step of steps) {
      if (typeof step === 'string') {
        actions.push(step as string);
      } else {
        runStep(capsule, next, step as StepObject, budget);
      }
    }
  } catch (e) {
    return { ok: false, state: state, actions: [], error: errorText(e) };
  }
  return { ok: true, state: next, actions: actions };
}

/**
 * Applies what the user typed into an input bound to `name`. Number inputs must parse as a
 * finite number ('' is rejected); text is limited to 500 characters. Never modifies `state`.
 */
export function setInput(capsule: Capsule, state: StateValues, name: string, raw: string): ApplyResult {
  try {
    const type = varType(capsule, name);
    let v: Value;
    if (type === 'number') {
      const trimmed = raw.trim();
      const n = trimmed.length === 0 ? NaN : Number(trimmed);
      if (!Number.isFinite(n)) {
        throw new ExprError(`"${raw}" is not a number`);
      }
      v = n;
    } else if (type === 'text') {
      v = raw;
    } else {
      throw new ExprError(`"${name}" cannot be bound to an input`);
    }
    const next = copyState(state);
    next[name] = checkValue(name, type, v);
    return { ok: true, state: next, actions: [] };
  } catch (e) {
    return { ok: false, state: state, actions: [], error: errorText(e) };
  }
}

/** Every component, including those nested in when/row, depth first. */
export function allComponents(ui: CapsuleComponent[]): CapsuleComponent[] {
  const out: CapsuleComponent[] = [];
  const walk = (list: CapsuleComponent[]): void => {
    list.forEach((c: CapsuleComponent) => {
      out.push(c);
      if (c.type === 'when') {
        walk((c as WhenComponent).show);
      } else if (c.type === 'row') {
        walk((c as RowComponent).items);
      }
    });
  };
  walk(ui);
  return out;
}
