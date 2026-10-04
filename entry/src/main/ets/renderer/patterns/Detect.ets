/**
 * Picks a layout pattern for a capsule from its EXISTING schema v1 content (docs/ui-redesign-plan.md section e).
 * View layer only: nothing here changes state, expressions or the schema. Pure, so it is unit tested.
 *
 * Rules, first match wins: record list, versus, converter, form + live result, timer ring, quiz, goal ring,
 * grouped checklist; anything else is "generic" (restyled cards). Week grids cannot be detected: no field
 * encodes days.
 *
 * A plan lists the components the pattern draws itself (`consumed`, at any depth); PatternView draws every other
 * component generically, in its original order, skipping consumed ones (a row whose children are all consumed
 * disappears).
 */
import {
  ButtonComponent,
  ButtonStep,
  Capsule,
  CapsuleComponent,
  ChecklistComponent,
  DisplayComponent,
  InputComponent,
  RowComponent,
  StepObject,
  TextComponent,
  TimerComponent,
  WhenComponent
} from '../../core/CapsuleTypes';
import { allComponents } from '../../core/CapsuleProgram';

export type PatternKind = 'record-list' | 'versus' | 'form' | 'converter' | 'timer-ring' | 'goal-ring' | 'quiz' |
  'grouped-checklist' | 'generic';

export class RecordItem {
  row: RowComponent;
  toggle: ButtonComponent;
  boolVar: string;
  /** The row's other children, drawn inside the record card. */
  parts: CapsuleComponent[];

  constructor(row: RowComponent, toggle: ButtonComponent, boolVar: string) {
    this.row = row;
    this.toggle = toggle;
    this.boolVar = boolVar;
    this.parts = row.items.filter((c: CapsuleComponent) => c !== toggle);
  }
}

export class VersusSide {
  button: ButtonComponent;
  name: string;
  /** The number var this side scores in (points). */
  pointsVar: string;
  /** A computed text var that spells the points ("15", "AD"), or '' to show pointsVar. */
  pointsText: string = '';
  /** A second number var only this side's button raises (games), or ''. */
  gamesVar: string = '';

  constructor(button: ButtonComponent, name: string, pointsVar: string) {
    this.button = button;
    this.name = name;
    this.pointsVar = pointsVar;
  }
}

export class SegmentPick {
  varName: string;
  label: string;
  buttons: ButtonComponent[];
  literals: number[];

  constructor(varName: string, label: string, buttons: ButtonComponent[], literals: number[]) {
    this.varName = varName;
    this.label = label;
    this.buttons = buttons;
    this.literals = literals;
  }
}

export class ConverterPair {
  input: InputComponent;
  result: DisplayComponent;

  constructor(input: InputComponent, result: DisplayComponent) {
    this.input = input;
    this.result = result;
  }
}

export class GoalPlan {
  display: DisplayComponent;
  countVar: string;
  /** A number literal, or a state var holding the total. */
  totalLiteral: number;
  totalVar: string;
  /** Words after the total in the display ("glasses", "push-ups"). */
  unit: string;
  add?: ButtonComponent;
  undo?: ButtonComponent;

  constructor(display: DisplayComponent, countVar: string, totalLiteral: number, totalVar: string, unit: string) {
    this.display = display;
    this.countVar = countVar;
    this.totalLiteral = totalLiteral;
    this.totalVar = totalVar;
    this.unit = unit;
  }
}

export class QuizStep {
  when: WhenComponent;
  /** The literal the position var is compared with (0-based question number), or -1. */
  position: number;

  constructor(when: WhenComponent, position: number) {
    this.when = when;
    this.position = position;
  }
}

export class QuizPlan {
  question?: DisplayComponent;
  steps: QuizStep[] = [];
  /** True when each step shows its answer buttons; false when each step shows a statement and `answers` answer it. */
  buttonsInSteps: boolean = true;
  answers: ButtonComponent[] = [];
  score?: DisplayComponent;
  next?: ButtonComponent;
}

export class ChecklistGroup {
  title: TextComponent;
  list: ChecklistComponent;

  constructor(title: TextComponent, list: ChecklistComponent) {
    this.title = title;
    this.list = list;
  }
}

