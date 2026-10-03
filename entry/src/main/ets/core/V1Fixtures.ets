/**
 * Example schema v1 capsules (JSON text), used by unit tests and available to the app as
 * demo fixtures. Both pass validateCapsule.
 */

/** Tennis scoreboard: 0/15/30/40, deuce, advantage and games. */
export const TENNIS_CAPSULE: string = `{
  "schemaVersion": 1, "id": "tennis", "name": "Tennis scoreboard", "permissions": [],
  "state": {
    "p1": { "type": "number", "initial": 0 }, "p2": { "type": "number", "initial": 0 },
    "g1": { "type": "number", "initial": 0 }, "g2": { "type": "number", "initial": 0 }
  },
  "computed": {
    "deuce": "p1 >= 3 and p1 == p2",
    "adv1": "p1 >= 3 and p2 >= 3 and p1 == p2 + 1",
    "adv2": "p1 >= 3 and p2 >= 3 and p2 == p1 + 1",
    "call1": "if(p1 >= 3 and p2 >= 3, if(adv1, 'AD', '40'), if(p1 == 0, '0', if(p1 == 1, '15', if(p1 == 2, '30', '40'))))",
    "call2": "if(p1 >= 3 and p2 >= 3, if(adv2, 'AD', '40'), if(p2 == 0, '0', if(p2 == 1, '15', if(p2 == 2, '30', '40'))))",
    "status": "if(deuce, 'Deuce', if(adv1, 'Advantage P1', if(adv2, 'Advantage P2', call1 + ' - ' + call2)))"
  },
  "ui": [
    { "type": "display", "text": "Games {g1} - {g2}" },
    { "type": "display", "text": "{status}" },
    { "type": "row", "items": [
      { "type": "button", "label": "Point P1", "do": [
        { "set": "g1", "to": "if(p1 >= 3 and p1 > p2, g1 + 1, g1)" },
        { "set": "p2", "to": "if(p1 >= 3 and p1 > p2, 0, p2)" },
        { "set": "p1", "to": "if(p1 >= 3 and p1 > p2, 0, p1 + 1)" } ] },
      { "type": "button", "label": "Point P2", "do": [
        { "set": "g2", "to": "if(p2 >= 3 and p2 > p1, g2 + 1, g2)" },
        { "set": "p1", "to": "if(p2 >= 3 and p2 > p1, 0, p1)" },
        { "set": "p2", "to": "if(p2 >= 3 and p2 > p1, 0, p2 + 1)" } ] }
    ] },
    { "type": "when", "if": "g1 + g2 > 0", "show": [
      { "type": "display", "text": "{if(g1 > g2, 'P1 leads', if(g2 > g1, 'P2 leads', 'Level'))}" } ] },
    { "type": "button", "label": "Reset match", "enabledIf": "p1 + p2 + g1 + g2 > 0",
      "do": [ { "reset": "p1" }, { "reset": "p2" }, { "reset": "g1" }, { "reset": "g2" } ] }
  ]
}`;

/** Live bill split: total, people and tip percent inputs; the share updates as you type. */
export const BILL_SPLIT_CAPSULE: string = `{
  "schemaVersion": 1, "id": "bill", "name": "Bill split", "permissions": [],
  "state": {
    "total": { "type": "number", "initial": 0 },
    "people": { "type": "number", "initial": 2 },
    "tip": { "type": "number", "initial": 0 }
  },
  "computed": { "each": "if(people > 0, round(total * (1 + tip / 100) / people, 2), 0)" },
  "ui": [
    { "type": "input", "bind": "total", "kind": "number", "label": "Total" },
    { "type": "input", "bind": "people", "kind": "number", "label": "People" },
    { "type": "input", "bind": "tip", "kind": "number", "label": "Tip %" },
    { "type": "display", "text": "Each pays {each}" },
    { "type": "when", "if": "people <= 0", "show": [ { "type": "text", "text": "Add at least one person." } ] }
  ]
}`;
