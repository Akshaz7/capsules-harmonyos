import { common } from '@kit.AbilityKit';
import { curves } from '@kit.ArkUI';
import {
  Capsule,
  GenerateResult,
  Permission,
  generateCapsule,
  getModelStatus,
  getOnDeviceStatus,
  routeCapsule,
  BILL_SPLIT_CAPSULE,
  TENNIS_CAPSULE,
  validateCapsule
} from '../core';
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
import { AppSettings } from './AppSettings';
import { CapsuleEntry, capsuleIcon, originBadge, originIcon, routeHeadline } from './CapsuleEntry';
import { CapsuleStore } from './CapsuleStore';
import { ConsentView } from './ConsentView';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { refreshCapsuleWidgets } from '../widget/WidgetService';
import { loadState, saveState } from '../widget/WidgetStore';
import { LogView } from './LogView';
import { SettingsView } from './SettingsView';

const LOG_PAGE = 'log';
const SETTINGS_PAGE = 'settings';
const OPEN_CURVE: ICurve = curves.springMotion(0.45, 0.9);

interface ExampleChip {
  label: string;
  icon: Resource;
  request: string;
}

const EXAMPLES: ExampleChip[] = [
  { label: 'Timers', icon: $r('sys.symbol.timer'), request: '3 timers pasta 9 sauce 15 bread 6' },
  { label: 'Squats', icon: $r('sys.symbol.dumbbell'), request: 'count my squats' },
  { label: 'Water', icon: $r('sys.symbol.drop'), request: 'water 8 glasses' },
  { label: 'Checklist', icon: $r('sys.symbol.checkmark_circle'),
    request: 'checklist for leaving home: keys, wallet, charger' }
];

// Shown after a failed create. Each request is one the offline rules can build.
const RETRY_SUGGESTIONS: ExampleChip[] = [
  { label: 'Tennis points counter', icon: $r('sys.symbol.plus_circle'), request: 'count tennis points' },
  { label: 'Eggs timer 10 min', icon: $r('sys.symbol.timer'), request: 'timer eggs 10' },
  { label: 'Gym checklist', icon: $r('sys.symbol.checkmark_circle'),
    request: 'checklist for gym: towel, water, shoes' }
];
/** Hidden demo requests that load core's schema v1 fixtures (for testing and the demo video). */
function demoFixture(text: string): string | null {
  const t = text.toLowerCase();
  return t === 'demo tennis' ? TENNIS_CAPSULE : t === 'demo bill split' ? BILL_SPLIT_CAPSULE : null;
}

const CLOUD_NOTICE =
  'For advanced apps, Harmoniser sends only your request text to Mistral AI (EU). No personal data or app data.';