export class PatternPlan {
  kind: PatternKind = 'generic';
  consumed: CapsuleComponent[] = [];
  records: RecordItem[] = [];
  /** Record list: a top-level "Add ..." button drawn as the dashed add button. */
  addButton?: ButtonComponent;
  sides: VersusSide[] = [];
  /** Versus: status chips (single-expression displays and when[display] blocks). */
  chips: CapsuleComponent[] = [];
  hero?: DisplayComponent;
  subLines: DisplayComponent[] = [];
  inputs: InputComponent[] = [];
  segments: SegmentPick[] = [];
  pairs: ConverterPair[] = [];
  timers: TimerComponent[] = [];
  goal?: GoalPlan;
  quiz?: QuizPlan;
  groups: ChecklistGroup[] = [];
}

// ---- Expression helpers ----

const KEYWORDS: string[] = ['true', 'false', 'and', 'or', 'not', 'if', 'min', 'max', 'round', 'abs', 'len'];

/** Names used in an expression or a display template (quoted text ignored). */
export function namesIn(text: string): string[] {
  const bare = text.replace(/'[^']*'|"[^"]*"/g, ' ');
  const out: string[] = [];
  (bare.match(/[A-Za-z_][A-Za-z0-9_]*/g) ?? []).forEach((n: string) => {
    if (KEYWORDS.indexOf(n) < 0 && out.indexOf(n) < 0) {
      out.push(n);
    }
  });
  return out;
}

function countName(text: string, name: string): number {
  const bare = text.replace(/'[^']*'|"[^"]*"/g, ' ');
  return (bare.match(new RegExp(`\\b${name}\\b`, 'g')) ?? []).length;
}

/** The {expr} parts of a display template ("{{" and "}}" are literal braces). */
export function templateExprs(template: string): string[] {
  const t = template.replace(/\{\{|\}\}/g, '');
  const out: string[] = [];
  const re = /\{([^{}]*)\}/g;
  let m = re.exec(t);
  while (m !== null) {
    out.push(m[1].trim());
    m = re.exec(t);
  }
  return out;
}

function squash(expr: string): string {
  return expr.replace(/\s+/g, '');
}

function stateType(capsule: Capsule, name: string): string {
  const s = capsule.state;
  return s !== undefined && s[name] !== undefined ? s[name].type : '';
}

function computedExpr(capsule: Capsule, name: string): string {
  const c = capsule.computed;
  return c !== undefined && c[name] !== undefined ? c[name] : '';
}

/** Every state var an expression depends on, following computed values (no cycles: validated). */
function deps(capsule: Capsule, names: string[], seen?: string[]): string[] {
  const out: string[] = seen ?? [];
  names.forEach((n: string) => {
    if (out.indexOf(n) >= 0) {
      return;
    }
    out.push(n);
    const expr = computedExpr(capsule, n);
    if (expr.length > 0) {
      deps(capsule, namesIn(expr), out);
    }
  });
  return out;
}

function stepsOf(b: ButtonComponent): ButtonStep[] {
  const steps: ButtonStep[] = (b.do ?? []).slice();
  const action: string = b.action ?? ''; // unvalidated JSON may omit it
  if (action.length > 0) {
    steps.push(action);
  }
  return steps;
}

function stepObjects(b: ButtonComponent): StepObject[] {
  return stepsOf(b).filter((s: ButtonStep) => typeof s !== 'string').map((s: ButtonStep) => s as StepObject);
}

/** Vars a button raises by one: set v to an expression with "v+1" in it, or increment:<counter>. */
function raisedVars(b: ButtonComponent): string[] {
  const out: string[] = [];
  stepsOf(b).forEach((s: ButtonStep) => {
    if (typeof s === 'string') {
      const a = s as string;
      if (a.startsWith('increment:')) {
        out.push(a.substring('increment:'.length));
      }
      return;
    }
    const o = s as StepObject;
    if (o.set !== undefined && o.to !== undefined && squash(o.to).indexOf(`${o.set}+1`) >= 0 && out.indexOf(o.set) < 0) {
      out.push(o.set);
    }
  });
  return out;
}

