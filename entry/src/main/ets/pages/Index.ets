import { common } from '@kit.AbilityKit';
import { Capsule, Permission } from '../core';
import { TimerAdapter } from '../adapters/TimerAdapter';
import { Gatekeeper } from '../gatekeeper/Gatekeeper';
import { ActionGuard, CapsuleRuntime, TimerScheduler, TimerState } from '../renderer/CapsuleRuntime';
import { CapsuleView } from '../renderer/CapsuleView';
import { ConsentView } from './ConsentView';
import { LogView } from './LogView';

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

const LOG_PAGE = 'log';

type Phase = 'consent' | 'run' | 'removed';

class ReminderScheduler implements TimerScheduler {
  private adapter: TimerAdapter;

  constructor(adapter: TimerAdapter) {
    this.adapter = adapter;
  }

  scheduleTimer(capsuleId: string, t: TimerState): void {
    this.adapter.schedule(capsuleId, t.timerId, t.label, t.remainingSec);
  }
}

class GatekeeperGuard implements ActionGuard {
  private gate: Gatekeeper;
  private capsule: Capsule;

  constructor(gate: Gatekeeper, capsule: Capsule) {
    this.gate = gate;
    this.capsule = capsule;
  }

  allowAction(action: string): boolean {
    return this.gate.allowAction(this.capsule, action);
  }
}

@Entry
@ComponentV2
struct Index {
  private capsule: Capsule = JSON.parse(PASTA_NIGHT_JSON) as Capsule;
  private gate: Gatekeeper | undefined = undefined;
  private timers: TimerAdapter | undefined = undefined;
  @Local phase: Phase = 'consent';
  @Local runtime: CapsuleRuntime | undefined = undefined;
  @Local removedNote: string = '';
  @Local nav: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.gate = new Gatekeeper(ctx);
    this.timers = new TimerAdapter(ctx);
    if (this.gate.isRemoved(this.capsule.id)) {
      this.phase = 'removed';
    } else if (this.gate.hasDecided(this.capsule.id)) {
      this.startCapsule();
    }
  }

  aboutToDisappear(): void {
    this.runtime?.stop();
  }

  private startCapsule(): void {
    if (!this.gate || !this.timers) {
      return;
    }
    const rt = new CapsuleRuntime(this.capsule);
    rt.blockReasons = this.gate.checkComponents(this.capsule);
    rt.guard = new GatekeeperGuard(this.gate, this.capsule);
    if (this.gate.isAllowed(this.capsule, 'reminders')) {
      rt.scheduler = new ReminderScheduler(this.timers);
      this.timers.prepare();
    }
    this.runtime = rt;
    this.phase = 'run';
  }

  private decide(allowed: Permission[]): void {
    this.gate?.decide(this.capsule, allowed);
    this.startCapsule();
  }

  private async undo(): Promise<void> {
    if (!this.gate || !this.timers) {
      return;
    }
    this.runtime?.stop();
    const cancelled = await this.timers.cancelForCapsule(this.capsule.id);
    const note = `Removed ${this.capsule.name}; cancelled ${cancelled} calendar reminder(s)`;
    this.gate.forget(this.capsule.id, note);
    this.runtime = undefined;
    this.removedNote = note;
    this.phase = 'removed';
  }

  @Builder
  pageMap(name: string) {
    if (name === LOG_PAGE && this.gate) {
      LogView({ log: this.gate.log })
    }
  }

  @Builder
  runBar() {
    Row({ space: 8 }) {
      Button('Log')
        .layoutWeight(1)
        .onClick(() => this.nav.pushPath({ name: LOG_PAGE }))
      Button('Undo')
        .layoutWeight(1)
        .backgroundColor(Color.Red)
        .onClick(() => {
          this.undo();
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8 })
  }

  build() {
    Navigation(this.nav) {
      Scroll() {
        Column() {
          if (this.phase === 'consent') {
            ConsentView({
              capsule: this.capsule,
              onDecide: (allowed: Permission[]) => this.decide(allowed)
            })
          } else if (this.phase === 'run' && this.runtime) {
            this.runBar()
            CapsuleView({ runtime: this.runtime })
          } else {
            Column({ space: 12 }) {
              Text(this.removedNote.length > 0 ? this.removedNote : 'No capsule installed.')
                .fontSize(16)
                .width('100%')
              Button('Reinstall Pasta night (test)')
                .width('100%')
                .onClick(() => {
                  this.removedNote = '';
                  this.phase = 'consent';
                })
              Button('Log')
                .width('100%')
                .onClick(() => this.nav.pushPath({ name: LOG_PAGE }))
            }
            .padding(16)
          }
        }
        .width('100%')
      }
      .height('100%')
      .width('100%')
      .align(Alignment.Top)
    }
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .navDestination(this.pageMap)
  }
}
