# Capsule schema v0
A capsule is JSON. No code. Unknown fields or types = reject.

{ "schemaVersion": 0, "id": string, "name": string,
  "permissions": [ "reminders" | "notifications" | "vibration" | "motion" | "location" | "widget" ],
  "ui": [ component ] }

component types:
- text      { type, text }
- timer     { type, id, label, minutes }                    needs: reminders
- counter   { type, id, label, source: "manual" | "motion" }  motion needs: motion
- checklist { type, id, items: [string] }
- number    { type, id, label }
- button    { type, label, action }

actions: startTimer:<id> | startAllTimers | increment:<id> | reset:<id> | notify:<text>
Rule: any component or action that needs a permission not listed in "permissions" is blocked and logged by the gatekeeper.

# Capsule schema v1 (approved by Ash, 2026-10-03)
Backwards compatible: every v0 capsule stays valid. v1 features are allowed only with "schemaVersion": 1.
Still JSON, still no code: expressions are parsed by our own parser (never eval). Unknown fields or types = reject.

{ "schemaVersion": 1, "id", "name", "permissions", "ui": [ component ],
  "state":    { name: { "type": "number" | "text" | "bool" | "list", "initial": value } },   optional, max 30
  "computed": { name: expression } }                                                         optional, max 30

Names: letters, digits, _; start with a letter or _; max 32 chars; unique across state and computed;
not a keyword (true false and or not if min max round abs len).
Initial values: number (finite), text (max 500 chars), bool, list = array of number|text|bool (max 100 items).
Computed values are derived from state and other computed values; no cycles.

Expressions (max 200 chars, max nesting depth 10, evaluation step budget):
- literals: 12, 3.5, 'text' or "text", true, false; names of state and computed values
- arithmetic: + - * / %   (number + number; text + anything = concatenation)
- comparison: == != (same type), < <= > >= (numbers)
- logic: and, or, not (bool)
- functions: if(cond, a, b), min(a, b, ...), max(a, b, ...), round(x) or round(x, digits 0-6), abs(x), len(list or text)
- Types are checked when the capsule is validated. Division or % by zero, non-finite results, text over
  500 chars or lists over 100 items are runtime errors: the step fails and nothing changes.

New components (v1):
- display { type, text }                 text is a template: "{p1} - {p2}"; each {expr} is an expression; "{{" and "}}" are literal braces
- input   { type, bind, kind: "number" | "text", label }   bind = a state var of the same type
- list    { type, source }               source = a state var of type list
- when    { type, if: expression, show: [component] }      if must be bool
- row     { type, items: [component] }

Button (v1): { type, label, action?, do?, enabledIf? }   at least one of action / do
- do: [step], max 20 steps, run in order; each step sees the state left by the previous step:
    { "set": var, "to": expression }      var = a state var (not computed); type must match
    { "push": listVar, "value": expression }   value is number | text | bool
    { "pop": listVar }                    removes the last item (no-op on an empty list)
    { "reset": var }                      back to its initial value
    "startTimer:<id>" | "startAllTimers" | "increment:<id>" | "reset:<id>" | "notify:<text>"   (v0 actions, same permissions)
  A button press is all-or-nothing: if any step fails, no state changes.
- enabledIf: bool expression; the button is disabled while it is false.

Limits: max 60 components in total, counting components nested in when/row (max nesting 5).
The validator checks every expression against the grammar, that every name exists, and that types fit.
