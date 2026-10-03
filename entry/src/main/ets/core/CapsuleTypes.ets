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
