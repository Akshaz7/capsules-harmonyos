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
