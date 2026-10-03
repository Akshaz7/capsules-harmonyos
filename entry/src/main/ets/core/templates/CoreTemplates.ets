/**
 * Hand-written templates that are always available, even if rawfile/templates/library.json cannot be read.
 * The seed script (scripts/seed-capsules) copies them into library.json and the marketplace seed.
 * Placeholders "@{slot}": see TemplateLibrary.ets.
 */
import { TemplateEntry, TemplateSlot } from './TemplateLibrary';

const TENNIS: string = `{
  "schemaVersion": 1, "id": "tennis", "name": "Tennis: @{player1} vs @{player2}", "permissions": [],
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
    "status": "if(deuce, 'Deuce', if(adv1, 'Advantage @{player1}', if(adv2, 'Advantage @{player2}', call1 + ' - ' + call2)))"
  },
  "ui": [
    { "type": "display", "text": "Games: @{player1} {g1} - {g2} @{player2}" },
    { "type": "display", "text": "{status}" },
    { "type": "row", "items": [
      { "type": "button", "label": "Point @{player1}", "do": [
        { "set": "g1", "to": "if(p1 >= 3 and p1 > p2, g1 + 1, g1)" },
        { "set": "p2", "to": "if(p1 >= 3 and p1 > p2, 0, p2)" },
        { "set": "p1", "to": "if(p1 >= 3 and p1 > p2, 0, p1 + 1)" } ] },
      { "type": "button", "label": "Point @{player2}", "do": [
        { "set": "g2", "to": "if(p2 >= 3 and p2 > p1, g2 + 1, g2)" },
        { "set": "p1", "to": "if(p2 >= 3 and p2 > p1, 0, p1)" },
        { "set": "p2", "to": "if(p2 >= 3 and p2 > p1, 0, p2 + 1)" } ] }
    ] },
    { "type": "when", "if": "g1 + g2 > 0", "show": [
      { "type": "display", "text": "{if(g1 > g2, '@{player1} leads', if(g2 > g1, '@{player2} leads', 'Level'))}" } ] },
    { "type": "button", "label": "Reset match", "enabledIf": "p1 + p2 + g1 + g2 > 0",
      "do": [ { "reset": "p1" }, { "reset": "p2" }, { "reset": "g1" }, { "reset": "g2" } ] }
  ]
}`;

const POMODORO: string = `{
  "schemaVersion": 1, "id": "pomodoro", "name": "Pomodoro @{work}/@{rest}", "permissions": ["reminders"],
  "ui": [
    { "type": "timer", "id": "focus", "label": "Focus", "minutes": "@{work}" },
    { "type": "timer", "id": "rest", "label": "Break", "minutes": "@{rest}" },
    { "type": "row", "items": [
      { "type": "button", "label": "Start focus", "do": ["stopTimer:rest", "startTimer:focus"] },
      { "type": "button", "label": "Start break", "do": ["stopTimer:focus", "startTimer:rest", "increment:rounds"] }
    ] },
    { "type": "row", "items": [
      { "type": "button", "label": "Pause", "do": ["pauseTimer:focus", "pauseTimer:rest"] },
      { "type": "button", "label": "Stop", "do": ["stopTimer:focus", "stopTimer:rest"] }
    ] },
    { "type": "counter", "id": "rounds", "label": "Rounds done", "source": "manual" }
  ]
}`;

const PUSHUPS: string = `{
  "schemaVersion": 1, "id": "pushups", "name": "Push-up counter", "permissions": [],
  "state": { "n": { "type": "number", "initial": 0 }, "goal": { "type": "number", "initial": "@{goal}" } },
  "ui": [
    { "type": "display", "text": "{n} / {goal} push-ups" },
    { "type": "row", "items": [
      { "type": "button", "label": "+1", "do": [ { "set": "n", "to": "n + 1" } ] },
      { "type": "button", "label": "+5", "do": [ { "set": "n", "to": "n + 5" } ] },
      { "type": "button", "label": "+10", "do": [ { "set": "n", "to": "n + 10" } ] }
    ] },
    { "type": "when", "if": "n >= goal", "show": [ { "type": "text", "text": "Goal reached!" } ] },
    { "type": "button", "label": "Reset", "enabledIf": "n > 0", "do": [ { "reset": "n" } ] }
  ]
}`;

function entry(id: string, name: string, description: string, category: string, tags: string[], slots: string,
  capsule: string): TemplateEntry {
  return {
    id: id, name: name, description: description, category: category, language: 'en', tags: tags,
    slots: JSON.parse(slots) as TemplateSlot[], capsule: JSON.parse(capsule) as Object
  };
}

export const CORE_TEMPLATES: TemplateEntry[] = [
  entry('tennis', 'Tennis scoreboard', 'Tennis points 0, 15, 30, 40, deuce, advantage and games for two players.',
    'games', ['tennis', 'tenis', 'tennis score', 'tennis scoreboard', 'scoreboard', 'score', 'scorer', 'points',
      'match', 'deuce', 'wynik', 'wyniki', 'punkty', 'mecz', 'tablica wynikow', 'licznik punktow', '网球', '记分'],
    '[{"name":"player1","kind":"text","default":"Player 1"},{"name":"player2","kind":"text","default":"Player 2"}]',
    TENNIS),
  entry('pomodoro', 'Pomodoro timer', 'Focus and break timers; starting one stops the other, with a round counter.',
    'study', ['pomodoro', 'focus', 'focus timer', 'study timer', 'work timer', 'deep work', 'productivity',
      'tomato', 'pomidor', 'pomodoro timer', 'skupienie', 'nauka', 'praca', 'przerwa', 'minutnik', '番茄钟', '专注'],
    '[{"name":"work","kind":"number","default":25,"hints":["work","focus","praca","nauka","skupienie"]},' +
      '{"name":"rest","kind":"number","default":5,"hints":["break","rest","pause","przerwa","odpoczynek"]}]',
    POMODORO),
  entry('pushups', 'Push-up counter', 'Count push-ups with +1, +5 and +10 buttons towards a daily goal.',
    'fitness', ['push-ups', 'push ups', 'pushups', 'push-up counter', 'press-ups', 'pompki', 'pompek', 'pompka',
      'licznik pompek', 'licznik', 'counter', 'reps', 'powtorzenia', '俯卧撑'],
    '[{"name":"goal","kind":"number","default":50,"hints":["goal","target","cel"]}]',
    PUSHUPS)
];