const FAILED_MESSAGE =
  "I couldn't build that offline. Try rephrasing, e.g. 'counter for tennis points' or 'timer 10 min'.";

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
  private ctx: common.UIAbilityContext | undefined = undefined;
  private statusPoll: number = -1;
  @Local entries: CapsuleEntry[] = [];
  @Local openId: string = '';
  @Local pending: Capsule | undefined = undefined;
  @Local pendingOrigin: string = '';
  private pendingOriginRaw: string = '';
  @Local settings: AppSettings = new AppSettings();
  @Local showSheet: boolean = false;
  @Local request: string = '';
  @Local busy: boolean = false;
  @Local message: string = '';
  @Local failed: boolean = false;
  @Local modelStatus: string = getModelStatus().message;
  @Local cloudConfigured: boolean = getModelStatus().configured;
  @Local onDeviceStatus: string = getOnDeviceStatus().message;
  @Local nav: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.ctx = ctx;
    this.gate = new Gatekeeper(ctx);
    this.timers = new TimerAdapter(ctx);
    this.notifications = new NotificationAdapter(ctx);
    this.store = new CapsuleStore(ctx);
    this.settings.load(ctx);
    this.watchModelStatus();
    // Saved capsules were approved before; ones whose consent was lost get dropped.
    const gate = this.gate;
    this.entries = this.store.all()
      .filter((c: Capsule) => gate.hasDecided(c.id))
      .map((c: Capsule) => this.makeEntry(c));
  }

  aboutToDisappear(): void {
    this.entries.forEach((e: CapsuleEntry) => e.runtime.stop());
    clearInterval(this.statusPoll);
  }

  // Core initialises the cloud config and the on-device model async; they may finish after the first render.
  private watchModelStatus(): void {
    let tries = 0;
    this.statusPoll = setInterval(() => {
      const status = getModelStatus();
      const onDevice = getOnDeviceStatus();
      this.modelStatus = status.message;
      this.cloudConfigured = status.configured;
      this.onDeviceStatus = onDevice.message;
      tries++;
      if ((status.configured && onDevice.ready) || tries >= 20) {
        clearInterval(this.statusPoll);
      }
    }, 500);
  }

  private openEntry(): CapsuleEntry | undefined {
    return this.entries.find((e: CapsuleEntry) => e.capsule.id === this.openId);
  }

  private makeEntry(capsule: Capsule): CapsuleEntry {
    const rt = new CapsuleRuntime(capsule);
    if (this.gate) {
      rt.blockReasons = this.gate.checkComponents(capsule);
      rt.guard = new GatekeeperGuard(this.gate, capsule);
      if (this.gate.isAllowed(capsule, 'reminders') && this.timers && this.notifications) {
        rt.scheduler = new CalendarScheduler(this.timers);
        rt.alert = new NotifyOnFinish(this.notifications, capsule.name);
      }
    }
    if (this.store && capsule.state !== undefined) {
      rt.restoreValues(this.store.values(capsule.id));
    }
    if (this.ctx) {
      // Shared with the home-screen widget: start from its saved state, write every change back.
      rt.applyState(loadState(this.ctx, capsule));
      rt.onChange = () => this.persist(rt);
    }
    return new CapsuleEntry(capsule, routeCapsule(capsule), rt, this.store?.origin(capsule.id) ?? '');
  }

  private persist(rt: CapsuleRuntime): void {
    if (!this.ctx) {
      return;
    }
    saveState(this.ctx, rt.exportState());
    if (rt.capsule.state !== undefined) {
      this.store?.setValues(rt.capsule.id, rt.values);
    }
    refreshCapsuleWidgets(this.ctx, rt.capsule.id);
  }

  // Widget taps change the shared state while the app is in the background; pick them up on return.
  onPageShow(): void {
    const ctx = this.ctx;
    if (!ctx) {
      return;
    }
    this.entries.forEach((e: CapsuleEntry) => e.runtime.applyState(loadState(ctx, e.capsule)));
    hilog.info(0x0001, 'Index', 'reloaded widget state for %{public}d capsules', this.entries.length);
  }

  /** Keeps ids unique across saved capsules so grants and calendar events never collide. */
  private uniqueCapsule(capsule: Capsule): Capsule {
    const taken = this.entries.map((e: CapsuleEntry) => e.capsule.id);
    let id = capsule.id;
    let n = 2;
    while (taken.includes(id)) {
      id = `${capsule.id}-${n++}`;
    }
    const copy: Capsule = {
      schemaVersion: capsule.schemaVersion,
      id: id,
      name: capsule.name,
      permissions: capsule.permissions,
      ui: capsule.ui,
      // v1: without these the copy's expressions would name values that don't exist.
      state: capsule.state,
      computed: capsule.computed
    };
    return copy;
  }

  private async create(): Promise<void> {
    const text = this.request.trim();
    if (text.length === 0 || this.busy) {
      return;
    }
    this.busy = true;
    this.message = '';
    this.failed = false;
    const fixture = demoFixture(text);
    if (fixture !== null) {
      const v = validateCapsule(fixture);
      this.busy = false;
      const demo: GenerateResult = { ok: v.ok, capsule: v.capsule, origin: 'rules', error: v.errors.join('; '),
        details: v.errors };
      this.finishCreate(text, demo);
      return;
    }
    const smart = this.settings.aiMode === 'smart';
    const result = await this.generate(text, smart && this.settings.cloudNoticeAccepted);
    this.busy = false;
    if (!result.ok && smart && !this.settings.cloudNoticeAccepted && getModelStatus().configured) {
      // The device couldn't build it and the cloud would be next: ask once before the first cloud request.
      hilog.info(0x0001, 'Index', 'on-device failed (%{public}s); showing the cloud notice', result.error ?? '');
      this.showCloudNotice(text);
      return;
    }
    this.finishCreate(text, result);
  }

  /** Rules, then the on-device model, then the cloud model only when `allowCloud`. Never throws. */
  private async generate(text: string, allowCloud: boolean): Promise<GenerateResult> {
    try {
      return await generateCapsule(text, { allowCloud: allowCloud });
    } catch (e) {
      const failed: GenerateResult = { ok: false, error: `generateCapsule threw: ${(e as Error).message}`, details: [] };
      return failed;
    }
  }

  /** One-time notice before the first cloud request. OK retries with the cloud; the other choice switches modes. */
  private showCloudNotice(text: string): void {
    this.getUIContext().showAlertDialog({
      title: 'Use Mistral AI (EU)?',
      message: CLOUD_NOTICE,
      autoCancel: false,
      // Stacked so "On-device only" is not cut off.
      buttonDirection: DialogButtonDirection.VERTICAL,
      buttons: [
        {
          value: 'OK',
          style: DialogButtonStyle.HIGHLIGHT,
          action: () => {
            this.settings.acceptCloudNotice();
            this.retryWithCloud(text);
          }
        },
        {
          value: 'On-device only',
          action: () => {
            this.settings.setAiMode('on-device');
            this.failed = true;
          }
        }
      ],
      cancel: () => {
        this.failed = true;
      }
    });
  }

  private async retryWithCloud(text: string): Promise<void> {
    this.busy = true;
    const result = await this.generate(text, true);
    this.busy = false;
    this.finishCreate(text, result);
  }

  private finishCreate(text: string, result: GenerateResult): void {
    if (!result.ok || !result.capsule) {
      // The user sees a friendly message; the real error only goes to the log.
      hilog.error(0x0001, 'Index', 'generateCapsule failed for "%{private}s": %{public}s [%{public}s]',
        text, result.error ?? 'no error', result.details.join('; '));
      this.failed = true;
      return;
    }
    this.pending = this.uniqueCapsule(result.capsule);
    this.pendingOriginRaw = result.origin ?? '';
    this.pendingOrigin = originBadge(this.pendingOriginRaw);
    this.showSheet = true;
  }

  private decide(allowed: Permission[]): void {
    const capsule = this.pending;
    if (!capsule || !this.gate) {
      return;
    }
    this.gate.decide(capsule, allowed);
    this.store?.setOrigin(capsule.id, this.pendingOriginRaw);
    this.store?.add(capsule);
    const entry = this.makeEntry(capsule);
    this.entries = [entry].concat(this.entries);
    if (this.gate.isAllowed(capsule, 'reminders')) {
      this.timers?.prepare().then(() => this.notifications?.ensureEnabled());
    }
    this.pending = undefined;
    this.showSheet = false;
    this.request = '';
    this.message = '';
    this.failed = false;
    if (this.ctx) {
      refreshCapsuleWidgets(this.ctx);
    }
    setTimeout(() => this.open(capsule.id), 300);
  }

  private cancelPending(): void {
    this.pending = undefined;
    this.showSheet = false;
  }

  private open(id: string): void {
    this.getUIContext().animateTo({ curve: OPEN_CURVE }, () => {
      this.openId = id;
    });
  }

  private close(): void {
    this.getUIContext().animateTo({ curve: OPEN_CURVE }, () => {
      this.openId = '';
    });
  }

  private async undo(entry: CapsuleEntry): Promise<void> {
    if (!this.gate || !this.timers) {
      return;
    }
    const capsule = entry.capsule;
    entry.runtime.stop();
    const cancelled = await this.timers.cancelForCapsule(capsule.id);
    const note = `Removed ${capsule.name}; cancelled ${cancelled} calendar reminder(s)`;
    this.gate.forget(capsule.id, note);
    this.store?.remove(capsule.id);
    this.close();
    if (this.ctx) {
      refreshCapsuleWidgets(this.ctx, capsule.id);
    }
    this.entries = this.entries.filter((e: CapsuleEntry) => e.capsule.id !== capsule.id);
    this.message = note;
  }

  /** Home status: on-device model state from core, then the cloud fallback state. */
  private statusLine(): string {
    if (this.settings.aiMode === 'on-device') {
      return `${this.onDeviceStatus} · On-device only`;
    }
    return `${this.onDeviceStatus} · ${this.cloudConfigured ? 'Mistral (EU) when needed' : this.modelStatus}`;
  }

  @Builder
  originPill(origin: string) {
    if (originBadge(origin).length > 0) {
      Row({ space: 4 }) {
        SymbolGlyph(originIcon(origin))
          .fontSize(12)
          .fontColor([$r('sys.color.icon_secondary')])
        Text(originBadge(origin))
          .fontSize($r('sys.float.Caption_S'))
          .fontColor($r('sys.color.font_secondary'))
      }
      .height(22)
      .padding({ left: 8, right: 8 })
      .borderRadius(11)
      .backgroundColor($r('sys.color.comp_background_tertiary'))
    }
  }

  @Builder
  pageMap(name: string) {
    if (name === LOG_PAGE && this.gate) {
      LogView({ log: this.gate.log })
    } else if (name === SETTINGS_PAGE) {
      SettingsView({ settings: this.settings, cloudStatus: this.cloudConfigured ? '' : this.modelStatus })
    }
  }

  @Builder
  iconButton(icon: Resource, action: () => void) {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([$r('sys.color.icon_primary')])
    }
    .width(40)
    .height(40)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .onClick(action)
  }

  @Builder
  sheetBody() {
    Column() {
      if (this.pending) {
        ConsentView({
          capsule: this.pending,
          origin: this.pendingOrigin,
          onDecide: (allowed: Permission[]) => this.decide(allowed),
          onCancel: () => this.cancelPending()
        })
      }
    }
    .width('100%')
  }

  @Builder
  inputCard() {
    Column({ space: 12 }) {
      TextArea({ placeholder: 'Describe a tiny app…', text: this.request })
        .height(96)
        .fontSize($r('sys.float.Body_L'))
        .backgroundColor(Color.Transparent)
        .padding({ left: 4, right: 4, top: 0, bottom: 0 })
        .onChange((value: string) => {
          this.request = value;
        })
      Row() {
        Text(this.statusLine())
          .fontSize($r('sys.float.Caption_M'))
          .fontColor($r('sys.color.font_tertiary'))
          .layoutWeight(1)
        Button() {
          Row({ space: 6 }) {
            if (this.busy) {
              LoadingProgress()
                .width(20)
                .height(20)
                .color($r('sys.color.font_on_primary'))
            }
            Text(this.busy ? 'Creating' : 'Create')
              .fontSize($r('sys.float.Body_M'))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_on_primary'))
          }
          .padding({ left: 18, right: 18 })
        }
        .height(40)
        .backgroundColor($r('sys.color.brand'))
        .enabled(!this.busy && this.request.trim().length > 0)
        .opacity(!this.busy && this.request.trim().length > 0 ? 1 : 0.4)
        .onClick(() => {
          this.create();
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .borderRadius(24)
    .backgroundColor($r('sys.color.comp_background_primary'))
  }

  @Builder
  chips() {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(EXAMPLES, (chip: ExampleChip) => {
        Row({ space: 6 }) {
          SymbolGlyph(chip.icon)
            .fontSize(16)
            .fontColor([$r('sys.color.icon_emphasize')])
          Text(chip.label)
            .fontSize($r('sys.float.Body_M'))
            .fontColor($r('sys.color.font_primary'))
        }
        .height(36)
        .padding({ left: 14, right: 14 })
        .margin({ right: 8, bottom: 8 })
        .borderRadius(18)
        .backgroundColor($r('sys.color.comp_background_primary'))
        .onClick(() => {
          this.request = chip.request;
        })
      }, (chip: ExampleChip) => chip.label)
    }
    .width('100%')
  }

  @Builder
  failedCard() {
    Column({ space: 12 }) {
      Text(FAILED_MESSAGE)
        .fontSize($r('sys.float.Body_M'))
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(RETRY_SUGGESTIONS, (chip: ExampleChip) => {
          Row({ space: 6 }) {
            SymbolGlyph(chip.icon)
              .fontSize(16)
              .fontColor([$r('sys.color.icon_emphasize')])
            Text(chip.label)
              .fontSize($r('sys.float.Body_M'))
              .fontColor($r('sys.color.font_primary'))
          }
          .height(36)
          .padding({ left: 14, right: 14 })
          .margin({ right: 8, bottom: 8 })
          .borderRadius(18)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .onClick(() => {
            this.request = chip.request;
            this.create();
          })
        }, (chip: ExampleChip) => chip.label)
      }
      .width('100%')
      if (this.settings.aiMode === 'on-device') {
        Row({ space: 4 }) {
          Text('or')
            .fontSize($r('sys.float.Body_M'))
            .fontColor($r('sys.color.font_secondary'))
          Text('switch AI mode to Smart in Settings')
            .fontSize($r('sys.float.Body_M'))
            .fontColor($r('sys.color.brand'))
            .fontWeight(FontWeight.Medium)
            .onClick(() => this.nav.pushPath({ name: SETTINGS_PAGE }))
        }
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(16)
    .borderRadius(20)
    .backgroundColor($r('sys.color.comp_background_primary'))
  }

  @Builder
  card(entry: CapsuleEntry) {
    Column({ space: 10 }) {
      Stack() {
        SymbolGlyph(capsuleIcon(entry.capsule))
          .fontSize(22)
          .fontColor([$r('sys.color.icon_emphasize')])
      }
      .width(44)
      .height(44)
      .borderRadius(22)
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      Text(entry.capsule.name)
        .fontSize($r('sys.float.Subtitle_M'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      this.originPill(entry.origin)
      Text(entry.runtime.summary())
        .fontSize($r('sys.float.Caption_L'))
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Blank()
      if (entry.route.widget) {
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.square_grid_2x2'))
            .fontSize(14)
            .fontColor([$r('sys.color.brand')])
          Text('Add to home screen')
            .fontSize($r('sys.float.Caption_M'))
            .fontColor($r('sys.color.brand'))
        }
      } else {
        Text('In app')
          .fontSize($r('sys.float.Caption_M'))
          .fontColor($r('sys.color.font_tertiary'))
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height(236)
    .padding(16)
    .borderRadius(24)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .geometryTransition(entry.capsule.id)
    .onClick(() => this.open(entry.capsule.id))
  }

  @Builder
  home() {
    Scroll() {
      Column({ space: 16 }) {
        Row() {
          Text('Harmoniser')
            .fontSize($r('sys.float.Subtitle_L'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_secondary'))
            .layoutWeight(1)
          Row({ space: 8 }) {
            this.iconButton($r('sys.symbol.gearshape'), () => this.nav.pushPath({ name: SETTINGS_PAGE }))
            this.iconButton($r('sys.symbol.doc_text'), () => this.nav.pushPath({ name: LOG_PAGE }))
          }
        }
        .width('100%')
        Text('What do you need?')
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
        this.inputCard()
        Text('Tiny apps, made by asking.')
          .fontSize($r('sys.float.Body_M'))
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .padding({ left: 4 })
        this.chips()
        if (this.failed) {
          this.failedCard()
        } else if (this.message.length > 0) {
          Text(this.message)
            .fontSize($r('sys.float.Body_M'))
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
        }
        Row() {
          Text('Your capsules')
            .fontSize($r('sys.float.Subtitle_L'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
          if (this.entries.length > 0) {
            Text(`${this.entries.length}`)
              .fontSize($r('sys.float.Body_M'))
              .fontColor($r('sys.color.font_tertiary'))
          }
        }
        .width('100%')
        .margin({ top: 8 })
        if (this.entries.length === 0) {
          Text('Capsules you create appear here.')
            .fontSize($r('sys.float.Body_M'))
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
            .padding({ top: 24, bottom: 24 })
            .textAlign(TextAlign.Center)
        } else {
          Grid() {
            ForEach(this.entries, (entry: CapsuleEntry) => {
              GridItem() {
                this.card(entry)
              }
            }, (entry: CapsuleEntry) => entry.capsule.id)
          }
          .columnsTemplate('1fr 1fr')
          .columnsGap(12)
          .rowsGap(12)
          .width('100%')
          .maxCount(2)
          .layoutDirection(GridDirection.Row)
        }
      }
      .padding({ left: 16, right: 16, top: 8, bottom: 32 })
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .edgeEffect(EdgeEffect.Spring)
    .scrollBar(BarState.Off)
    .transition(TransitionEffect.OPACITY)
  }

  @Builder
  routeCard(entry: CapsuleEntry) {
    if (entry.route.widget) {
      Column({ space: 10 }) {
        Row({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.square_grid_2x2'))
            .fontSize(22)
            .fontColor([$r('sys.color.brand')])
          Text('Add to home screen')
            .fontSize($r('sys.float.Subtitle_M'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
        }
        Text('1. Long-press the Harmoniser app icon on your home screen.\n' +
          '2. Pick the Harmoniser widget.\n' +
          '3. Tap "Add to home screen".')
          .fontSize($r('sys.float.Body_M'))
          .fontColor($r('sys.color.font_secondary'))
          .lineHeight(22)
        Text(`${routeHeadline(entry.route)} · ${entry.route.reason}`)
          .fontSize($r('sys.float.Caption_M'))
          .fontColor($r('sys.color.font_tertiary'))
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(16)
      .borderRadius(20)
      .backgroundColor($r('sys.color.comp_background_primary'))
      .border({ width: 1, color: $r('sys.color.brand'), style: BorderStyle.Dashed })
    } else {
      Text(`${routeHeadline(entry.route)} · ${entry.route.reason}`)
        .fontSize($r('sys.float.Caption_M'))
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
        .padding({ left: 4, right: 4 })
    }
  }

  @Builder
  detail(entry: CapsuleEntry) {
    Column() {
      Row({ space: 12 }) {
        this.iconButton($r('sys.symbol.chevron_left'), () => this.close())
        Text(entry.capsule.name)
          .fontSize($r('sys.float.Title_S'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        this.iconButton($r('sys.symbol.doc_text'), () => this.nav.pushPath({ name: LOG_PAGE }))
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })

      Scroll() {
        Column({ space: 16 }) {
          this.originPill(entry.origin)
          CapsuleView({ runtime: entry.runtime })
          this.routeCard(entry)
          Button() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.trash'))
                .fontSize(18)
                .fontColor([$r('sys.color.warning')])
              Text('Remove capsule')
                .fontSize($r('sys.float.Body_L'))
                .fontColor($r('sys.color.warning'))
            }
          }
          .width('100%')
          .height(48)
          .margin({ top: 8 })
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .onClick(() => {
            this.undo(entry);
          })
          Text('Removes the capsule, its permissions and its calendar events.')
            .fontSize($r('sys.float.Caption_M'))
            .fontColor($r('sys.color.font_tertiary'))
        }
        .padding({ left: 16, right: 16, top: 8, bottom: 32 })
        .width('100%')
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_secondary'))
    .geometryTransition(entry.capsule.id)
    .transition(TransitionEffect.OPACITY)
  }

  build() {
    Navigation(this.nav) {
      Stack() {
        if (this.openEntry()) {
          this.detail(this.openEntry() as CapsuleEntry)
        } else {
          this.home()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('sys.color.background_secondary'))
      .bindSheet(this.showSheet, this.sheetBody(), {
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        backgroundColor: $r('sys.color.background_secondary'),
        onDisappear: () => {
          if (this.pending) {
            this.cancelPending();
          }
        }
      })
    }
    .hideTitleBar(true)
    .backgroundColor($r('sys.color.background_secondary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .mode(NavigationMode.Stack)
    .navDestination(this.pageMap)
  }
}