function setVars(b: ButtonComponent): string[] {
  return stepObjects(b).filter((o: StepObject) => o.set !== undefined).map((o: StepObject) => o.set as string);
}

function topButtons(items: CapsuleComponent[]): ButtonComponent[] {
  return items.filter((c: CapsuleComponent) => c.type === 'button').map((c: CapsuleComponent) => c as ButtonComponent);
}

// ---- Rules ----

function detectRecords(capsule: Capsule, plan: PatternPlan): boolean {
  capsule.ui.forEach((c: CapsuleComponent) => {
    if (c.type !== 'row') {
      return;
    }
    const row = c as RowComponent;
    for (const b of topButtons(row.items)) {
      const steps = b.do ?? [];
      if (steps.length !== 1 || typeof steps[0] === 'string') {
        continue;
      }
      const o = steps[0] as StepObject;
      if (o.set !== undefined && o.to !== undefined && stateType(capsule, o.set) === 'bool' &&
        (squash(o.to) === `not${o.set}` || squash(o.to) === `not(${o.set})`)) {
        plan.records.push(new RecordItem(row, b, o.set));
        break;
      }
    }
  });
  if (plan.records.length === 0) {
    return false;
  }
  plan.kind = 'record-list';
  plan.records.forEach((r: RecordItem) => plan.consumed.push(r.row));
  const add = topButtons(capsule.ui).find((b: ButtonComponent) => /^add\b/i.test(b.label.trim()));
  if (add !== undefined) {
    plan.addButton = add;
    plan.consumed.push(add);
  }
  return true;
}

function sideName(label: string, i: number): string {
  const n = label.replace(/^\s*(\+\s*\d*\s*)?(points?|score|scored|goal|win|won|wins|game|rack|round|\+)?\s*(for|to)?\s*:?\s*/i,
    '').replace(/\s+(wins?|won|scores?)(\s+\w+)?\s*$/i, '').replace(/\s*(\+\s*\d+|point)\s*$/i, '').trim();
  return n.length > 0 && n.length <= 24 ? n : `Player ${i + 1}`;
}

/** Two sides keep score in mirrored vars: p1/p2, a/b, w1/w2 (same length, one character apart). */
function mirrored(a: string, b: string): boolean {
  if (a.length !== b.length || a === b) {
    return false;
  }
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    if (a.charAt(i) !== b.charAt(i)) {
      diff++;
    }
  }
  return diff === 1;
}

