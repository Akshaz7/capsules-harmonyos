import { common } from '@kit.AbilityKit';
import { Capsule, GenerateResult, Permission, generateCapsule, getModelStatus } from '../core';
import { NotificationAdapter } from '../adapters/NotificationAdapter';
import { TimerAdapter } from '../adapters/TimerAdapter';
import { Gatekeeper } from '../gatekeeper/Gatekeeper';
import {
  ActionGuard,
  CapsuleRuntime,
  TimerAlert,
  TimerScheduler,
  TimerState
} from '../renderer/CapsuleRuntime';
import { CapsuleView } from '../renderer/CapsuleView';
import { CapsuleStore } from './CapsuleStore';
import { ConsentView } from './ConsentView';
import { LogView } from './LogView';

const LOG_PAGE = 'log';

type Phase = 'create' | 'consent' | 'run';

class CalendarScheduler implements TimerScheduler {
  private adapter: TimerAdapter;

  constructor(adapter: TimerAdapter) {
    this.adapter = adapter;
  }

  scheduleTimer(capsuleId: string, t: TimerState): void {
    this.adapter.schedule(capsuleId, t.timerId, t.label, t.remainingSec);
  }
}

class NotifyOnFinish implements TimerAlert {
  private adapter: NotificationAdapter;
  private capsuleName: string;

  constructor(adapter: NotificationAdapter, capsuleName: string) {
    this.adapter = adapter;
    this.capsuleName = capsuleName;
  }

  timerFinished(capsuleId: string, t: TimerState): void {
    this.adapter.publish(`${t.label} is done`, this.capsuleName);
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
  private gate: Gatekeeper | undefined = undefined;
  private timers: TimerAdapter | undefined = undefined;
  private notifications: NotificationAdapter | undefined = undefined;
  private store: CapsuleStore | undefined = undefined;
  @Local phase: Phase = 'create';
  @Local capsule: Capsule | undefined = undefined;
  @Local runtime: CapsuleRuntime | undefined = undefined;
  @Local request: string = '';
  @Local busy: boolean = false;
  @Local message: string = '';
  @Local nav: NavPathStack = new NavPathStack();
  @Local modelStatus: string = getModelStatus().message;
  private statusPoll: number = -1;

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.gate = new Gatekeeper(ctx);
    this.timers = new TimerAdapter(ctx);
    this.notifications = new NotificationAdapter(ctx);
    this.store = new CapsuleStore(ctx);
    this.watchModelStatus();
    // Resume the saved capsule; ask again if its consent was never given.
    const saved = this.store.load();
    if (saved) {
      this.capsule = saved;
      if (this.gate.hasDecided(saved.id)) {
        this.startCapsule(saved);
      } else {
        this.phase = 'consent';
      }
    }
  }

  aboutToDisappear(): void {
    this.runtime?.stop();
    clearInterval(this.statusPoll);
  }

  // initCapsuleModel runs async in EntryAbility and may finish after the first render.
  private watchModelStatus(): void {
    let tries = 0;
    this.statusPoll = setInterval(() => {
      const status = getModelStatus();
      this.modelStatus = status.message;
      tries++;
      if (status.configured || tries >= 10) {
        clearInterval(this.statusPoll);
      }
    }, 500);
  }

  private async create(): Promise<void> {
    const text = this.request.trim();
    if (text.length === 0 || this.busy) {
      return;
    }
    this.busy = true;
    this.message = 'Creating…';
    const result: GenerateResult = await generateCapsule(text);
    this.busy = false;
    if (!result.ok || !result.capsule) {
      this.message = result.error ?? 'Could not create a capsule.';
      return;
    }
    // A new capsule always gets a fresh consent screen.
    this.capsule = result.capsule;
    this.store?.save(result.capsule);
    this.message = result.origin === 'model' ? 'Made by the AI fallback.' : 'Made on-device by the rule parser.';
    this.phase = 'consent';
  }

  private startCapsule(capsule: Capsule): void {
    if (!this.gate || !this.timers || !this.notifications) {
      return;
    }
    const rt = new CapsuleRuntime(capsule);
    rt.blockReasons = this.gate.checkComponents(capsule);
    rt.guard = new GatekeeperGuard(this.gate, capsule);
    if (this.gate.isAllowed(capsule, 'reminders')) {
      rt.scheduler = new CalendarScheduler(this.timers);
      rt.alert = new NotifyOnFinish(this.notifications, capsule.name);
      this.timers.prepare().then(() => this.notifications?.ensureEnabled());
    }
    this.runtime = rt;
    this.phase = 'run';
  }

  private decide(allowed: Permission[]): void {
    if (!this.capsule) {
      return;
    }
    this.gate?.decide(this.capsule, allowed);
    this.startCapsule(this.capsule);
  }

  private async undo(): Promise<void> {
    if (!this.gate || !this.timers || !this.capsule) {
      return;
    }
    const capsule = this.capsule;
    this.runtime?.stop();
    const cancelled = await this.timers.cancelForCapsule(capsule.id);
    const note = `Removed ${capsule.name}; cancelled ${cancelled} calendar reminder(s)`;
    this.gate.forget(capsule.id, note);
    this.store?.remove();
    this.runtime = undefined;
    this.capsule = undefined;
    this.message = note;
    this.phase = 'create';
  }

  @Builder
  pageMap(name: string) {
    if (name === LOG_PAGE && this.gate) {
      LogView({ log: this.gate.log })
    }
  }

  @Builder
  createScreen() {
    Column({ space: 12 }) {
      Text('Capsules')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .width('100%')
      TextArea({ placeholder: 'Describe a tiny app, e.g. "pasta 9 min, sauce 15 min, bread 6 min"', text: this.request })
        .height(120)
        .onChange((value: string) => {
          this.request = value;
        })
      Button(this.busy ? 'Creating…' : 'Create')
        .width('100%')
        .enabled(!this.busy && this.request.trim().length > 0)
        .onClick(() => {
          this.create();
        })
      if (this.message.length > 0) {
        Text(this.message).fontSize(15).width('100%')
      }
      Text(this.modelStatus)
        .fontSize(13)
        .fontColor(Color.Gray)
        .width('100%')
      Button('Log')
        .width('100%')
        .type(ButtonType.Normal)
        .borderRadius(20)
        .backgroundColor(Color.Gray)
        .onClick(() => this.nav.pushPath({ name: LOG_PAGE }))
    }
    .width('100%')
    .padding(16)
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
          if (this.phase === 'consent' && this.capsule) {
            if (this.message.length > 0) {
              Text(this.message)
                .fontSize(13)
                .fontColor(Color.Gray)
                .width('100%')
                .padding({ left: 16, right: 16, top: 8 })
            }
            ConsentView({
              capsule: this.capsule,
              onDecide: (allowed: Permission[]) => this.decide(allowed)
            })
          } else if (this.phase === 'run' && this.runtime) {
            this.runBar()
            CapsuleView({ runtime: this.runtime })
          } else {
            this.createScreen()
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
