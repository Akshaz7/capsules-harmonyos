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
import { CapsuleEntry, capsuleIcon, isCloudOrigin, originBadge, originIcon, routeHeadline } from './CapsuleEntry';
import { CapsuleStore } from './CapsuleStore';
import { ConsentView } from './ConsentView';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  assignCapsuleToWidget, firstBlankWidget, listWidgets, refreshCapsuleWidgets, WidgetInfo
} from '../widget/WidgetService';
import { WidgetCapsulePicker } from './WidgetCapsulePicker';
import { WidgetLaunch, widgetLaunch } from './WidgetLaunch';
import { ShareLaunch, shareLaunch } from './ShareLaunch';
import { failureDetail, joinWords, refusalWords } from './CreateText';
import { loadState, saveState } from '../widget/WidgetStore';
import { LogView } from './LogView';
import { SettingsView } from './SettingsView';
import { PreparedImport, SharingBar } from '../sharing';

const LOG_PAGE = 'log';
const SETTINGS_PAGE = 'settings';
const CHOOSE_PAGE = 'chooseCapsule';
// Stored as a capsule origin so the sheet and the card badge say where it came from.
const IMPORTED_ORIGIN = 'imported';
const OPEN_CURVE: ICurve = curves.springMotion(0.45, 0.9);

interface ExampleChip {
  label: string;
  icon: Resource;
  request: string;
}

// The input's placeholder cycles through these so the app reads as open-ended, not a list of presets.
const PLACEHOLDERS: string[] = [
  'Try: tennis scoreboard me vs Sam',
  'Try: km to miles converter',
  'Try: split dinner 120 between 4',
  'Try: quiz me on 3 capitals',
  'Try: habit streak for reading',
  'Try: pasta 9 min, sauce 15 min'
];
const PLACEHOLDER_MS = 3000;

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

interface CloudNotice {
  title: string;
  message: string;
}

