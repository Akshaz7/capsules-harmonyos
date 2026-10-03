import { common } from '@kit.AbilityKit';
import { Capsule } from '../core/CapsuleTypes';
import { TimerAdapter } from '../adapters/TimerAdapter';
import { CapsuleRuntime, TimerScheduler, TimerState } from '../renderer/CapsuleRuntime';
import { CapsuleView } from '../renderer/CapsuleView';

// Hard-coded test capsule until the core parser/validator is wired in.
// TEMP: the 1-minute "Test" timer is for checking that reminders fire with the app closed.
const PASTA_NIGHT_JSON: string = `{
  "schemaVersion": 0,
  "id": "pasta-night",
  "name": "Pasta night",
  "permissions": ["reminders"],
  "ui": [
    { "type": "timer", "id": "pasta", "label": "Pasta", "minutes": 9 },
    { "type": "timer", "id": "sauce", "label": "Sauce", "minutes": 15 },
    { "type": "timer", "id": "bread", "label": "Bread", "minutes": 6 },
    { "type": "timer", "id": "test", "label": "Test", "minutes": 1 },
    { "type": "button", "label": "Start all", "action": "startAllTimers" }
  ]
}`;

class ReminderScheduler implements TimerScheduler {
  private adapter: TimerAdapter;

  constructor(adapter: TimerAdapter) {
    this.adapter = adapter;
  }

  scheduleTimer(capsuleId: string, t: TimerState): void {
    this.adapter.schedule(capsuleId, t.timerId, t.label, t.remainingSec);
  }
}

@Entry
@ComponentV2
struct Index {
  @Local runtime: CapsuleRuntime = new CapsuleRuntime(JSON.parse(PASTA_NIGHT_JSON) as Capsule);

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const adapter = new TimerAdapter(ctx);
    this.runtime.scheduler = new ReminderScheduler(adapter);
    adapter.prepare();
  }

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
