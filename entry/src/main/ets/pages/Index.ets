import { Capsule } from '../core/CapsuleTypes';
import { CapsuleRuntime } from '../renderer/CapsuleRuntime';
import { CapsuleView } from '../renderer/CapsuleView';

// Hard-coded test capsule until the core parser/validator is wired in.
const PASTA_NIGHT_JSON: string = `{
  "schemaVersion": 0,
  "id": "pasta-night",
  "name": "Pasta night",
  "permissions": ["reminders"],
  "ui": [
    { "type": "timer", "id": "pasta", "label": "Pasta", "minutes": 9 },
    { "type": "timer", "id": "sauce", "label": "Sauce", "minutes": 15 },
    { "type": "timer", "id": "bread", "label": "Bread", "minutes": 6 },
    { "type": "button", "label": "Start all", "action": "startAllTimers" }
  ]
}`;

@Entry
@ComponentV2
struct Index {
  @Local runtime: CapsuleRuntime = new CapsuleRuntime(JSON.parse(PASTA_NIGHT_JSON) as Capsule);

  aboutToDisappear(): void {
    this.runtime.stop();
  }

  build() {
    Scroll() {
      CapsuleView({ runtime: this.runtime })
    }
    .height('100%')
    .width('100%')
    .align(Alignment.Top)
  }
}