/** The one-time notice names the provider that will actually get the request, and says if it is outside the EU. */
function cloudNotice(provider: string): CloudNotice {
  if (provider === 'mistral') {
    return { title: 'Use Mistral AI (EU)?', message:
      'For advanced apps, Harmoniser sends only your request text to Mistral AI (EU). No personal data or app data.' };
  }
  const who = provider === 'anthropic' ? 'Claude by Anthropic' : provider === 'openai' ? 'OpenAI' : 'a cloud AI provider';
  const name = provider === 'anthropic' ? 'Claude' : provider === 'openai' ? 'OpenAI' : 'cloud AI';
  return { title: `Use ${name} (outside the EU)?`, message:
    `For advanced apps, Harmoniser sends only your request text to ${who}, which is outside the EU. ` +
      'No personal data or app data.' };
}
/** What capsules can do, for the "can't do that by design" card. */
const CAPSULE_ABILITIES = 'timers, counters, checklists, calculations, inputs and lists, reminders, ' +
  'notifications, vibration and the motion sensor';

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

  /** Paused, stopped or reset: its calendar reminder must not ring. */
  cancelTimer = (capsuleId: string, t: TimerState): void => {
    this.adapter.cancelTimer(capsuleId, t.timerId);
  };
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
  private placeholderTimer: number = -1;
  @Local placeholderIndex: number = 0;
  @Local entries: CapsuleEntry[] = [];
  @Local openId: string = '';
  @Local pending: Capsule | undefined = undefined;
  @Local pendingOrigin: string = '';
  private pendingOriginRaw: string = '';
  /** The request text behind `pending`; '' for imports. */
  private pendingRequest: string = '';
  /** Capsule that `pending` will replace when the user runs it ("Make it smarter"); '' otherwise. */
  private replacingId: string = '';
  /** Capsule being rebuilt with the cloud right now; '' when idle. */
  @Local smarterBusyId: string = '';
  /** Capsules whose "Add to home screen" how-to is expanded. Open on first view, collapsed after. */
  @Local hintOpenIds: string[] = [];
  /** Placed Harmoniser widgets, in the order they were added. */
  @Local widgets: WidgetInfo[] = [];
  /** Set by EntryAbility when a blank widget asks the user to choose a capsule. */
  @Local launch: WidgetLaunch = widgetLaunch();
  /** Set by EntryAbility when text, a link or an image is shared to Harmoniser. */
  @Local share: ShareLaunch = shareLaunch();
  private handledShare: number = 0;
  @Local settings: AppSettings = new AppSettings();
  @Local showSheet: boolean = false;
  @Local request: string = '';
  @Local busy: boolean = false;
  @Local message: string = '';
  @Local failed: boolean = false;
  /** When core refused a request by design: what it would need, e.g. ["contacts", "SMS"]. Else empty. */
  @Local unsupported: string[] = [];
  @Local modelStatus: string = getModelStatus().message;
  @Local cloudConfigured: boolean = getModelStatus().configured;
  @Local euCloud: boolean = getModelStatus().euAvailable;
  @Local cloudProviders: string[] = getModelStatus().providers;
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
    this.placeholderTimer = setInterval(() => {
      this.placeholderIndex = (this.placeholderIndex + 1) % PLACEHOLDERS.length;
    }, PLACEHOLDER_MS);
    // Saved capsules were approved before; ones whose consent was lost get dropped.
    const gate = this.gate;
    this.entries = this.store.all()
      .filter((c: Capsule) => gate.hasDecided(c.id))
      .map((c: Capsule) => this.makeEntry(c));
    this.loadWidgets();
    if (this.launch.formId.length > 0) {
      // Cold start from a blank widget: open the picker once the Navigation is up.
      setTimeout(() => this.openCapsulePicker(), 0);
    }
    if (this.share.seq > 0) {
      setTimeout(() => this.onShared(), 0); // cold start from the share sheet
    }
  }

  /** Shared text or a link becomes the request and goes through the normal create + consent flow. */
  @Monitor('share.seq')
  onShared(): void {
    if (this.share.seq === this.handledShare) {
      return;
    }
    this.handledShare = this.share.seq;
    this.close();
    this.nav.clear();
    if (this.share.text.length > 0) {
      this.request = this.share.text;
      this.create();
    } else if (this.share.imageUri.length > 0) {
      // TODO(T3-2): send the image to generateCapsuleFromImage once core exports it (T5-3).
      this.toast("Harmoniser can't build from photos yet. Describe it in words instead.");
    }
  }

  @Monitor('launch.formId')
  onWidgetLaunch(): void {
    if (this.launch.formId.length > 0) {
      this.openCapsulePicker();
    }
  }

  private openCapsulePicker(): void {
    this.close();
    this.nav.clear();
    this.nav.pushPath({ name: CHOOSE_PAGE });
  }

  private loadWidgets(): void {
    if (this.ctx) {
      this.widgets = listWidgets(this.ctx);
    }
  }

  private widgetLabel(w: WidgetInfo, index: number): string {
    const entry = this.entries.find((e: CapsuleEntry) => e.capsule.id === w.capsuleId);
    return `Widget ${index + 1}: ${entry ? entry.capsule.name : 'empty'}`;
  }

  /** From the picker a blank widget opened: show the chosen capsule on that widget. */
  private async pickForWidget(capsuleId: string): Promise<void> {
    const formId = this.launch.formId;
    if (!this.ctx || formId.length === 0) {
      return;
    }
    const ok = await assignCapsuleToWidget(this.ctx, formId, capsuleId);
    const name = this.entries.find((e: CapsuleEntry) => e.capsule.id === capsuleId)?.capsule.name ?? 'It';
    this.toast(ok ? `${name} is now on your home screen` : "That widget isn't available any more");
    this.launch.formId = '';
    this.loadWidgets();
    this.nav.pop();
  }

  /** "Show on home screen widget": fill a blank widget, else ask which widget to replace. */
  private showOnWidget(entry: CapsuleEntry): void {
    const ctx = this.ctx;
    if (!ctx) {
      return;
    }
    this.loadWidgets();
    const index = this.widgets.findIndex((w: WidgetInfo) => w.capsuleId === entry.capsule.id);
    if (index >= 0) {
      this.toast(`Already on your home screen (Widget ${index + 1})`);
      return;
    }
    const blank = firstBlankWidget(ctx);
    if (blank !== null) {
      this.putOnWidget(entry, blank.formId);
      return;
    }
    this.getUIContext().showActionSheet({
      title: 'Replace which widget?',
      message: 'All your Harmoniser widgets are in use.',
      autoCancel: true,
      sheets: this.widgets.map((w: WidgetInfo, i: number): SheetInfo => {
        const sheet: SheetInfo = { title: this.widgetLabel(w, i), action: () => this.putOnWidget(entry, w.formId) };
        return sheet;
      })
    });
  }

  private async putOnWidget(entry: CapsuleEntry, formId: string): Promise<void> {
    if (!this.ctx) {
      return;
    }
    const ok = await assignCapsuleToWidget(this.ctx, formId, entry.capsule.id);
    this.loadWidgets();
    const index = this.widgets.findIndex((w: WidgetInfo) => w.formId === formId);
    this.toast(ok ? `Showing ${entry.capsule.name} on Widget ${index + 1}` : "Couldn't show it on that widget");
  }

  private toast(text: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: text });
    } catch (e) {
      hilog.warn(0x0001, 'Index', 'toast failed: %{public}s', text);
    }
  }

  aboutToDisappear(): void {
    this.entries.forEach((e: CapsuleEntry) => e.runtime.stop());
    clearInterval(this.statusPoll);
    clearInterval(this.placeholderTimer);
  }

  // Core initialises the cloud config and the on-device model async; they may finish after the first render.
  private watchModelStatus(): void {
    let tries = 0;
    this.statusPoll = setInterval(() => {
      const status = getModelStatus();
      const onDevice = getOnDeviceStatus();
      this.modelStatus = status.message;
      this.cloudConfigured = status.configured;
      this.euCloud = status.euAvailable;
      this.cloudProviders = status.providers;
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
    this.loadWidgets(); // the user may have added or removed widgets while away
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

  /** Never throws: whatever goes wrong (any language, any reply), the user gets the failure card. */
  private async create(): Promise<void> {
    const text = this.request.trim();
    if (text.length === 0 || this.busy) {
      return;
    }
    try {
      await this.createFrom(text);
    } catch (e) {
      hilog.error(0x0001, 'Index', 'create crashed: %{public}s %{public}s', (e as Error).message, (e as Error).stack);
      this.busy = false;
      this.unsupported = [];
      this.failed = true;
    }
  }

  private async createFrom(text: string): Promise<void> {
    this.busy = true;
    this.message = '';
    this.failed = false;
    this.unsupported = [];
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
    const consent = this.settings.hasCloudConsent(this.cloudKey());
    const result = await this.generate(text, smart && consent);
    this.busy = false;
    if (!result.ok && result.failure === undefined && smart && !consent && this.cloudUsable()) {
      // The device couldn't build it and the cloud would be next: ask once before the first cloud request.
      hilog.info(0x0001, 'Index', 'on-device failed (%{public}s); showing the cloud notice', result.error ?? '');
      this.showCloudNotice(() => this.retryWithCloud(text), () => {
        this.failed = true;
      });
      return;
    }
    this.finishCreate(text, result);
  }

  /** Rules, then the on-device model, then the cloud model only when `allowCloud`. Never throws. */
  private async generate(text: string, allowCloud: boolean, cloudOnly: boolean = false): Promise<GenerateResult> {
    try {
      return await generateCapsule(text, {
        mode: this.settings.aiMode === 'on-device' ? 'on-device-only' : 'smart',
        allowNonEu: this.settings.allowNonEu,
        allowCloud: allowCloud,
        cloudOnly: cloudOnly
      });
    } catch (e) {
      const failed: GenerateResult = { ok: false, error: `generateCapsule threw: ${(e as Error).message}`, details: [] };
      return failed;
    }
  }

  /** One-time notice before the first cloud request. OK retries with the cloud; the other choice switches modes. */
  private showCloudNotice(onOk: () => void, onDeclined: () => void): void {
    this.getUIContext().showAlertDialog({
      title: cloudNotice(this.cloudKey()).title,
      message: cloudNotice(this.cloudKey()).message,
      autoCancel: false,
      // Stacked so "On-device only" is not cut off.
      buttonDirection: DialogButtonDirection.VERTICAL,
      buttons: [
        {
          value: 'OK',
          style: DialogButtonStyle.HIGHLIGHT,
          action: () => {
            this.settings.acceptCloudNotice(this.cloudKey());
            onOk();
          }
        },
        {
          value: 'On-device only',
          action: () => {
            this.settings.setAiMode('on-device');
            onDeclined();
          }
        }
      ],
      cancel: () => onDeclined()
    });
  }

  private async retryWithCloud(text: string): Promise<void> {
    this.busy = true;
    const result = await this.generate(text, true);
    this.busy = false;
    try {
      this.finishCreate(text, result);
    } catch (e) {
      hilog.error(0x0001, 'Index', 'finishCreate crashed: %{public}s', (e as Error).message);
      this.unsupported = [];
      this.failed = true;
    }
  }

  private finishCreate(text: string, result: GenerateResult): void {
    if (!result.ok || !result.capsule) {
      // The user sees a friendly message; the real error only goes to the log.
      hilog.error(0x0001, 'Index', 'generateCapsule failed for "%{private}s": %{public}s [%{public}s]',
        text, result.error ?? 'no error', failureDetail(result));
      this.unsupported = refusalWords(result);
      this.failed = true;
      return;
    }
    this.pending = this.uniqueCapsule(result.capsule);
    this.pendingOriginRaw = result.origin ?? '';
    this.pendingRequest = text;
    this.replacingId = '';
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
    if (this.pendingRequest.length > 0) {
      this.store?.setRequest(capsule.id, this.pendingRequest);
    }
    const replaced = this.entries.find((e: CapsuleEntry) => e.capsule.id === this.replacingId);
    if (replaced) {
      this.undo(replaced, `Replaced ${replaced.capsule.name} with a version made with Mistral (EU)`);
    }
    this.replacingId = '';
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
    this.unsupported = [];
    if (this.ctx) {
      refreshCapsuleWidgets(this.ctx);
    }
    setTimeout(() => this.open(capsule.id), 300);
  }

  private cancelPending(): void {
    this.pending = undefined;
    this.showSheet = false;
  }

  /**
   * A capsule from another phone. It goes to the gatekeeper sheet first and is
   * saved only when the user runs it; cancelling the sheet discards it.
   */
  private handleImported(prepared: PreparedImport): void {
    this.pending = this.uniqueCapsule(prepared.capsule);
    this.pendingOriginRaw = IMPORTED_ORIGIN;
    this.pendingRequest = '';
    this.replacingId = '';
    this.pendingOrigin = originBadge(this.pendingOriginRaw);
    this.showSheet = true;
  }

  private open(id: string): void {
    // The "Add to home screen" how-to starts open the first time only.
    const firstView = this.store !== undefined && !this.store.hintSeen(id);
    if (firstView) {
      this.store?.setHintSeen(id);
    }
    this.hintOpenIds = firstView ? this.hintOpenIds.concat([id]) : this.hintOpenIds.filter((x: string) => x !== id);
    this.getUIContext().animateTo({ curve: OPEN_CURVE }, () => {
      this.openId = id;
    });
  }

  private close(): void {
    this.getUIContext().animateTo({ curve: OPEN_CURVE }, () => {
      this.openId = '';
    });
  }

  private async undo(entry: CapsuleEntry, replacedNote?: string): Promise<void> {
    if (!this.gate || !this.timers) {
      return;
    }
    const capsule = entry.capsule;
    entry.runtime.stop();
    const cancelled = await this.timers.cancelForCapsule(capsule.id);
    const note = `${replacedNote ?? `Removed ${capsule.name}`}; cancelled ${cancelled} calendar reminder(s)`;
    this.gate.forget(capsule.id, note);
    this.store?.remove(capsule.id);
    this.close();
    if (this.ctx) {
      refreshCapsuleWidgets(this.ctx, capsule.id);
    }
    this.entries = this.entries.filter((e: CapsuleEntry) => e.capsule.id !== capsule.id);
    this.message = replacedNote === undefined ? note : '';
  }

  /** "Make it smarter": offered on rules and on-device capsules when smart mode can use the cloud. */
  private canMakeSmarter(entry: CapsuleEntry): boolean {
    return (entry.origin === 'rules' || entry.origin === 'on-device') && this.settings.aiMode === 'smart' &&
      this.cloudUsable();
  }

  /** Rebuilds a capsule with the cloud from its original request, then asks for consent again. */
  private makeSmarter(entry: CapsuleEntry): void {
    if (!this.settings.hasCloudConsent(this.cloudKey())) {
      this.showCloudNotice(() => this.rebuildWithCloud(entry), () => {
      });
      return;
    }
    this.rebuildWithCloud(entry);
  }

  private async rebuildWithCloud(entry: CapsuleEntry): Promise<void> {
    const saved = this.store?.request(entry.capsule.id) ?? '';
    const text = saved.length > 0 ? saved : entry.capsule.name;
    this.smarterBusyId = entry.capsule.id;
    // Cloud only: a matching rule or the on-device model would just rebuild the same capsule.
    const result = await this.generate(text, true, true);
    this.smarterBusyId = '';
    if (!result.ok || !result.capsule || !isCloudOrigin(result.origin ?? '')) {
      hilog.error(0x0001, 'Index', 'make smarter failed for "%{private}s": origin %{public}s, %{public}s',
        text, result.origin ?? '-', result.error ?? '');
      this.message = "Mistral couldn't improve this one right now.";
      return;
    }
    this.pending = this.uniqueCapsule(result.capsule);
    this.pendingOriginRaw = result.origin ?? '';
    this.pendingOrigin = originBadge(this.pendingOriginRaw);
    this.pendingRequest = text;
    this.replacingId = entry.capsule.id;
    this.showSheet = true;
  }

  private toggleHint(id: string): void {
    this.hintOpenIds = this.hintOpenIds.includes(id) ? this.hintOpenIds.filter((x: string) => x !== id) :
      this.hintOpenIds.concat([id]);
  }

  @Builder
  smarterButton(entry: CapsuleEntry) {
    Row({ space: 6 }) {
      if (this.smarterBusyId === entry.capsule.id) {
        LoadingProgress()
          .width(16)
          .height(16)
          .color($r('sys.color.brand'))
      } else {
        SymbolGlyph($r('sys.symbol.wand_and_stars'))
          .fontSize(16)
          .fontColor([$r('sys.color.brand')])
      }
      Text(this.smarterBusyId === entry.capsule.id ? `Asking ${this.cloudName()}…` :
        `Make it smarter with ${this.cloudName()}`)
        .fontSize($r('sys.float.Body_M'))
        .fontColor($r('sys.color.brand'))
    }
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .enabled(this.smarterBusyId.length === 0)
    .onClick(() => this.makeSmarter(entry))
  }

  /** The provider smart mode will send cloud requests to: Mistral when an EU provider is set up, else the default. */
  private cloudKey(): string {
    if (this.euCloud) {
      return 'mistral';
    }
    return this.cloudProviders.length > 0 ? this.cloudProviders[0] : '';
  }

  /** Settings > Smart: names the provider Smart mode would actually use (BUG-3). */
  private smartModeDetail(): string {
    if (this.euCloud) {
      return 'On-device + Mistral EU when needed';
    }
    if (!this.cloudConfigured) {
      return 'On-device + cloud AI when set up';
    }
    return this.settings.allowNonEu ? `On-device + ${this.cloudName()} (outside the EU) when needed` :
      `On-device only: ${this.cloudName()} is outside the EU`;
  }

  /** The cloud provider smart mode will use, as users know it. Core prefers an EU provider. */
  private cloudName(): string {
    if (this.euCloud) {
      return 'Mistral (EU)';
    }
    const p = this.cloudProviders.length > 0 ? this.cloudProviders[0] : '';
    return p === 'anthropic' ? 'Claude' : p === 'openai' ? 'OpenAI' : 'cloud AI';
  }

  /** Whether smart mode may use a cloud provider: an EU one, or any one if non-EU providers are allowed. */
  private cloudUsable(): boolean {
    return this.euCloud || (this.cloudConfigured && this.settings.allowNonEu);
  }

  /** Home status: on-device model state from core, then the cloud fallback state. */
  private statusLine(): string {
    if (this.settings.aiMode === 'on-device') {
      return `${this.onDeviceStatus} · On-device only`;
    }
    if (this.euCloud) {
      return `${this.onDeviceStatus} · Mistral (EU) when needed`;
    }
    if (this.cloudConfigured) {
      return `${this.onDeviceStatus} · ${this.settings.allowNonEu ? 'Cloud AI when needed' : 'No EU cloud provider'}`;
    }
    return `${this.onDeviceStatus} · ${this.modelStatus}`;
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
    } else if (name === CHOOSE_PAGE) {
      WidgetCapsulePicker({
        entries: this.entries,
        onPick: (capsuleId: string) => this.pickForWidget(capsuleId)
      })
    } else if (name === SETTINGS_PAGE) {
      SettingsView({
        settings: this.settings,
        cloudStatus: this.cloudConfigured ? '' : this.modelStatus,
        smartDetail: this.smartModeDetail()
      })
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
      // No inner padding here: the card's 16vp is the only inset, so the text lines up with the
      // Create button. Even a few vp of TextArea padding clipped the first glyph ("k", "W", "M").
      TextArea({ placeholder: PLACEHOLDERS[this.placeholderIndex], text: this.request })
        .height(96)
        .width('100%')
        .fontSize($r('sys.float.Body_L'))
        .backgroundColor(Color.Transparent)
        .borderRadius(0)
        .padding(0)
        .onChange((value: string) => {
          this.request = value;
        })
      Row() {
        Blank()
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

  /** AI status on its own line under the input card: one line, ellipsis when long. */
  @Builder
  statusRow() {
    Text(this.statusLine())
      .fontSize($r('sys.float.Caption_M'))
      .fontColor($r('sys.color.font_tertiary'))
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .width('100%')
      .padding({ left: 4, right: 4 })
  }

  /** Calm, final answer for requests capsules can never do; no suggestions to retry. */
  @Builder
  unsupportedCard() {
    Row({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.lock'))
        .fontSize(20)
        .fontColor([$r('sys.color.icon_secondary')])
      Column({ space: 6 }) {
        Text(`Harmoniser can't do ${joinWords(this.unsupported)} by design.`)
          .fontSize($r('sys.float.Body_L'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
        Text(`Capsules can only use: ${CAPSULE_ABILITIES}.`)
          .fontSize($r('sys.float.Body_M'))
          .fontColor($r('sys.color.font_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .alignItems(VerticalAlign.Top)
    .width('100%')
    .padding(16)
    .borderRadius(20)
    .backgroundColor($r('sys.color.comp_background_primary'))
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
            // Import is a secondary action: a small icon next to Settings and Log, not a big button.
            SharingBar({
              showShare: false,
              compact: true,
              onImported: (prepared: PreparedImport) => this.handleImported(prepared)
            })
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
        this.statusRow()
        Text('Tiny apps, made by asking.')
          .fontSize($r('sys.float.Body_M'))
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .padding({ left: 4 })
        if (this.failed && this.unsupported.length > 0) {
          this.unsupportedCard()
        } else if (this.failed) {
          this.failedCard()
        } else if (this.message.length > 0) {
          Text(this.message)
            .fontSize($r('sys.float.Body_M'))
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
        }
        // Import from another phone. Nothing is saved until the sheet's Run.
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
    if (entry.route.widget && this.widgets.length > 0) {
      Column({ space: 6 }) {
        Button() {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.square_grid_2x2'))
              .fontSize(18)
              .fontColor([$r('sys.color.brand')])
            Text('Show on home screen widget')
              .fontSize($r('sys.float.Body_L'))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.brand'))
          }
        }
        .width('100%')
        .height(48)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .onClick(() => this.showOnWidget(entry))
        if (this.widgets.some((w: WidgetInfo) => w.capsuleId === entry.capsule.id)) {
          Text('On your home screen')
            .fontSize($r('sys.float.Caption_M'))
            .fontColor($r('sys.color.font_tertiary'))
        }
      }
      .width('100%')
    } else if (entry.route.widget) {
      Column({ space: 10 }) {
        Row({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.square_grid_2x2'))
            .fontSize(22)
            .fontColor([$r('sys.color.brand')])
          Text('Add to home screen')
            .fontSize($r('sys.float.Subtitle_M'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
          SymbolGlyph(this.hintOpenIds.includes(entry.capsule.id) ? $r('sys.symbol.chevron_up') :
          $r('sys.symbol.chevron_down'))
            .fontSize(18)
            .fontColor([$r('sys.color.icon_secondary')])
        }
        .width('100%')
        .onClick(() => this.toggleHint(entry.capsule.id))
        if (this.hintOpenIds.includes(entry.capsule.id)) {
          Text('1. Long-press the Harmoniser app icon on your home screen.\n' +
            '2. Pick the Harmoniser widget.\n' +
            '3. Tap "Add to home screen".')
            .fontSize($r('sys.float.Body_M'))
            .fontColor($r('sys.color.font_secondary'))
            .lineHeight(22)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(16)
      .borderRadius(20)
      .backgroundColor($r('sys.color.comp_background_primary'))
      .border({ width: 1, color: $r('sys.color.brand'), style: BorderStyle.Dashed })
    } else {
      Text(routeHeadline(entry.route))
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
          if (this.canMakeSmarter(entry)) {
            this.smarterButton(entry)
          }
          this.routeCard(entry)
          // Share only: importing lives on the home screen.
          SharingBar({ capsule: entry.capsule, showImport: false })
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