function detectVersus(capsule: Capsule, plan: PatternPlan): boolean {
  const displays = capsule.ui.filter((c: CapsuleComponent) => c.type === 'display').length;
  const counters = capsule.ui.filter((c: CapsuleComponent) => c.type === 'counter').length;
  if (displays < 2 && counters < 2) {
    return false;
  }
  let main: RowComponent | undefined = undefined;
  for (const c of capsule.ui) {
    if (c.type !== 'row') {
      continue;
    }
    const row = c as RowComponent;
    if (row.items.length !== 2 || row.items.some((x: CapsuleComponent) => x.type !== 'button')) {
      continue;
    }
    const a = raisedVars(row.items[0] as ButtonComponent);
    const b = raisedVars(row.items[1] as ButtonComponent);
    if (a.length > 0 && b.length > 0 && !a.some((v: string) => b.indexOf(v) >= 0) &&
      a.some((x: string) => b.some((y: string) => mirrored(x, y)))) {
      main = row;
      break;
    }
  }
  if (main === undefined) {
    return false;
  }
  const buttons = main.items.map((c: CapsuleComponent) => c as ButtonComponent);
  const raised = buttons.map((b: ButtonComponent) => raisedVars(b));
  const sets = buttons.map((b: ButtonComponent) => setVars(b));
  buttons.forEach((b: ButtonComponent, i: number) => {
    const other = 1 - i;
    // Points: a var this side raises that the other side also sets (resets on a won game); else the first raised.
    const shared = raised[i].find((v: string) => sets[other].indexOf(v) >= 0);
    const side = new VersusSide(b, sideName(b.label, i), shared ?? raised[i][0]);
    if (shared !== undefined) {
      side.gamesVar = raised[i].find((v: string) => v !== shared && sets[other].indexOf(v) < 0) ?? '';
    }
    plan.sides.push(side);
  });
  // A computed text that spells each side's points: mentions its own points var more than the other side's.
  const computed = capsule.computed;
  if (computed !== undefined) {
    plan.sides.forEach((s: VersusSide, i: number) => {
      const otherVar = plan.sides[1 - i].pointsVar;
      const name = Object.keys(computed).find((k: string) => {
        const e = computed[k];
        return e.indexOf("'") >= 0 && countName(e, s.pointsVar) > countName(e, otherVar);
      });
      s.pointsText = name ?? '';
    });
  }
  const sideVars: string[] = [];
  plan.sides.forEach((s: VersusSide) => {
    [s.pointsVar, s.gamesVar, s.pointsText].filter((v: string) => v.length > 0).forEach((v: string) => sideVars.push(v));
  });
  plan.kind = 'versus';
  plan.consumed.push(main);
  capsule.ui.forEach((c: CapsuleComponent) => {
    if (c.type === 'display') {
      const d = c as DisplayComponent;
      const exprs = templateExprs(d.text);
      const literal = d.text.replace(/\{[^{}]*\}/g, '').trim();
      if (exprs.length === 1 && literal.length === 0 && !namesIn(exprs[0]).some((n: string) => sideVars.indexOf(n) >= 0)) {
        plan.chips.push(d); // "{status}": Deuce, Advantage ...
        plan.consumed.push(d);
      } else if (namesIn(d.text).some((n: string) => sideVars.indexOf(n) >= 0)) {
        plan.consumed.push(d); // the side cards show these numbers
      }
    } else if (c.type === 'when' && (c as WhenComponent).show.length > 0 &&
      (c as WhenComponent).show.every((x: CapsuleComponent) => x.type === 'display')) {
      plan.chips.push(c);
      plan.consumed.push(c);
    }
  });
  return true;
}

function segmentRow(capsule: Capsule, row: RowComponent, inputs: InputComponent[]): SegmentPick | null {
  if (row.items.length < 2 || row.items.length > 4 || row.items.some((x: CapsuleComponent) => x.type !== 'button')) {
    return null;
  }
  let varName = '';
  const literals: number[] = [];
  for (const x of row.items) {
    const steps = (x as ButtonComponent).do ?? [];
    if (steps.length !== 1 || typeof steps[0] === 'string') {
      return null;
    }
    const o = steps[0] as StepObject;
    if (o.set === undefined || o.to === undefined || !/^-?\d+(\.\d+)?$/.test(o.to.trim()) ||
      (varName.length > 0 && o.set !== varName)) {
      return null;
    }
    varName = o.set;
    literals.push(Number(o.to.trim()));
  }
  const input = inputs.find((i: InputComponent) => i.bind === varName);
  return new SegmentPick(varName, input !== undefined ? input.label : '',
    row.items.map((x: CapsuleComponent) => x as ButtonComponent), literals);
}

function detectForm(capsule: Capsule, plan: PatternPlan): boolean {
  const flat = allComponents(capsule.ui);
  if (flat.some((c: CapsuleComponent) => c.type === 'timer')) {
    return false;
  }
  const inputs = capsule.ui.filter((c: CapsuleComponent) => c.type === 'input').map((c: CapsuleComponent) =>
    c as InputComponent);
  if (inputs.length === 0 || !inputs.some((i: InputComponent) => i.kind === 'number')) {
    return false;
  }
  const bound = inputs.map((i: InputComponent) => i.bind);
  const dependent = capsule.ui.filter((c: CapsuleComponent) => c.type === 'display' &&
    deps(capsule, namesIn((c as DisplayComponent).text)).some((n: string) => bound.indexOf(n) >= 0))
    .map((c: CapsuleComponent) => c as DisplayComponent);
  if (dependent.length === 0) {
    return false;
  }
  plan.kind = 'form';
  plan.inputs = inputs;
  plan.hero = dependent[0];
  plan.subLines = dependent.slice(1, 4);
  inputs.forEach((i: InputComponent) => plan.consumed.push(i));
  plan.consumed.push(dependent[0]);
  plan.subLines.forEach((d: DisplayComponent) => plan.consumed.push(d));
  capsule.ui.forEach((c: CapsuleComponent) => {
    if (c.type === 'row') {
      const seg = segmentRow(capsule, c as RowComponent, inputs);
      if (seg !== null) {
        plan.segments.push(seg);
        plan.consumed.push(c);
      }
    }
  });
  return true;
}

