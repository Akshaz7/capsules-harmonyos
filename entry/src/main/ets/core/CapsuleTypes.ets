// Types for Capsule schema v0 and v1 (see SCHEMA.md). Types only, no logic.

export type Permission = 'reminders' | 'notifications' | 'vibration' | 'motion' | 'location' | 'widget';

export type ComponentType = 'text' | 'timer' | 'counter' | 'checklist' | 'number' | 'button' |
  'display' | 'input' | 'list' | 'when' | 'row'; // last five: v1 only

export type CounterSource = 'manual' | 'motion';

// One of: startTimer:<id> | pauseTimer:<id> | stopTimer:<id> | resetTimer:<id> | startAllTimers | increment:<id>
// | reset:<id> | notify:<text>
export type Action = string;

export interface TextComponent {
  type: ComponentType; // 'text'
  text: string;
}

export interface TimerComponent {
  type: ComponentType; // 'timer'
  id: string;
  label: string;
  minutes: number;
}

export interface CounterComponent {
  type: ComponentType; // 'counter'
  id: string;
  label: string;
  source: CounterSource;
}

export interface ChecklistComponent {
  type: ComponentType; // 'checklist'
  id: string;
  items: string[];
}

export interface NumberComponent {
  type: ComponentType; // 'number'
  id: string;
  label: string;
}

export interface ButtonComponent {
  type: ComponentType; // 'button'
  label: string;
  // v0 action. In v1 the JSON may omit it when "do" is given; the validated capsule then has ''.
  action: Action;
  do?: ButtonStep[]; // v1: steps run in order, all-or-nothing
  enabledIf?: string; // v1: bool expression
}

// ---- v1 ----

export type VarType = 'number' | 'text' | 'bool' | 'list';

export type Scalar = number | string | boolean;

/** A state or computed value. Lists hold scalars only. */
export type Value = Scalar | Scalar[];

export interface StateVar {
  type: VarType;
  initial: Value;
}

/** One button step: {set,to} | {push,value} | {pop} | {reset}. A plain string step is a v0 action. */
export interface StepObject {
  set?: string;
  to?: string;
  push?: string;
  value?: string;
  pop?: string;
  reset?: string;
}

export type ButtonStep = string | StepObject;

export interface DisplayComponent {
  type: ComponentType; // 'display'
  text: string; // template: "{expr} ..."
}

export type InputKind = 'number' | 'text';

export interface InputComponent {
  type: ComponentType; // 'input'
  bind: string; // state var
  kind: InputKind;
  label: string;
}

export interface ListComponent {
  type: ComponentType; // 'list'
  source: string; // state var of type list
}

export interface WhenComponent {
  type: ComponentType; // 'when'
  if: string; // bool expression
  show: CapsuleComponent[];
}

export interface RowComponent {
  type: ComponentType; // 'row'
  items: CapsuleComponent[];
}

export type CapsuleComponent =
  TextComponent | TimerComponent | CounterComponent | ChecklistComponent | NumberComponent | ButtonComponent |
  DisplayComponent | InputComponent | ListComponent | WhenComponent | RowComponent;

export interface Capsule {
  schemaVersion: number; // 0 or 1
  id: string;
  name: string;
  permissions: Permission[];
  ui: CapsuleComponent[];
  state?: Record<string, StateVar>; // v1
  computed?: Record<string, string>; // v1: name -> expression
  triggers?: Trigger[]; // v1.1
}

/** v1.1: what starts a trigger. "time" = every day at `at` (HH:MM); "motion" = the user starts moving. */
export type TriggerKind = 'time' | 'motion';

export interface Trigger {
  on: TriggerKind;
  at?: string; // "HH:MM", only for "time"
  do: ButtonStep[]; // same steps as a v1 button
  label?: string;
}

export const TRIGGER_KINDS: string[] = ['time', 'motion'];
export const MAX_TRIGGERS: number = 5;
export const MAX_TRIGGER_LABEL: number = 60;

// ---- Shared constants and result types used by the core (validator, parser, generator). ----

export const SCHEMA_VERSION: number = 0;

export const PERMISSIONS: string[] = ['reminders', 'notifications', 'vibration', 'motion', 'location', 'widget'];

export const COMPONENT_TYPES: string[] = ['text', 'timer', 'counter', 'checklist', 'number', 'button'];

export const V1_COMPONENT_TYPES: string[] = ['display', 'input', 'list', 'when', 'row'];

export const MAX_SCHEMA_VERSION: number = 1;

export const COUNTER_SOURCES: string[] = ['manual', 'motion'];

export type ActionKind = 'startTimer' | 'pauseTimer' | 'stopTimer' | 'resetTimer' | 'startAllTimers' | 'increment' |
  'reset' | 'notify';

/** Actions that control one timer: their target must be a timer, and they need "reminders". */
export const TIMER_ACTIONS: string[] = ['startTimer', 'pauseTimer', 'stopTimer', 'resetTimer'];

// A parsed Action. `arg` is the target id (or the text for notify); empty for startAllTimers.
export interface ParsedAction {
  kind: ActionKind;
  arg: string;
}

export interface ValidationResult {
  ok: boolean;
  capsule?: Capsule; // present only when ok
  errors: string[]; // each prefixed with a JSON path, e.g. "$.ui[2].action: ..."; empty when ok
}

/** Cloud origins name the provider; "cloud-eu:" marks providers hosted in the EU. */
export type CloudOrigin = 'cloud-eu:mistral' | 'cloud:anthropic' | 'cloud:openai';

export type CapsuleOrigin = 'rules' | 'on-device' | CloudOrigin;

export interface GenerateResult {
  ok: boolean;
  capsule?: Capsule; // present only when ok; always validated
  origin?: CapsuleOrigin;
  error?: string; // one clear message when not ok
  details: string[]; // validator errors behind `error`, if any
  /**
   * True when the request needs the cloud (it implies logic the on-device templates cannot express) and
   * an EU provider is configured, but this call did not allow the cloud (options.allowCloud false). Ask the
   * user, then retry with the cloud allowed.
   */
  needsCloud?: boolean;
  /**
   * Why the model refused, when it did: "not-an-app" (nonsense such as "asdf") or "unsupported" (the
   * request needs capabilities capsules do not have; see `unsupported`). Do not retry these elsewhere.
   */
  failure?: FailureKind;
  /** With failure "unsupported": what is missing, e.g. ["contacts", "SMS"]. */
  unsupported?: string[];
}

export type FailureKind = 'not-an-app' | 'unsupported';
