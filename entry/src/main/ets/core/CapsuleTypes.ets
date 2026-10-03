// Types for Capsule schema v0 (see SCHEMA.md). Types only, no logic.

export type Permission = 'reminders' | 'notifications' | 'vibration' | 'motion' | 'location' | 'widget';

export type ComponentType = 'text' | 'timer' | 'counter' | 'checklist' | 'number' | 'button';

export type CounterSource = 'manual' | 'motion';

// One of: startTimer:<id> | startAllTimers | increment:<id> | reset:<id> | notify:<text>
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
  action: Action;
}

export type CapsuleComponent =
  TextComponent | TimerComponent | CounterComponent | ChecklistComponent | NumberComponent | ButtonComponent;

export interface Capsule {
  schemaVersion: number; // 0
  id: string;
  name: string;
  permissions: Permission[];
  ui: CapsuleComponent[];
}

// ---- Shared constants and result types used by the core (validator, parser, generator). ----

export const SCHEMA_VERSION: number = 0;

export const PERMISSIONS: string[] = ['reminders', 'notifications', 'vibration', 'motion', 'location', 'widget'];

export const COMPONENT_TYPES: string[] = ['text', 'timer', 'counter', 'checklist', 'number', 'button'];

export const COUNTER_SOURCES: string[] = ['manual', 'motion'];

export type ActionKind = 'startTimer' | 'startAllTimers' | 'increment' | 'reset' | 'notify';

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

export type CapsuleOrigin = 'rules' | 'model';

export interface GenerateResult {
  ok: boolean;
  capsule?: Capsule; // present only when ok; always validated
  origin?: CapsuleOrigin;
  error?: string; // one clear message when not ok
  details: string[]; // validator errors behind `error`, if any
}