function detectConverter(capsule: Capsule, plan: PatternPlan): boolean {
  const ui = capsule.ui;
  const inputs = ui.filter((c: CapsuleComponent) => c.type === 'input');
  if (inputs.length !== 2) {
    return false;
  }
  const pairs: ConverterPair[] = [];
  ui.forEach((c: CapsuleComponent, i: number) => {
    if (c.type === 'input' && (c as InputComponent).kind === 'number' && i + 1 < ui.length && ui[i + 1].type === 'display') {
      pairs.push(new ConverterPair(c as InputComponent, ui[i + 1] as DisplayComponent));
    }
  });
  if (pairs.length !== 2 || allComponents(ui).some((c: CapsuleComponent) => c.type === 'timer')) {
    return false;
  }
  plan.kind = 'converter';
  plan.pairs = pairs;
  pairs.forEach((p: ConverterPair) => {
    plan.consumed.push(p.input);
    plan.consumed.push(p.result);
  });
  return true;
}

function detectTimers(capsule: Capsule, plan: PatternPlan): boolean {
  const timers = capsule.ui.filter((c: CapsuleComponent) => c.type === 'timer').map((c: CapsuleComponent) =>
    c as TimerComponent);
  if (timers.length === 0) {
    return false;
  }
  plan.kind = 'timer-ring';
  plan.timers = timers;
  timers.forEach((t: TimerComponent) => plan.consumed.push(t));
  return true;
}

const GOAL_RE: RegExp = /\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*\}\s*(?:of|\/)\s*(?:\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*\}|(\d+))\s*([^{]*)/i;

function detectGoal(capsule: Capsule, plan: PatternPlan): boolean {
  for (const c of capsule.ui) {
    if (c.type !== 'display') {
      continue;
    }
    const d = c as DisplayComponent;
    const m = d.text.match(GOAL_RE);
    if (m === null || stateType(capsule, m[1]) !== 'number') {
      continue;
    }
    const totalVar = m[2] !== undefined ? m[2] : '';
    if (totalVar.length > 0 && stateType(capsule, totalVar) !== 'number') {
      continue;
    }
    const count = m[1];
    const unit = (m[4] ?? '').split('(')[0].trim();
    const goal = new GoalPlan(d, count, m[3] !== undefined ? Number(m[3]) : 0, totalVar, unit);
    const buttons = allComponents(capsule.ui).filter((x: CapsuleComponent) => x.type === 'button')
      .map((x: CapsuleComponent) => x as ButtonComponent);
    goal.add = buttons.find((b: ButtonComponent) => stepObjects(b).some((o: StepObject) => o.set === count &&
      o.to !== undefined && squash(o.to) === `${count}+1`));
    goal.undo = buttons.find((b: ButtonComponent) => stepObjects(b).some((o: StepObject) => (o.set === count &&
      o.to !== undefined && squash(o.to).indexOf(`${count}-1`) >= 0) || o.reset === count));
    if (goal.add === undefined) {
      continue;
    }
    plan.kind = 'goal-ring';
    plan.goal = goal;
    plan.consumed.push(d);
    plan.consumed.push(goal.add);
    if (goal.undo !== undefined) {
      plan.consumed.push(goal.undo);
    }
    return true;
  }
  return false;
}

/** "q == 2" -> 2; anything else -1. */
function positionOf(w: WhenComponent): number {
  const m = w.if.match(/^\s*[A-Za-z_][A-Za-z0-9_]*\s*==\s*(\d+)\s*$/);
  return m !== null ? Number(m[1]) : -1;
}

function detectQuiz(capsule: Capsule, plan: PatternPlan): boolean {
  const whens = capsule.ui.filter((c: CapsuleComponent) => c.type === 'when').map((c: CapsuleComponent) =>
    c as WhenComponent).filter((w: WhenComponent) => positionOf(w) >= 0);
  const buttonSteps = whens.filter((w: WhenComponent) => w.show.length >= 2 && w.show.length <= 4 &&
    w.show.every((x: CapsuleComponent) => x.type === 'button'));
  const statementSteps = whens.filter((w: WhenComponent) => w.show.length === 1 && w.show[0].type === 'display');
  const quiz = new QuizPlan();
  if (buttonSteps.length >= 2) {
    quiz.steps = buttonSteps.map((w: WhenComponent) => new QuizStep(w, positionOf(w)));
  } else if (statementSteps.length >= 2) {
    const answerRow = capsule.ui.find((c: CapsuleComponent) => c.type === 'row' &&
      (c as RowComponent).items.length >= 2 && (c as RowComponent).items.length <= 4 &&
      (c as RowComponent).items.every((x: CapsuleComponent) => x.type === 'button'));
    if (answerRow === undefined) {
      return false;
    }
    quiz.buttonsInSteps = false;
    quiz.steps = statementSteps.map((w: WhenComponent) => new QuizStep(w, positionOf(w)));
    quiz.answers = (answerRow as RowComponent).items.map((x: CapsuleComponent) => x as ButtonComponent);
    plan.consumed.push(answerRow);
  } else {
    return false;
  }
  const displays = capsule.ui.filter((c: CapsuleComponent) => c.type === 'display').map((c: CapsuleComponent) =>
    c as DisplayComponent);
  quiz.question = quiz.buttonsInSteps ? displays.find((d: DisplayComponent) => !/score/i.test(d.text)) : undefined;
  quiz.score = displays.find((d: DisplayComponent) => /score|correct|right/i.test(d.text));
  quiz.next = topButtons(capsule.ui).find((b: ButtonComponent) => /^(next|skip)\b/i.test(b.label.trim()));
  plan.kind = 'quiz';
  plan.quiz = quiz;
  quiz.steps.forEach((s: QuizStep) => plan.consumed.push(s.when));
  [quiz.question, quiz.score].forEach((d: DisplayComponent | undefined) => {
    if (d !== undefined) {
      plan.consumed.push(d);
    }
  });
  if (quiz.next !== undefined) {
    plan.consumed.push(quiz.next);
  }
  return true;
}

function detectGroups(capsule: Capsule, plan: PatternPlan): boolean {
  const ui = capsule.ui;
  const groups: ChecklistGroup[] = [];
  ui.forEach((c: CapsuleComponent, i: number) => {
    if (c.type === 'checklist' && i > 0 && ui[i - 1].type === 'text') {
      groups.push(new ChecklistGroup(ui[i - 1] as TextComponent, c as ChecklistComponent));
    }
  });
  if (groups.length < 2) {
    return false;
  }
  plan.kind = 'grouped-checklist';
  plan.groups = groups;
  groups.forEach((g: ChecklistGroup) => {
    plan.consumed.push(g.title);
    plan.consumed.push(g.list);
  });
  return true;
}

/** The layout pattern for a capsule. Never throws; anything unexpected gives "generic". */
export function detectPattern(capsule: Capsule): PatternPlan {
  // Converter before form (every converter is also a form) and quiz before goal (a quiz score "{score} of 5" is
  // also a goal display): the more specific rule goes first.
  const rules: ((c: Capsule, p: PatternPlan) => boolean)[] = [detectRecords, detectVersus, detectConverter, detectForm,
    detectTimers, detectQuiz, detectGoal, detectGroups];
  for (const rule of rules) {
    try {
      const plan = new PatternPlan();
      if (rule(capsule, plan)) {
        return plan;
      }
    } catch (e) {
      // a malformed edge case: try the next rule, finally generic
    }
  }
  return new PatternPlan();
}

/** Rows wider than this many non-button children stack on phones. */
export const MAX_ROW_ACROSS: number = 2;

/** "3 of 8" in a display: [3, 8] for a progress bar, else null. */
export function countOf(text: string): number[] | null {
  const m = text.match(/\b(\d+)\s*(?:of|\/)\s*(\d+)\b/);
  if (m === null || Number(m[2]) <= 0) {
    return null;
  }
  return [Number(m[1]), Number(m[2])];
}
