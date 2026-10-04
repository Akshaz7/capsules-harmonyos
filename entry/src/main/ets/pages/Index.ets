import { common } from '@kit.AbilityKit';
import { curves } from '@kit.ArkUI';
import {
  Capsule,
  CapsuleComponent,
  allComponents,
  DeviceComponent,
  carryState,
  editCapsule,
  EditResult,
  EDIT_NO_CHANGE,
  GenerateResult,
  StateValues,
  Permission,
  generateCapsule,
  generateCapsuleFromImage,
  getModelStatus,
  isNotEnglish,
  matchTemplate,
  parseRequest,
  getOnDeviceStatus,
  routeCapsule,
  BILL_SPLIT_CAPSULE,
  TENNIS_CAPSULE,
  Trigger,
  dueTimeTriggers,
  permissionForTrigger,
  triggerKey,
  validateCapsule
} from '../core';
import { GatekeeperTriggerGuard } from '../widget/TriggerGate';
import { TriggerCard } from './TriggerCard';
import { formatAt, retimed, triggerTitle, withoutTrigger } from './TriggerText';
import { NotificationAdapter } from '../adapters/NotificationAdapter';
import { TimerAdapter } from '../adapters/TimerAdapter';
import { MotionAdapter, MotionStatus } from '../adapters/MotionAdapter';
import { BatteryAdapter, BatteryReading } from '../adapters/BatteryAdapter';
import { WeatherAdapter, WeatherResult } from '../adapters/WeatherAdapter';
import { batteryDetail, batteryValue, DeviceReadout, emptyReadout } from '../capabilities/DeviceReadout';
import { CITIES, City, cityName, weatherValue, WEATHER_SOURCE } from '../capabilities/WeatherData';
import { MotionEvent } from '../capabilities/ShakeDetector';
import { activeMotionConsumers, MotionConsumer, motionCounterIds } from '../capabilities/MotionConsumers';
import { Gatekeeper } from '../gatekeeper/Gatekeeper';
import {
  ActionGuard,
  CapsuleRuntime,
  TimerAlert,
  TimerScheduler,
  TimerState
} from '../renderer/CapsuleRuntime';
import { Notifier } from '../renderer/CapsuleRuntime';
import { dailyReminders, notificationContent } from '../core/Reminders';
import { CapsuleView } from '../renderer/CapsuleView';
import { AppSettings } from './AppSettings';
import { CapsuleEntry, capsuleIcon, isCloudOrigin, originBadge, originIcon } from './CapsuleEntry';
import { CapsuleStore } from './CapsuleStore';
import { ConsentView } from './ConsentView';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  assignCapsuleToWidget, firstBlankWidget, listWidgets, refreshCapsuleWidgets, WidgetInfo
} from '../widget/WidgetService';
import { WidgetCapsulePicker } from './WidgetCapsulePicker';
import { AddToHomeButton } from '../widget/AddToHomeButton'; // PROTECTED: owned by T4
import { WidgetLaunch, widgetLaunch } from './WidgetLaunch';
import { ShareLaunch, shareLaunch } from './ShareLaunch';
import {
  failureDetail, isUnsupportedLanguage, joinWords, LANGUAGE_EXAMPLE, LANGUAGE_MESSAGE, limitsText, refusalWords
} from './CreateText';
import { loadState, saveState } from '../widget/WidgetStore';
import { LogView } from './LogView';
import { SettingsView } from './SettingsView';
import { prepareImport, PreparedImport, SharingBar, scanAndPrepare } from '../sharing';
import { loadLibraryJson, loadMarketplaceBaseUrl, MarketItem, MarketplaceClient } from '../adapters/MarketplaceClient';
import { MarketplaceView } from './MarketplaceView';
import {
  DeviceRelay, DeviceState, HttpDeviceRelay, isOffline, isStaleState, loadRelayBaseUrl, normalizePairCode, PairedDevice, payloadFor,
  relaySimulationEnabled, SimulatedDeviceRelay
} from '../adapters/DeviceRelay';
import { deviceName, DeviceStore } from '../adapters/DeviceStore';
import { getInstallToken, getMarketplaceToken } from '../adapters/InstallToken';
import { formatClock } from '../renderer/CapsuleRuntime';
import { DevicePanel } from './DevicePanel';
import { ChangeCard } from './ChangeCard';
import { HomeHero } from './HomeHero';
import { Flags } from '../theme/Flags';
import { Palette, Radius } from '../theme/Tokens';
import { storeWidthClass } from '../theme/Breakpoint';
import { CapsuleFrame, HostBar, originKindOf, TabBar, TabItem } from '../components';
import { PromptBar } from '../components/PromptBar';
import { BuildCard, BuildStep } from '../components/BuildCard';
import { BuildSkeleton } from '../components/BuildSkeleton';
import { VoiceButton } from '../components/VoiceButton';
import { BuildStage, buildStageIndex, BUILD_STAGES, buildStageText, stageFromCore, StageUpdate } from './BuildStages';
import { BuildStage as CoreStage } from '../core';
import { CapsuleTile } from '../components/CapsuleTile';
import { EmptyState, ErrorCard } from '../components';
import { RecentRow, RecentTile, SuggestionChips } from '../components/CreateParts';
import { shareCapsule } from '../sharing';
import { MiniPreview } from './MiniPreview';
import { reduceMotion, springCurve, successTick } from './Motion';
import { BUILT_FROM_TEMPLATE } from './CapsuleEntry';
import { copyToCache, pickPhoto, removeSnap, SNAP_HINT, SNAP_NEEDS_CLOUD, takePhoto } from './SnapPhoto';
import { CapsuleState, TimerRun } from '../core/WidgetModel';

/** The version before the last applied change, with its state, for "Undo last change". */
interface UndoPoint {
  capsule: Capsule;
  state: CapsuleState;
}

const LOG_PAGE = 'log';
const SETTINGS_PAGE = 'settings';
const CHOOSE_PAGE = 'chooseCapsule';
const MARKET_PAGE = 'marketplace';
const TAB_CREATE = 0;
const TAB_CAPSULES = 1;
const TAB_MARKET = 2;
const TAB_SETTINGS = 3;
/** Redesign tab bar items, in tab order. */
const TAB_ITEMS: TabItem[] = [
  { icon: $r('sys.symbol.plus_circle'), label: 'Create' },
  { icon: $r('sys.symbol.square_grid_2x2'), label: 'Capsules' },
  { icon: $r('sys.symbol.bag'), label: 'Marketplace' },
  { icon: $r('sys.symbol.gearshape'), label: 'Settings' }
];
const MARKETPLACE_ORIGIN = 'marketplace';
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
const TYPE_MS = 55; // one character per tick while typing the placeholder
const HOLD_TICKS = 30; // ~1.6 s with a whole example shown

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
  'notifications, vibration, the motion sensor (shakes while a capsule is open), the battery reading and a ' +
  'weather reading from Open-Meteo';

/** How often due daily triggers are checked while the app is open. */
const TRIGGER_CHECK_MS = 30 * 1000;

/** T3-12: a built-in template that fits the request, offered before anything is built. */

/** How often a device's state is read back while its capsule is on screen. */
const DEVICE_POLL_MS = 2000;

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

/** notify:<text> from a button or trigger: a notification titled with the text (T4-27). */
class NotifyText implements Notifier {
  private adapter: NotificationAdapter;
  private capsuleName: string;

  constructor(adapter: NotificationAdapter, capsuleName: string) {
    this.adapter = adapter;
    this.capsuleName = capsuleName;
  }

  notify(capsuleId: string, text: string): void {
    const n = notificationContent(this.capsuleName, text);
    this.adapter.publish(n.title, n.text, capsuleId); // tapping it opens the capsule
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
  private triggerTimer: number = -1;
  /** "Show on another device": the relay (or its labelled simulation) and the paired devices. */
  private relay: DeviceRelay = new SimulatedDeviceRelay();
  private deviceStore: DeviceStore | undefined = undefined;
  @Local devices: PairedDevice[] = [];
  @Local relaySimulated: boolean = true;
  /** The panel only shows with a relay configured (or the dev simulation flag): never a fake device on phones. */
  @Local devicesEnabled: boolean = false;
  /** Live line for the capsule last sent to a device; '' when none. */
  @Local deviceStatus: string = '';
  /** @Local: the panel's status is read only for this capsule, so this must re-render when it changes. */
  @Local deviceCapsuleId: string = '';
  private deviceId: string = '';
  private deviceVersion: number = 0;
  private devicePoll: number = -1;
  /** Marketplace (T3-10/T3-11): live when marketplace.baseUrl is configured, else the shipped examples. */
  private market: MarketplaceClient = new MarketplaceClient('', '', '');
  @Local marketConfigured: boolean = false;
  /** "Change it…" (T3-16): which capsule the card's state belongs to, and what it shows. */
  /** Snap (T3-2): the phone could not read the photo and the cloud was not used. */
  @Local snapNeedsCloud: boolean = false;
  @Local changeId: string = '';
  @Local changeBusy: boolean = false;
  @Local changeSummary: string[] = [];
  @Local changeIssue: string = '';
  @Local changeIssueText: string = '';
  /** Capsules with a change that "Undo last change" can take back (this session). */
  @Local undoIds: string[] = [];
  private changeResult: EditResult | undefined = undefined;
  private undoPoints: Map<string, UndoPoint> = new Map();
  /** True while the consent sheet is for an edit that asks for new permissions. */
  private consentForEdit: boolean = false;
  /** The marketplace item behind `pending`, for the install count once the user runs it. */
  private pendingMarketItem: MarketItem | undefined = undefined;
  /** Capsule ids this install has published, to show "Remove from marketplace". */
  @Local publishedIds: string[] = [];
  /** Time of the last trigger check; the trigger cards re-read "Next: ..." from it. */
  @Local triggerNow: number = Date.now();
  @Local placeholderIndex: number = 0;
  /** UI-2: the selected home tab, and a tap counter per tab for the symbol bounce. */
  @Local tab: number = TAB_CREATE;
  @Local tabTaps: number[] = [0, 0, 0, 0];
  private tabsController: TabsController = new TabsController();
  /** Redesign: true on wide windows (600vp and up); also stored in AppStorage by theme/Breakpoint. */
  @Local wide: boolean = false;
  /** Height of the Create tab, to place the heading about 40% down the screen. */
  @Local createHeight: number = 0;
  /** T3-28: where the current build is, for the live step line. */
  @Local buildStage: BuildStage = 'reading';
  /** The provider the model step asks ("Claude"), or '' for the phone's own model. */
  @Local buildCloud: string = '';
  /** Bumped by every build and by Cancel; a result whose number is stale is dropped. */
  private createSeq: number = 0;
  /** T3-32: true once core reported a stage for this build; Index's own guesses then stay out of the way. */
  private coreStageSeen: boolean = false;
  /** T3-29: the mic is listening (the prompt shows "Listening…"). */
  @Local listening: boolean = false;
  /** T3-29: why dictation stopped, shown as the standard error card; '' when fine. */
  @Local voiceError: string = '';
  /** Redesign frame: the "Change it…" card shows after the footer pill is tapped (or while it has news). */
  @Local changeOpenId: string = '';
  /** UI-1: the placeholder as typed so far (types and erases the examples). */
  @Local placeholderText: string = PLACEHOLDERS[0];
  @Local inputFocused: boolean = false;
  /** Bumped on tap: drives the camera symbol's bounce effect. */
  @Local cameraBounce: number = 0;
  @Local shimmerOn: boolean = false;
  private typed: number = 0;
  private erasing: boolean = false;
  private holdTicks: number = 0;
  @Local entries: CapsuleEntry[] = [];
  @Local openId: string = '';
  /** Motion: one shared accelerometer subscription; the scope comes from Settings. */
  private motion: MotionAdapter | undefined = undefined;
  @Local motionState: MotionStatus = 'unsupported';
  private motionProbed: boolean = false;
  private foreground: boolean = false;
  private battery: BatteryAdapter | undefined = undefined;
  private weather: WeatherAdapter | undefined = undefined;
  /** Capsule id whose city picker is open; '' when closed. */
  @Local cityPickerId: string = '';
  @Local pending: Capsule | undefined = undefined;
  @Local pendingOrigin: string = '';
  /** T3-17: the consent sheet's "Built from a template" line; '' when the capsule was not. */
  @Local pendingBuiltFrom: string = '';
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
  /** Core's English-only gate refused the request (T4-11): show the calm language card. */
  @Local languageFailed: boolean = false;
  /** "Found a template: X — Use / Adapt / Build new" (T3-12); undefined when none is offered. */
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
    this.motion = new MotionAdapter();
    this.motion.probe().then((s: MotionStatus) => {
      this.motionState = s;
      this.motionProbed = true;
      this.syncMotion();
    });
    this.battery = new BatteryAdapter();
    this.weather = new WeatherAdapter();
    this.watchModelStatus();
    if (reduceMotion()) {
      this.placeholderTimer = setInterval(() => {
        this.placeholderIndex = (this.placeholderIndex + 1) % PLACEHOLDERS.length;
        this.placeholderText = PLACEHOLDERS[this.placeholderIndex];
      }, PLACEHOLDER_MS);
    } else {
      this.placeholderText = '';
      this.placeholderTimer = setInterval(() => this.typePlaceholder(), TYPE_MS);
    }
    // Saved capsules were approved before; ones whose consent was lost get dropped.
    const gate = this.gate;
    this.entries = this.store.all()
      .filter((c: Capsule) => gate.hasDecided(c.id))
      .map((c: Capsule) => this.makeEntry(c));
    this.loadWidgets();
    if (this.launch.formId.length > 0) {
      // Cold start from a blank widget: open the picker once the Navigation is up.
      setTimeout(() => this.openCapsulePicker(), 0);
    } else if (this.launch.capsuleId.length > 0) {
      setTimeout(() => this.openLaunchedCapsule(), 0); // cold start from a reminder or widget tap
    }
    if (this.share.seq > 0) {
      setTimeout(() => this.onShared(), 0); // cold start from the share sheet
    }
    this.checkTriggers();
    this.triggerTimer = setInterval(() => this.checkTriggers(), TRIGGER_CHECK_MS);
    this.deviceStore = new DeviceStore(ctx);
    this.devices = this.deviceStore.all();
    const base = loadRelayBaseUrl(ctx);
    this.relay = base.length > 0 ? new HttpDeviceRelay(base, getInstallToken(ctx)) : new SimulatedDeviceRelay();
    this.relaySimulated = this.relay.simulated;
    this.devicesEnabled = base.length > 0 || relaySimulationEnabled(ctx);
    const marketBase = loadMarketplaceBaseUrl(ctx);
    this.marketConfigured = marketBase.length > 0;
    loadLibraryJson(ctx).then((library: string) => {
      this.market = new MarketplaceClient(marketBase, marketBase.length > 0 ? getMarketplaceToken(ctx) : '', library);
    });
    this.publishedIds = this.entries.filter((e: CapsuleEntry) => (this.store?.published(e.capsule.id) ?? '').length > 0)
      .map((e: CapsuleEntry) => e.capsule.id);
  }

  // ---- Marketplace (T3-10 / T3-11) ----

  /** Install = download the JSON into the normal import flow: validator, fresh id, consent. Nothing runs yet. */
  private async installFromMarket(item: MarketItem): Promise<void> {
    const got = await this.market.capsuleJson(item);
    if (got.json === undefined) {
      this.toast(got.error ?? "Couldn't download that capsule. Check your connection and try again.");
      return;
    }
    const prepared = prepareImport(got.json);
    if (!prepared.ok || prepared.capsule === undefined) {
      this.toast(prepared.error ?? "That capsule isn't valid, so nothing was installed.");
      return;
    }
    this.nav.pop();
    this.pending = this.uniqueCapsule(prepared.capsule);
    this.pendingOriginRaw = MARKETPLACE_ORIGIN;
    this.pendingRequest = '';
    this.replacingId = '';
    this.pendingMarketItem = item;
    this.pendingOrigin = originBadge(this.pendingOriginRaw);
    this.showSheet = true;
  }

  private publishToMarket(entry: CapsuleEntry): void {
    const name = entry.capsule.name;
    this.getUIContext().showAlertDialog({
      title: `Publish "${name}"?`,
      message: `The name "${name}" and how the capsule works become public: anyone can find and install it. ` +
        'Its current values, your request and your permissions are not included.',
      primaryButton: { value: 'Cancel', action: () => {
      } },
      secondaryButton: { value: 'Publish', action: async () => {
        const r = await this.market.publish(entry.capsule, '', []);
        const id = r.id ?? r.duplicateId ?? '';
        if (id.length > 0) {
          this.store?.setPublished(entry.capsule.id, id);
          this.publishedIds = this.publishedIds.filter((x: string) => x !== entry.capsule.id).concat([entry.capsule.id]);
        }
        this.toast(r.id !== undefined ? 'Published. Anyone can install it now.' : r.error ?? "Couldn't publish it. Try again later.");
      } }
    });
  }

  private async unpublishFromMarket(entry: CapsuleEntry): Promise<void> {
    const id = this.store?.published(entry.capsule.id) ?? '';
    if (id.length === 0) {
      return;
    }
    if (await this.market.unpublish(id)) {
      this.store?.setPublished(entry.capsule.id, '');
      this.publishedIds = this.publishedIds.filter((x: string) => x !== entry.capsule.id);
      this.toast('Removed from the marketplace');
    } else {
      this.toast("Couldn't reach the marketplace. Try again later.");
    }
  }

  // ---- Show on another device (T3-15) ----

  private async pairScan(): Promise<void> {
    if (!this.ctx) {
      return;
    }
    const outcome = await scanAndPrepare(this.ctx);
    if (outcome.pairCode !== undefined) {
      await this.claimDevice(outcome.pairCode);
    } else if (!outcome.cancelled) {
      this.toast("That isn't a device's pairing code");
    }
  }

  private async claimDevice(text: string): Promise<void> {
    const code = normalizePairCode(text);
    if (code.length === 0) {
      this.toast('Type the three words shown on the device');
      return;
    }
    const r = await this.relay.claim(code);
    if (r.device !== undefined && this.deviceStore) {
      this.devices = this.deviceStore.add(r.device);
      this.toast(`Paired with ${deviceName(r.device)}`);
    } else {
      this.toast(r.error ?? "Couldn't pair that device. Check the code and try again.");
    }
  }

  private unpairDevice(id: string): void {
    this.relay.unpair(id); // best effort: forget it here whatever the relay says
    if (this.deviceStore) {
      this.devices = this.deviceStore.remove(id);
    }
    if (this.deviceId === id) {
      this.stopDevicePoll();
    }
  }

  /**
   * T3-15 with T4-13: once this capsule has "devices" it sends straight away; until then it asks once and the
   * gatekeeper keeps the answer (allowDevices / denyDevices, both logged). Every send is logged too.
   */
  private showOnDevice(entry: CapsuleEntry, deviceId: string): void {
    const counter = entry.runtime.counters.length > 0 ? entry.runtime.counters[0].value : undefined;
    const payload = payloadFor(entry.capsule, counter);
    const device = this.devices.find((d: PairedDevice) => d.id === deviceId);
    if (payload === null || device === undefined || !this.gate) {
      return;
    }
    const gate = this.gate;
    const name = deviceName(device);
    const number = payload.type === 'timer' ? `${payload.seconds} seconds` : `the count ${payload.count}`;
    const what = `${payload.type} "${payload.label}", ${number}`;
    const send = (): void => {
      gate.logDeviceSend(entry.capsule.id, true, `sent to ${name}: ${what}`);
      this.sendToDevice(entry, deviceId);
    };
    if (gate.canSendToDevice(entry.capsule.id)) {
      send();
      return;
    }
    this.getUIContext().showAlertDialog({
      title: `Show "${entry.capsule.name}" on ${name}?`,
      message: `Only this leaves your phone: ${what}. Harmoniser remembers your answer for this capsule.` +
        `${this.relaySimulated ? ' (Simulated: nothing is sent.)' : ''}`,
      primaryButton: { value: "Don't allow", action: () => {
        gate.denyDevices(entry.capsule.id, `show on ${name}`);
      } },
      secondaryButton: { value: 'Allow and send', action: () => {
        gate.allowDevices(entry.capsule.id, `show on ${name}`);
        send();
      } }
    });
  }

  /** T3-15: a capsule's own sendToDevice button: the device last used, else the first paired one. */
  private sendFromButton(capsuleId: string): void {
    const entry = this.entries.find((e: CapsuleEntry) => e.capsule.id === capsuleId);
    const device = this.devices.find((d: PairedDevice) => d.id === this.deviceId) ??
      (this.devices.length > 0 ? this.devices[0] : undefined);
    if (entry === undefined) {
      return;
    }
    if (device === undefined) {
      this.toast('Pair a device first: open "Show on another device" below the capsule.');
      return;
    }
    this.showOnDevice(entry, device.id);
  }

  private async sendToDevice(entry: CapsuleEntry, deviceId: string): Promise<void> {
    const counter = entry.runtime.counters.length > 0 ? entry.runtime.counters[0].value : undefined;
    const payload = payloadFor(entry.capsule, counter);
    if (payload === null) {
      return;
    }
    const version = await this.relay.send(deviceId, payload);
    hilog.info(0x0001, 'Index', 'device send -> version %{public}d', version);
    if (version < 0) {
      this.deviceStatus = "Couldn't reach the device. The capsule still works here.";
      return;
    }
    this.deviceCapsuleId = entry.capsule.id;
    this.deviceId = deviceId;
    this.deviceVersion = version;
    this.deviceStatus = 'Sent. Waiting for the device...';
    clearInterval(this.devicePoll);
    this.devicePoll = setInterval(() => this.pollDevice(), DEVICE_POLL_MS);
  }

  private async pollDevice(): Promise<void> {
    if (this.openId !== this.deviceCapsuleId) {
      this.stopDevicePoll(); // only while that capsule is on screen
      return;
    }
    const device = this.devices.find((d: PairedDevice) => d.id === this.deviceId);
    const s: DeviceState | null = await this.relay.state(this.deviceId);
    if (s === null) {
      this.deviceStatus = 'The device is not answering. The capsule still works here.';
      return;
    }
    if (isStaleState(s, this.deviceVersion)) {
      return;
    }
    const name = device !== undefined ? deviceName(device) : 'Device';
    if (isOffline(s)) {
      this.deviceStatus = `${name} is offline`;
      return;
    }
    const value = s.type === 'timer' ? (s.done ? 'done' : formatClock(s.remaining_seconds)) : `${s.count}`;
    this.deviceStatus = `On ${name}: ${s.label} ${value}`;
  }

  private stopDevicePoll(): void {
    clearInterval(this.devicePoll);
    this.devicePoll = -1;
    this.deviceStatus = '';
    this.deviceCapsuleId = '';
  }

  /**
   * Fires daily "time" triggers that are due (schema v1.1) through core and the gatekeeper. Runs while the app
   * is open; a time missed while it was closed fires once on the next check (core's dueTimeTriggers rule).
   */
  private checkTriggers(): void {
    const gate = this.gate;
    const store = this.store;
    this.triggerNow = Date.now();
    if (!gate || !store) {
      return;
    }
    let runs = store.triggerRuns();
    const before = JSON.stringify(runs);
    const guard = new GatekeeperTriggerGuard(gate);
    this.entries.forEach((e: CapsuleEntry) => {
      if ((e.capsule.triggers ?? []).length === 0) {
        return;
      }
      const due = dueTimeTriggers(e.capsule, runs, this.triggerNow);
      runs = due.lastRun;
      due.indices.forEach((i: number) => {
        const r = e.runtime.fireTrigger(i, guard);
        if (r.fired) {
          this.toast(`${triggerTitle((e.capsule.triggers ?? [])[i])} ran in ${e.capsule.name}`);
        }
      });
    });
    if (JSON.stringify(runs) !== before) {
      store.setTriggerRuns(runs);
    }
  }

  private triggersAllowed(entry: CapsuleEntry): boolean[] {
    const gate = this.gate;
    return (entry.capsule.triggers ?? []).map((t: Trigger) =>
      gate !== undefined && gate.isAllowed(entry.capsule, permissionForTrigger(t)));
  }

  private runTriggerNow(entry: CapsuleEntry, index: number): void {
    if (!this.gate) {
      return;
    }
    const r = entry.runtime.fireTrigger(index, new GatekeeperTriggerGuard(this.gate));
    const name = triggerTitle((entry.capsule.triggers ?? [])[index]);
    this.toast(r.fired ? `${name} ran` : r.blocked.length > 0 ? `Blocked: ${r.blocked}` : `${name} didn't run`);
  }

  // ---- Motion (schema v1.1 counters with source "motion" and motion triggers) ----

  /**
   * Reads the battery for the capsule on screen, only while it is allowed and only on open or on return to
   * the foreground. Nothing is polled in the background. (Weather joins this in the next slice.)
   */
  private refreshDeviceReadings(): void {
    const entry = this.openEntry();
    const gate = this.gate;
    const battery = this.battery;
    if (!entry || !gate || !battery) {
      return;
    }
    this.refreshBattery(entry);
    this.refreshWeather(entry);
  }

  /** Reads the battery only for capsules that actually show one, and only while it is allowed. */
  private refreshBattery(entry: CapsuleEntry): void {
    const gate = this.gate;
    const battery = this.battery;
    if (!gate || !battery) {
      return;
    }
    const showsBattery: boolean = allComponents(entry.capsule.ui).some((c: CapsuleComponent) =>
      c.type === 'device' && (c as DeviceComponent).bind === 'battery');
    if (!showsBattery || !gate.isAllowed(entry.capsule, 'battery') || gate.isRemoved(entry.capsule.id)) {
      return;
    }
    const reading: BatteryReading = battery.read();
    const out: DeviceReadout = emptyReadout();
    if (reading.state === 'ok') {
      out.state = 'ok';
      out.value = batteryValue(reading.soc, reading.charging);
      out.detail = batteryDetail(reading.charging);
      out.percent = reading.soc;
      out.charging = reading.charging;
    } else {
      out.state = 'unavailable';
      out.value = 'Unavailable';
      out.detail = 'This phone does not report its battery here';
    }
    entry.runtime.setDeviceReadout('battery', out);
  }

  /** The capsule's weather component, if it has one. */
  private weatherComponent(capsule: Capsule): DeviceComponent | undefined {
    const hit = allComponents(capsule.ui).find((c: CapsuleComponent) =>
      c.type === 'device' && (c as DeviceComponent).bind === 'weather');
    return hit === undefined ? undefined : hit as DeviceComponent;
  }

  /** The city the capsule names, else the one the user picked for it; '' when none yet. */
  private weatherCityFor(capsule: Capsule, c: DeviceComponent): string {
    const named: string = c.city ?? '';
    if (named.length > 0) {
      return named;
    }
    return this.store?.weatherCity(capsule.id) ?? '';
  }

  /**
   * Renders the cached reading and fetches when it is missing or older than 15 minutes. Only the chosen
   * city's coordinates are sent, never capsule text or state. Nothing is fetched when the capsule is denied.
   */
  private refreshWeather(entry: CapsuleEntry): void {
    const gate = this.gate;
    const weather = this.weather;
    if (!gate || !weather) {
      return;
    }
    const c = this.weatherComponent(entry.capsule);
    if (c === undefined || gate.isRemoved(entry.capsule.id) || !gate.isAllowed(entry.capsule, 'weather')) {
      return;
    }
    const city: string = this.weatherCityFor(entry.capsule, c);
    if (city.length === 0) {
      const ask = emptyReadout();
      ask.state = 'pending';
      ask.title = 'Weather';
      ask.value = '—';
      ask.detail = 'Tap to choose a city';
      entry.runtime.setDeviceReadout('weather', ask);
      return;
    }
    const now: number = Date.now();
    const cached: WeatherResult = weather.read(city, now);
    if (cached.reading !== null) {
      this.applyWeather(entry, city, cached);
    } else {
      const pending = emptyReadout();
      pending.state = 'pending';
      pending.title = cityName(city);
      pending.value = '…';
      pending.detail = 'Getting the weather…';
      entry.runtime.setDeviceReadout('weather', pending);
    }
    if (cached.state !== 'ok') {
      weather.refresh(city, now).then((r: WeatherResult) => {
        const g = this.gate;
        if (g && !g.isRemoved(entry.capsule.id) && g.isAllowed(entry.capsule, 'weather')) {
          this.applyWeather(entry, city, r);
        }
      });
    }
  }

  /** Writes one validated weather result into the capsule's read-only reading. */
  private applyWeather(entry: CapsuleEntry, cityId: string, result: WeatherResult): void {
    const out: DeviceReadout = emptyReadout();
    out.title = cityName(cityId);
    if (result.reading !== null) {
      out.value = weatherValue(result.reading);
      out.detail = `Updated ${this.clockText(result.reading.fetchedAt)}` +
        (result.state === 'stale' ? ' · stale' : '');
      out.source = WEATHER_SOURCE;
      out.weatherCode = result.reading.code;
      out.state = result.state === 'ok' ? 'ok' : 'stale';
    } else {
      out.state = result.state === 'offline' ? 'offline' : 'unavailable';
      out.value = 'Unavailable';
      out.detail = result.state === 'offline' ? 'No connection' : 'The weather service did not answer';
    }
    entry.runtime.setDeviceReadout('weather', out);
  }

  private clockText(ms: number): string {
    const d = new Date(ms);
    const h: number = d.getHours();
    const m: number = d.getMinutes();
    return `${h < 10 ? '0' : ''}${h}:${m < 10 ? '0' : ''}${m}`;
  }

  private openCityPicker(capsuleId: string): void {
    this.cityPickerId = capsuleId;
  }

  /** Stores the picked city for that capsule, then fetches for it. */
  private chooseCity(cityId: string): void {
    const capsuleId: string = this.cityPickerId;
    this.cityPickerId = '';
    if (capsuleId.length === 0 || !this.store) {
      return;
    }
    this.store.setWeatherCity(capsuleId, cityId);
    const entry = this.entries.find((e: CapsuleEntry) => e.capsule.id === capsuleId);
    if (entry !== undefined) {
      this.refreshWeather(entry);
    }
  }

  private cityPickerCurrent(): string {
    return this.cityPickerId.length > 0 ? (this.store?.weatherCity(this.cityPickerId) ?? '') : '';
  }

  @Builder
  citySheet() {
    Column({ space: 8 }) {
      Text('Weather city')
        .fontSize($r('sys.float.Title_M'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
      Text('Only this city\'s coordinates are sent to Open-Meteo. Nothing else leaves the phone.')
        .fontSize($r('sys.float.Caption_M'))
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      List({ space: 0 }) {
        ForEach(CITIES, (c: City) => {
          ListItem() {
            Row({ space: 12 }) {
              Text(c.name)
                .fontSize($r('sys.float.Body_L'))
                .fontColor($r('sys.color.font_primary'))
                .layoutWeight(1)
              if (this.cityPickerCurrent() === c.id) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(18)
                  .fontColor([$r('sys.color.brand')])
              }
            }
            .width('100%')
            .height(48)
            .onClick(() => this.chooseCity(c.id))
          }
        }, (c: City) => c.id)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 16 })
    .backgroundColor($r('sys.color.background_secondary'))
  }

  /** The line under a capsule's motion counters: how to count, or why it cannot count here. */
  private motionNoteFor(capsule: Capsule): string {
    if (!this.motionProbed || motionCounterIds(capsule).length === 0) {
      return '';
    }
    if (this.motionState === 'available') {
      return 'Shake the phone to count';
    }
    if (this.motionState === 'denied') {
      return 'Motion access is off in system settings';
    }
    if (this.motionState === 'error') {
      return 'Motion sensor unavailable right now';
    }
    return 'Motion sensor unavailable on this device';
  }

  /** Capsules that may receive shakes now: scope setting, per-capsule grant and the capsule still present. */
  private motionConsumersNow(): MotionConsumer[] {
    const gate = this.gate;
    if (!gate) {
      return [];
    }
    const capsules: Capsule[] = this.entries.map((e: CapsuleEntry) => e.capsule);
    return activeMotionConsumers(capsules, this.settings.motionScope, this.openId,
      (c: Capsule) => gate.isAllowed(c, 'motion') && !gate.isRemoved(c.id));
  }

  /** Keeps exactly one subscription running when there is something to feed and the app is in front. */
  private syncMotion(): void {
    const motion = this.motion;
    if (!motion) {
      return;
    }
    if (this.motionState !== 'available' || !this.foreground || this.motionConsumersNow().length === 0) {
      motion.stop();
      return;
    }
    motion.start((e: MotionEvent) => this.onMotionEvent(e), (s: MotionStatus) => {
      this.motionState = s;
      motion.stop();
    });
  }

  /**
   * One shake event, applied to every active consumer. The motion grant is verified again immediately
   * before each counter increment and each trigger, so a revoked capsule stops at once.
   */
  private onMotionEvent(e: MotionEvent): void {
    const gate = this.gate;
    if (!gate) {
      return;
    }
    this.motionConsumersNow().forEach((c: MotionConsumer) => {
      const entry = this.entries.find((x: CapsuleEntry) => x.capsule.id === c.capsuleId);
      if (!entry || gate.isRemoved(entry.capsule.id) || !gate.isAllowed(entry.capsule, 'motion')) {
        return;
      }
      if (e.kind === 'shake') {
        c.counterIds.forEach((id: string) => entry.runtime.dispatch(`increment:${id}`));
        return;
      }
      c.triggerIndices.forEach((i: number) => entry.runtime.fireTrigger(i, new GatekeeperTriggerGuard(gate)));
    });
  }

  private editTriggerTime(entry: CapsuleEntry, index: number): void {
    const t = (entry.capsule.triggers ?? [])[index];
    if (t === undefined || t.on !== 'time') {
      return;
    }
    const selected = new Date();
    const hm = (t.at ?? '08:00').split(':');
    selected.setHours(parseInt(hm[0], 10), parseInt(hm[1], 10), 0, 0);
    this.getUIContext().showTimePickerDialog({
      selected: selected,
      useMilitaryTime: true,
      onAccept: (v: TimePickerResult) => {
        const at = formatAt(v.hour ?? 0, v.minute ?? 0);
        if (at !== t.at) {
          this.updateTriggers(retimed(entry.capsule, index, at));
        }
      }
    });
  }

  private removeTrigger(entry: CapsuleEntry, index: number): void {
    const name = triggerTitle((entry.capsule.triggers ?? [])[index]);
    this.getUIContext().showAlertDialog({
      title: `Remove "${name}"?`,
      message: 'It will stop running by itself. The rest of the capsule stays.',
      primaryButton: { value: 'Cancel', action: () => {
      } },
      secondaryButton: { value: 'Remove', fontColor: $r('sys.color.warning'), action: () => {
        this.updateTriggers(withoutTrigger(entry.capsule, index));
      } }
    });
  }

  /**
   * Saves a capsule whose triggers changed and rebuilds its entry. The edited capsule is validated first.
   * Its trigger history is cleared, so a changed time starts counting fresh instead of firing at once.
   */
  private updateTriggers(updated: Capsule): void {
    const store = this.store;
    if (!store) {
      return;
    }
    const v = validateCapsule(JSON.stringify(updated));
    if (!v.ok || !v.capsule) {
      hilog.error(0x0001, 'Index', 'edited triggers invalid: %{public}s', v.errors.join('; '));
      this.toast("That trigger change isn't valid, so nothing changed.");
      return;
    }
    const capsule = v.capsule;
    store.replace(capsule);
    const runs = store.triggerRuns();
    const prefix = triggerKey(capsule.id, 0).slice(0, -1); // "<id>#", core's key without the index
    const kept: Record<string, number> = {};
    Object.keys(runs).filter((k: string) => !k.startsWith(prefix)).forEach((k: string) => {
      kept[k] = runs[k];
    });
    store.setTriggerRuns(kept);
    // Update the entry in place: the open capsule page holds this object, not a lookup.
    const entry = this.entries.find((e: CapsuleEntry) => e.capsule.id === capsule.id);
    if (entry !== undefined) {
      entry.runtime.stop();
      const fresh = this.makeEntry(capsule);
      entry.capsule = fresh.capsule;
      entry.runtime = fresh.runtime;
    }
    hilog.info(0x0001, 'Index', 'triggers of %{public}s updated: %{public}d left', capsule.id,
      (capsule.triggers ?? []).length);
    this.checkTriggers();
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
      this.createFromPhoto(this.share.imageUri);
    }
  }

  @Monitor('launch.formId')
  onWidgetLaunch(): void {
    if (this.launch.formId.length > 0) {
      this.openCapsulePicker();
    }
  }

  @Monitor('launch.capsuleId')
  onCapsuleLaunch(): void {
    if (this.launch.capsuleId.length > 0 && this.entries.length > 0) {
      this.openLaunchedCapsule();
    }
  }

  /** A reminder notification or a widget's "tap to open": show that capsule (if it is still saved). */
  private openLaunchedCapsule(): void {
    const id = this.launch.capsuleId;
    this.launch.capsuleId = '';
    if (this.entries.some((e: CapsuleEntry) => e.capsule.id === id)) {
      this.nav.clear();
      this.open(id);
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
    this.toast(ok ? `${name} is now on your home screen` : "That widget isn't there any more. Add a new one from the home screen.");
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
    this.toast(ok ? `Showing ${entry.capsule.name} on Widget ${index + 1}` : "Couldn't show it on that widget. Try another one.");
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
    this.motion?.stop();
    clearInterval(this.statusPoll);
    clearInterval(this.placeholderTimer);
    clearInterval(this.triggerTimer);
    clearInterval(this.devicePoll);
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
      if (this.gate.isAllowed(capsule, 'notifications') && this.notifications) {
        rt.notifier = new NotifyText(this.notifications, capsule.name); // asks to enable notifications once
      }
      rt.onSendToDevice = () => this.sendFromButton(capsule.id); // T3-15: same path as "Show on another device"

      // Daily notify triggers ring from the calendar, also while the app is closed (T4-27).
      const reminders = this.gate.isAllowed(capsule, 'reminders') && this.gate.isAllowed(capsule, 'notifications') ?
        dailyReminders(capsule) : [];
      if (this.timers) {
        // Adds, updates or removes; never duplicates. Until the calendar holds them, the app notifies itself.
        this.timers.syncDailyReminders(capsule.id, reminders).then((ok: boolean) => {
          rt.calendarReminders = ok && reminders.length > 0;
        });
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
    this.foreground = true;
    this.entries.forEach((e: CapsuleEntry) => e.runtime.applyState(loadState(ctx, e.capsule)));
    this.loadWidgets(); // the user may have added or removed widgets while away
    this.checkTriggers(); // a time that passed while the app was away fires once now
    this.syncMotion();
    this.refreshDeviceReadings(); // a battery read on return to the foreground only
    hilog.info(0x0001, 'Index', 'reloaded widget state for %{public}d capsules', this.entries.length);
  }

  /** The app left the front: motion is foreground-only, so the subscription stops here. */
  onPageHide(): void {
    this.foreground = false;
    this.motion?.stop();
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
      computed: capsule.computed,
      triggers: capsule.triggers // v1.1: without this, new and imported capsules lost their triggers
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
      this.languageFailed = false;
        this.failed = true;
    }
  }

  private async createFrom(text: string): Promise<void> {
    const seq = ++this.createSeq;
    this.coreStageSeen = false;
    this.voiceError = '';
    this.buildStage = 'reading';
    this.buildCloud = '';
    this.dismissKeyboard();
    this.busy = true;
    this.snapNeedsCloud = false;
    this.message = '';
    this.failed = false;
    this.unsupported = [];
    this.languageFailed = false;
    const fixture = demoFixture(text);
    if (fixture !== null) {
      const v = validateCapsule(fixture);
      this.busy = false;
      const demo: GenerateResult = { ok: v.ok, capsule: v.capsule, origin: 'rules', error: v.errors.join('; '),
        details: v.errors };
      this.finishCreate(text, demo);
      return;
    }
    // T3-12: when the rules don't cover it but a built-in template does, offer it first.
    this.buildStage = 'templates';
    if (!isNotEnglish(text) && parseRequest(text) === null) {
      const m = matchTemplate(text);
      if (m !== null) {
        // T3-17: a strong template match goes straight to consent, with "Build fresh" as the way out.
        this.busy = false;
        hilog.info(0x0001, 'Index', 'built from template %{public}s (score %{public}d)', m.template.id,
          Math.round(m.score * 100));
        const fromTemplate: GenerateResult = { ok: true, capsule: m.capsule, origin: 'template', details: [] };
        this.finishCreate(text, fromTemplate);
        this.pendingBuiltFrom = BUILT_FROM_TEMPLATE;
        return;
      }
    }
    const smart = this.settings.aiMode === 'smart';
    const consent = this.settings.hasCloudConsent(this.cloudKey());
    // Until core reports its stages (T4-25), the model step names the cloud only when it may be used.
    this.buildCloud = smart && consent && this.cloudUsable() ? this.cloudName() : '';
    this.buildStage = 'model';
    const result = await this.generate(text, smart && consent);
    if (seq !== this.createSeq) {
      return; // cancelled, or replaced by a newer build: drop the late result
    }
    if (!this.coreStageSeen) {
      this.buildStage = 'checking';
    }
    this.busy = false;
    if (!result.ok && result.failure === undefined && !isUnsupportedLanguage(result) && smart && !consent &&
      this.cloudUsable()) {
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
  private async generate(text: string, allowCloud: boolean, cloudOnly: boolean = false,
    skipTemplates: boolean = false): Promise<GenerateResult> {
    const seq = this.createSeq;
    try {
      return await generateCapsule(text, {
        onStage: (stage: CoreStage) => this.onCoreStage(seq, stage), // T3-32: the live step line
        mode: this.settings.aiMode === 'on-device' ? 'on-device-only' : 'smart',
        allowNonEu: this.settings.allowNonEu,
        allowCloud: allowCloud,
        cloudOnly: cloudOnly,
        skipTemplates: skipTemplates // "Build fresh": no cache, templates or marketplace (T4 355746d)
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
    const seq = ++this.createSeq;
    this.coreStageSeen = false;
    this.buildCloud = this.cloudName();
    this.buildStage = 'model';
    this.busy = true;
    const result = await this.generate(text, true);
    if (seq !== this.createSeq) {
      return; // cancelled
    }
    if (!this.coreStageSeen) {
      this.buildStage = 'checking';
    }
    this.busy = false;
    try {
      this.finishCreate(text, result);
    } catch (e) {
      hilog.error(0x0001, 'Index', 'finishCreate crashed: %{public}s', (e as Error).message);
      this.unsupported = [];
      this.languageFailed = false;
        this.failed = true;
    }
  }

  /** Wide windows (>= 600vp, NEW_WIDE): the capsule frame shows its extras in a side panel. */
  private frameHasSide(): boolean {
    return Flags.NEW_WIDE && this.wide;
  }

  /** T3-29: partial then final dictated text replaces the prompt each time. */
  private onVoiceText(text: string): void {
    this.voiceError = '';
    this.request = text;
  }

  private onVoiceError(message: string): void {
    this.listening = false;
    this.voiceError = message;
  }

  /** The prompt's placeholder: "Listening…" while the mic is on, else the rotating examples. */
  private promptPlaceholder(): string {
    return this.listening ? 'Listening…' : this.placeholderText;
  }

  /** T3-32: core's stage events drive the step line, for the build that is still on screen only. */
  private onCoreStage(seq: number, stage: CoreStage): void {
    if (seq !== this.createSeq || !this.busy) {
      return; // cancelled or replaced
    }
    const u: StageUpdate | null = stageFromCore(stage.name, stage.provider);
    if (u === null) {
      return;
    }
    this.coreStageSeen = true;
    this.buildStage = u.stage;
    if (u.stage === 'model') {
      this.buildCloud = u.cloud;
    }
  }

  /** T3-28 Cancel: the build keeps running in core, but its result is ignored when it arrives. */
  private cancelBuild(): void {
    this.createSeq++;
    this.busy = false;
    this.buildStage = 'reading';
    hilog.info(0x0001, 'Index', 'build cancelled by the user');
  }

  private dismissKeyboard(): void {
    try {
      this.getUIContext().getFocusController().clearFocus();
    } catch (e) {
      // no focused input: nothing to dismiss
    }
  }

  /** T3-28: the live build card under the prompt, fading and scaling out as the sheet or capsule takes over. */
  @Builder
  buildLive() {
    if (this.busy) {
      BuildSkeleton({
        stepText: buildStageText(this.buildStage, this.buildCloud),
        stepIndex: buildStageIndex(this.buildStage),
        stepCount: BUILD_STAGES.length,
        reduceMotion: reduceMotion(),
        onCancel: () => this.cancelBuild()
      })
        .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.96, y: 0.96 }))
          .animation({ duration: reduceMotion() ? 0 : 250, curve: Curve.EaseOut }))
    }
  }

  private finishCreate(text: string, result: GenerateResult): void {
    if (isUnsupportedLanguage(result)) {
      // English only for now (T4-11): a calm card, never the error or refusal card, and nothing is saved.
      hilog.info(0x0001, 'Index', 'request refused by the English-only gate');
      this.unsupported = [];
      this.failed = false;
      this.languageFailed = true;
      return;
    }
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
    this.pendingBuiltFrom = '';
    this.replacingId = '';
    this.pendingOrigin = originBadge(this.pendingOriginRaw);
    this.showSheet = true;
  }

  private decide(allowed: Permission[]): void {
    const capsule = this.pending;
    if (!capsule || !this.gate) {
      return;
    }
    if (this.consentForEdit) {
      // An edit that asks for new permissions: same capsule id, so the new answers replace the old grants.
      this.gate.decide(capsule, allowed);
      this.syncMotion(); // an edit can add or drop the motion grant
      this.consentForEdit = false;
      this.pending = undefined;
      this.showSheet = false;
      this.applyChange();
      return;
    }
    this.gate.decide(capsule, allowed);
    this.syncMotion();
    this.store?.setOrigin(capsule.id, this.pendingOriginRaw);
    if (this.pendingRequest.length > 0) {
      this.store?.setRequest(capsule.id, this.pendingRequest);
    }
    const replaced = this.entries.find((e: CapsuleEntry) => e.capsule.id === this.replacingId);
    if (replaced) {
      this.undo(replaced, `Replaced ${replaced.capsule.name} with a version made with Mistral (EU)`);
    }
    this.replacingId = '';
    if (this.pendingOriginRaw === MARKETPLACE_ORIGIN && this.pendingMarketItem !== undefined) {
      this.market.installed(this.pendingMarketItem); // best effort, after the user chose to run it
    }
    this.pendingMarketItem = undefined;
    this.store?.add(capsule);
    const entry = this.makeEntry(capsule);
    successTick();
    this.getUIContext().animateTo({ curve: springCurve() }, () => {
      this.entries = [entry].concat(this.entries); // the card springs into "Your capsules"
    });
    if (this.gate.isAllowed(capsule, 'reminders')) {
      this.timers?.prepare().then(() => this.notifications?.ensureEnabled());
    }
    this.pending = undefined;
    this.showSheet = false;
    this.request = '';
    this.message = '';
    this.failed = false;
    this.unsupported = [];
    this.languageFailed = false;
    if (this.ctx) {
      refreshCapsuleWidgets(this.ctx);
    }
    setTimeout(() => this.open(capsule.id), reduceMotion() ? 300 : 700); // let the card land first
  }

  private cancelPending(): void {
    this.pendingBuiltFrom = '';
    this.consentForEdit = false; // the change stays proposed; nothing was applied
    this.pending = undefined;
    this.pendingMarketItem = undefined;
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
    this.syncMotion(); // the "while a capsule is open" scope starts with this page
    this.refreshDeviceReadings();
  }

  private close(): void {
    this.getUIContext().animateTo({ curve: OPEN_CURVE }, () => {
      this.openId = '';
    });
    this.syncMotion();
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
    this.syncMotion(); // no consumers left for a removed capsule
    this.message = replacedNote === undefined ? note : '';
  }

  /** "Make it smarter": offered on rules and on-device capsules when smart mode can use the cloud. */
  private canMakeSmarter(entry: CapsuleEntry): boolean {
    return (entry.origin === 'rules' || entry.origin === 'template' || entry.origin === 'on-device') &&
      this.settings.aiMode === 'smart' &&
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

  /** Snap: camera or gallery, then the photo path. The pickers are system UIs (no permission needed). */
  private snap(): void {
    this.getUIContext().showActionSheet({
      title: 'Snap',
      message: SNAP_HINT,
      autoCancel: true,
      confirm: {
        value: 'Cancel',
        action: () => {
        }
      },
      sheets: [
        {
          title: 'Take a photo',
          action: () => {
            if (this.ctx) {
              takePhoto(this.ctx).then((uri: string) => this.createFromPhoto(uri));
            }
          }
        },
        {
          title: 'Choose from gallery',
          action: () => {
            pickPhoto().then((uri: string) => this.createFromPhoto(uri));
          }
        }
      ]
    });
  }

  /**
   * Photo -> capsule via core (on-device text reading first, the cloud only under the usual consent).
   * The "needs cloud" note shows only when core says the phone could not do it (needsCloud). Never throws.
   */
  private async createFromPhoto(uri: string, allowCloud?: boolean): Promise<void> {
    const ctx = this.ctx;
    if (!ctx || uri.length === 0 || this.busy) {
      return;
    }
    this.failed = false;
    this.unsupported = [];
    this.languageFailed = false;
    this.snapNeedsCloud = false;
    const path = copyToCache(ctx, uri);
    if (path.length === 0) {
      this.toast("Couldn't open that photo. Try another one.");
      return;
    }
    this.busy = true;
    const smart = this.settings.aiMode === 'smart';
    const consent = this.settings.hasCloudConsent(this.cloudKey());
    let result: GenerateResult;
    try {
      result = await generateCapsuleFromImage(path, {
        mode: smart ? 'smart' : 'on-device-only',
        allowNonEu: this.settings.allowNonEu,
        allowCloud: allowCloud ?? (smart && consent)
      });
    } catch (e) {
      result = { ok: false, error: `generateCapsuleFromImage threw: ${(e as Error).message}`, details: [] };
    }
    removeSnap(path);
    this.busy = false;
    hilog.info(0x0001, 'Index', 'photo -> ok %{public}s origin %{public}s needsCloud %{public}s', String(result.ok),
      result.origin ?? '-', String(result.needsCloud === true));
    if (!result.ok && result.needsCloud === true) {
      if (smart && !consent && this.cloudUsable()) {
        this.showCloudNotice(() => this.createFromPhoto(uri, true), () => {
          this.snapNeedsCloud = true;
        });
      } else {
        this.snapNeedsCloud = true;
      }
      return;
    }
    try {
      this.finishCreate('', result); // the consent sheet shows the origin badge (on your phone / cloud)
    } catch (e) {
      hilog.error(0x0001, 'Index', 'finishCreate crashed: %{public}s', (e as Error).message);
      this.failed = true;
    }
  }

  @Builder
  snapCloudNote() {
    if (Flags.NEW_SNAP) {
      // Redesign: the standard error card; same text, same single action.
      ErrorCard({
        title: SNAP_NEEDS_CLOUD,
        action: this.settings.aiMode === 'on-device' ? 'Switch AI mode to Smart in Settings' : '',
        onAction: () => this.selectTab(TAB_SETTINGS)
      })
    } else {
      this.snapCloudNoteOld()
    }
  }

  @Builder
  snapCloudNoteOld() {
    Row({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.camera'))
        .fontSize(20)
        .fontColor([$r('sys.color.icon_secondary')])
      Column({ space: 4 }) {
        Text(SNAP_NEEDS_CLOUD)
          .fontSize($r('sys.float.Body_M'))
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
        if (this.settings.aiMode === 'on-device') {
          Text('Switch AI mode to Smart in Settings')
            .fontSize($r('sys.float.Body_M'))
            .fontColor($r('sys.color.brand'))
            .fontWeight(FontWeight.Medium)
            .onClick(() => this.selectTab(TAB_SETTINGS))
        }
      }
      .layoutWeight(1)
    }
    .alignItems(VerticalAlign.Top)
    .width('100%')
    .padding(16)
    .borderRadius(20)
    .backgroundColor($r('sys.color.comp_background_primary'))
  }

  /** T3-16: the card's state is per capsule; opening another one starts clean. */
  private resetChange(id: string): void {
    this.changeId = id;
    this.changeBusy = false;
    this.changeSummary = [];
    this.changeIssue = '';
    this.changeIssueText = '';
    this.changeResult = undefined;
  }

  /** "Change it…": English gate, rules, then the cloud under the same consent as creating. Never throws. */
  private async proposeChange(entry: CapsuleEntry, text: string, allowCloud?: boolean): Promise<void> {
    const ctx = this.ctx;
    if (!ctx || this.changeBusy) {
      return;
    }
    this.resetChange(entry.capsule.id);
    this.changeBusy = true;
    const smart = this.settings.aiMode === 'smart';
    const consent = this.settings.hasCloudConsent(this.cloudKey());
    const r = await editCapsule(ctx, entry.capsule, text, {
      mode: smart ? 'smart' : 'on-device-only',
      allowNonEu: this.settings.allowNonEu,
      allowCloud: allowCloud ?? (smart && consent)
    });
    this.changeBusy = false;
    if (this.changeId !== entry.capsule.id) {
      return; // the user opened another capsule meanwhile
    }
    if (!r.ok && r.needsCloud === true && smart && !consent && this.cloudUsable()) {
      this.showCloudNotice(() => this.proposeChange(entry, text, true), () => {
        this.changeIssue = 'failed';
      });
      return;
    }
    if (r.failure === 'unsupported-language') {
      hilog.info(0x0001, 'Index', 'change refused by the English-only gate');
      this.changeIssue = 'language';
      return;
    }
    if (!r.ok || !r.capsule) {
      hilog.error(0x0001, 'Index', 'change "%{private}s" failed: %{public}s [%{public}s]', text, r.error ?? '',
        r.details.join('; '));
      this.changeIssue = 'failed';
      this.changeIssueText = r.error === EDIT_NO_CHANGE ? "That wouldn't change anything." :
        r.failure === 'not-an-app' ? (r.error ?? '') : '';
      return;
    }
    hilog.info(0x0001, 'Index', 'change proposed by %{public}s: %{public}s', r.origin ?? '-', r.summary.join(' | '));
    this.changeResult = r;
    this.changeSummary = r.summary.length > 0 ? r.summary : ['Small changes'];
  }

  /** Apply: new permissions go through the gatekeeper sheet first; otherwise the change is saved now. */
  private confirmChange(): void {
    const r = this.changeResult;
    if (!r || !r.capsule) {
      return;
    }
    if (r.needsConsent) {
      this.pending = r.capsule;
      this.pendingOriginRaw = this.store?.origin(r.capsule.id) ?? '';
      this.pendingOrigin = originBadge(this.pendingOriginRaw);
      this.pendingRequest = '';
      this.replacingId = '';
      this.consentForEdit = true;
      this.showSheet = true;
      return;
    }
    this.applyChange();
  }

  private applyChange(): void {
    const r = this.changeResult;
    const entry = this.entries.find((e: CapsuleEntry) => e.capsule.id === this.changeId);
    if (!r || !r.capsule || !entry) {
      return;
    }
    const before = entry.runtime.exportState();
    this.undoPoints.set(entry.capsule.id, { capsule: entry.capsule, state: before });
    this.swapVersion(entry, r.capsule, carryState(entry.capsule, r.capsule, before), before);
    if (!this.undoIds.includes(r.capsule.id)) {
      this.undoIds = this.undoIds.concat([r.capsule.id]);
    }
    this.resetChange(r.capsule.id);
    this.toast('Changed');
  }

  /** "Undo last change": the version before the last Apply, with the state it had then. */
  private undoChange(entry: CapsuleEntry): void {
    const point = this.undoPoints.get(entry.capsule.id);
    if (!point) {
      return;
    }
    this.undoPoints.delete(entry.capsule.id);
    this.undoIds = this.undoIds.filter((id: string) => id !== entry.capsule.id);
    this.swapVersion(entry, point.capsule, point.state, entry.runtime.exportState());
    this.resetChange(entry.capsule.id);
    this.toast('Undid the last change');
  }

  /**
   * Saves `capsule` (same id) with `state`, rebuilds the entry in place (the open page holds it), cancels the
   * calendar reminders of timers that no longer run, and refreshes the widgets.
   */
  private swapVersion(entry: CapsuleEntry, capsule: Capsule, state: CapsuleState, old: CapsuleState): void {
    const ctx = this.ctx;
    if (!ctx || !this.store) {
      return;
    }
    this.store.replace(capsule);
    saveState(ctx, state);
    if (capsule.state !== undefined) {
      const values: StateValues = state.values ?? {};
      this.store.setValues(capsule.id, values);
    }
    const now = Date.now();
    old.timers.filter((run: TimerRun) => run.endAt > now &&
      !state.timers.some((kept: TimerRun) => kept.id === run.id && kept.endAt === run.endAt))
      .forEach((run: TimerRun) => {
        this.timers?.cancelTimer(capsule.id, run.id);
      });
    entry.runtime.stop();
    const fresh = this.makeEntry(capsule);
    entry.capsule = fresh.capsule;
    entry.runtime = fresh.runtime;
    entry.route = fresh.route;
    if (this.gate?.isAllowed(capsule, 'reminders')) {
      this.timers?.prepare().then(() => this.notifications?.ensureEnabled());
    }
    refreshCapsuleWidgets(ctx, capsule.id);
    this.checkTriggers();
  }

  @Builder
  changeCard(entry: CapsuleEntry) {
    ChangeCard({
      busy: this.changeId === entry.capsule.id && this.changeBusy,
      summary: this.changeId === entry.capsule.id ? this.changeSummary : [],
      issue: this.changeId === entry.capsule.id ? this.changeIssue : '',
      issueText: this.changeId === entry.capsule.id ? this.changeIssueText : '',
      canUndo: this.undoIds.includes(entry.capsule.id),
      autoFocus: this.changeOpenId === entry.capsule.id,
      onSubmit: (text: string) => this.proposeChange(entry, text),
      onApply: () => this.confirmChange(),
      onCancel: () => this.resetChange(entry.capsule.id),
      onUndo: () => this.undoChange(entry),
      onLimits: () => this.nav.pushPath({ name: SETTINGS_PAGE })
    })
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
    } else if (name === MARKET_PAGE) {
      MarketplaceView({
        client: this.market,
        wide: this.wide,
        onDeviceOnly: this.settings.aiMode === 'on-device',
        onOpenSettings: () => this.nav.pushPath({ name: SETTINGS_PAGE }),
        onInstall: (item: MarketItem) => this.installFromMarket(item)
      })
    } else if (name === SETTINGS_PAGE) {
      SettingsView({
        settings: this.settings,
        cloudStatus: this.cloudConfigured ? '' : this.modelStatus,
        smartDetail: this.smartModeDetail(),
        onMotionScopeChange: () => this.syncMotion()
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
    if (this.cityPickerId.length > 0) {
      this.citySheet()
    } else {
      Column() {
        if (this.pending) {
          ConsentView({
            capsule: this.pending,
            origin: this.pendingOrigin,
            originKind: originKindOf(this.pendingOriginRaw),
            builtFrom: this.pendingBuiltFrom,
            canBuildFresh: this.pendingBuiltFrom.length > 0, // the cloud when usable, else the phone (skipTemplates)
            onBuildFresh: () => this.buildFresh(),
            onDecide: (allowed: Permission[]) => this.decide(allowed),
            onCancel: () => this.cancelPending()
          })
        }
      }
      .width('100%')
    }
  }

  @Builder
  inputCard() {
    Column({ space: 12 }) {
      // No inner padding here: the card's 16vp is the only inset, so the text lines up with the
      // Create button. Even a few vp of TextArea padding clipped the first glyph ("k", "W", "M").
      TextArea({ placeholder: this.promptPlaceholder(), text: this.request })
        .height(96)
        .onFocus(() => {
          this.inputFocused = true;
        })
        .onBlur(() => {
          this.inputFocused = false;
        })
        .width('100%')
        .fontSize(Flags.NEW_CREATE_CLASSIC ? 17 : $r('sys.float.Body_L'))
        .fontColor(Flags.NEW_CREATE_CLASSIC ? Palette.text : undefined)
        .placeholderColor(Flags.NEW_CREATE_CLASSIC ? Palette.disabled : undefined)
        .backgroundColor(Color.Transparent)
        .borderRadius(0)
        .padding(0)
        .onChange((value: string) => {
          this.request = value;
        })
      Row() {
        if (Flags.CREATE_SNAP) {
          Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
            SymbolGlyph($r('sys.symbol.camera'))
              .fontSize(20)
              .fontColor([Flags.NEW_CREATE_CLASSIC ? Palette.text : $r('sys.color.icon_primary')])
              .symbolEffect(new BounceSymbolEffect(EffectScope.WHOLE, EffectDirection.UP), this.cameraBounce)
          }
          .width(Flags.NEW_CREATE_CLASSIC ? 44 : 40)
          .height(Flags.NEW_CREATE_CLASSIC ? 44 : 40)
          .backgroundColor(Flags.NEW_CREATE_CLASSIC ? Palette.softButton : undefined)
          .enabled(!this.busy)
          .accessibilityText('Snap')
          .accessibilityDescription(SNAP_HINT)
          .onClick(() => {
            this.cameraBounce++;
            this.snap();
          })
        } else {
          // T3-29: dictation replaces Snap; the words land in the prompt as they are spoken.
          VoiceButton({
            diameter: Flags.NEW_CREATE_CLASSIC ? 44 : 40,
            onText: (t: string) => this.onVoiceText(t),
            onError: (m: string) => this.onVoiceError(m),
            onListening: (on: boolean) => {
              this.listening = on;
            }
          })
            .enabled(!this.busy)
        }
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
          .height(40)
          .overlay(this.shimmer(), { align: Alignment.Start })
        }
        .height(Flags.NEW_CREATE_CLASSIC ? 44 : 40)
        .clip(true)
        .backgroundColor(Flags.NEW_CREATE_CLASSIC ? (this.busy || this.request.trim().length > 0 ? Palette.blue : Palette.sendDisabled) :
          $r('sys.color.brand'))
        .clickEffect(reduceMotion() ? null : { level: ClickEffectLevel.MIDDLE, scale: 0.92 })
        .enabled(!this.busy && this.request.trim().length > 0)
        .opacity(Flags.NEW_CREATE_CLASSIC || this.busy || this.request.trim().length > 0 ? 1 : 0.4)
        .onClick(() => {
          this.create();
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .borderRadius(Flags.NEW_CREATE_CLASSIC ? 22 : 24)
    // Frosted material over the hero gradient, with a soft shadow; a brand glow while typing.
    // NEW_CREATE_CLASSIC: a white card, 1vp line border (blue while typing), the same soft shadow.
    .backgroundBlurStyle(Flags.NEW_CREATE_CLASSIC ? BlurStyle.NONE : BlurStyle.COMPONENT_THIN)
    .backgroundColor(Flags.NEW_CREATE_CLASSIC ? Palette.surface : undefined)
    .border({ width: Flags.NEW_CREATE_CLASSIC ? (this.inputFocused ? 1.5 : 1) : (this.inputFocused ? 1.5 : 0.5),
      color: this.inputFocused ? (Flags.NEW_CREATE_CLASSIC ? Palette.blue : $r('sys.color.brand')) :
        (Flags.NEW_CREATE_CLASSIC ? Palette.line2 : $r('sys.color.comp_divider')) })
    .shadow(this.inputFocused ? { radius: 28, color: '#335B8CFF', offsetY: 6 } :
      { radius: 16, color: '#14000000', offsetY: 4 })
    .animation({ duration: 220, curve: Curve.EaseOut })
  }

  /** A light band sweeping across Create while it builds (not with reduce motion). */
  @Builder
  shimmer() {
    if (this.busy && !reduceMotion()) {
      Column()
        .width(56)
        .height(40)
        .linearGradient({ angle: 90, colors: [['#00FFFFFF', 0], ['#55FFFFFF', 0.5], ['#00FFFFFF', 1]] })
        .translate({ x: this.shimmerOn ? 160 : -60 })
        .onAppear(() => {
          this.shimmerOn = false;
          this.getUIContext().animateTo({ duration: 1100, curve: Curve.Linear, iterations: -1 }, () => {
            this.shimmerOn = true;
          });
        })
    }
  }

  /** UI-1: type an example, hold it, erase it, move to the next. */
  private typePlaceholder(): void {
    const target = PLACEHOLDERS[this.placeholderIndex];
    if (this.holdTicks > 0) {
      this.holdTicks--;
      return;
    }
    if (!this.erasing) {
      this.typed = Math.min(this.typed + 1, target.length);
      this.placeholderText = target.substring(0, this.typed);
      if (this.typed === target.length) {
        this.erasing = true;
        this.holdTicks = HOLD_TICKS;
      }
      return;
    }
    this.typed = Math.max(this.typed - 2, 0);
    this.placeholderText = target.substring(0, this.typed);
    if (this.typed === 0) {
      this.erasing = false;
      this.holdTicks = 4;
      this.placeholderIndex = (this.placeholderIndex + 1) % PLACEHOLDERS.length;
    }
  }

  /** AI status on its own line under the input card: one line, ellipsis when long. */
  @Builder
  statusRow() {
    Text(this.statusLine())
      .fontSize(Flags.NEW_CREATE_CLASSIC ? 13 : $r('sys.float.Caption_M'))
      .fontWeight(Flags.NEW_CREATE_CLASSIC ? 500 : undefined)
      .fontColor(Flags.NEW_CREATE_CLASSIC ? Palette.text2 : $r('sys.color.font_tertiary'))
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .width('100%')
      .padding({ left: 4, right: 4 })
  }

  /** Calm, final answer for requests capsules can never do; no suggestions to retry. */
  @Builder
  unsupportedCard() {
    if (Flags.NEW_ERRORS) {
      ErrorCard({
        title: `Harmoniser can't do ${joinWords(this.unsupported)} by design.`,
        body: `Capsules can only use: ${CAPSULE_ABILITIES}.`
      })
    } else {
      this.unsupportedCardOld()
    }
  }

  @Builder
  unsupportedCardOld() {
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

  /**
   * "Not quite right? Build fresh" on a template's consent sheet: skip the cache, templates and marketplace and
   * build a capsule for this request. With the cloud usable it asks the cloud (after the cloud notice; declining
   * brings the template back); otherwise the phone's own model builds it.
   */
  private buildFresh(): void {
    const capsule = this.pending;
    const request = this.pendingRequest;
    if (capsule === undefined || request.length === 0) {
      return;
    }
    this.cancelPending();
    const useCloud = this.settings.aiMode === 'smart' && this.cloudUsable();
    const run = async (): Promise<void> => {
      const seq = ++this.createSeq;
      this.coreStageSeen = false;
      this.buildCloud = useCloud ? this.cloudName() : '';
      this.buildStage = 'model';
      this.busy = true;
      const result = await this.generate(request, useCloud, useCloud, true);
      if (seq !== this.createSeq) {
        return; // cancelled
      }
      if (!this.coreStageSeen) {
        this.buildStage = 'checking';
      }
      this.busy = false;
      this.finishCreate(request, result);
    };
    if (!useCloud || this.settings.hasCloudConsent(this.cloudKey())) {
      run();
    } else {
      this.showCloudNotice(() => run(), () => {
        const back: GenerateResult = { ok: true, capsule: capsule, origin: 'template', details: [] };
        this.finishCreate(request, back);
        this.pendingBuiltFrom = BUILT_FROM_TEMPLATE;
      });
    }
  }

  /** T3-13: exact wording; tapping the example fills the input (it does not create anything). */
  @Builder
  languageCard() {
    Row({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.character_on_character'))
        .fontSize(20)
        .fontColor([Flags.NEW_ERRORS ? Palette.orangeIcon : $r('sys.color.icon_secondary')])
      Text() {
        Span(LANGUAGE_MESSAGE)
        Span(`'${LANGUAGE_EXAMPLE}'`)
          .fontColor(Flags.NEW_ERRORS ? Palette.orangeText : $r('sys.color.font_emphasize'))
          .fontWeight(FontWeight.Medium)
          .onClick(() => this.useLanguageExample())
        Span('.')
      }
      .fontSize($r('sys.float.Body_M'))
      .fontColor($r('sys.color.font_primary'))
      .layoutWeight(1)
    }
    .alignItems(VerticalAlign.Top)
    .width('100%')
    .padding(16)
    .borderRadius(Flags.NEW_ERRORS ? Radius.card : 20)
    .backgroundColor(Flags.NEW_ERRORS ? Palette.orangeTintSoft : $r('sys.color.comp_background_primary'))
  }

  private useLanguageExample(): void {
    this.request = LANGUAGE_EXAMPLE;
    this.languageFailed = false;
  }

  @Builder
  failedCard() {
    Column({ space: 12 }) {
      Text(FAILED_MESSAGE)
        .fontSize(Flags.NEW_ERRORS ? 15 : $r('sys.float.Body_M'))
        .fontWeight(Flags.NEW_ERRORS ? 700 : undefined)
        .fontColor(Flags.NEW_ERRORS ? Palette.orangeText : $r('sys.color.font_primary'))
        .width('100%')
      Text(limitsText())
        .fontSize($r('sys.float.Body_S'))
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
        .onClick(() => this.selectTab(TAB_SETTINGS))
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
          .backgroundColor(Flags.NEW_ERRORS ? Palette.surface : $r('sys.color.comp_background_tertiary'))
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
            .fontColor(Flags.NEW_ERRORS ? Palette.orangeText : $r('sys.color.brand'))
            .fontWeight(FontWeight.Medium)
            .onClick(() => this.selectTab(TAB_SETTINGS))
        }
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(16)
    .borderRadius(Flags.NEW_ERRORS ? Radius.card : 20)
    .backgroundColor(Flags.NEW_ERRORS ? Palette.orangeTintSoft : $r('sys.color.comp_background_primary'))
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
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height(236)
    .padding(16)
    .borderRadius(24)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .geometryTransition(entry.capsule.id)
    // A new capsule lands with a spring (the insert runs inside animateTo in decide()).
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.7, y: 0.7 })))
    .onClick(() => this.open(entry.capsule.id))
  }

  @Builder
  home() {
    Scroll() {
      Column({ space: 16 }) {
        if (Flags.NEW_CREATE_CLASSIC) {
          // New logo and wordmark, and the scan-QR button (the existing import: file or QR).
          Row() {
            HostBar({ showScan: false })
              .layoutWeight(1)
              .margin({ left: -20 }) // HostBar pads 20; the page already pads 16
            SharingBar({
              showShare: false,
              compact: true,
              onPairCode: (code: string) => this.claimDevice(code),
              onImported: (prepared: PreparedImport) => this.handleImported(prepared)
            })
          }
          .width('100%')
        } else {
          Row({ space: 8 }) {
            Image($r('app.media.harmoniser_mark'))
              .width(28)
              .height(28)
            Text('Harmoniser')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('sys.color.font_primary'))
          }
          .width('100%')
          .height(44)
        }
        Column({ space: 4 }) {
          HomeHero()
          Text("Tiny apps you don't need to download.")
            .fontSize(Flags.NEW_CREATE_CLASSIC ? 15 : $r('sys.float.Body_L'))
            .fontWeight(Flags.NEW_CREATE_CLASSIC ? 500 : undefined)
            .fontColor(Flags.NEW_CREATE_CLASSIC ? Palette.text2 : $r('sys.color.font_secondary'))
            .width('100%')
        }
        this.inputCard()
        if (Flags.NEW_BUILD_LIVE) {
          this.buildLive()
        }
        this.statusRow()
        this.createNotices()
        this.recentSection()
      }
      .padding({ left: 16, right: 16, top: 8, bottom: 120 }) // room for the floating tab bar
      .width('100%')
      .constraintSize({ maxWidth: Flags.NEW_WIDE && this.wide ? 640 : undefined })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .edgeEffect(EdgeEffect.Spring)
    .scrollBar(BarState.Off)
    // One soft, static pale-blue wash at the top that fades into the system background.
    .linearGradient({ direction: GradientDirection.Bottom,
      colors: Flags.NEW_CREATE_CLASSIC ? [[Color.Transparent, 0], [Color.Transparent, 1]] :
        [[$r('app.color.hero_top'), 0], [$r('sys.color.background_secondary'), 0.35]] })
    .transition(TransitionEffect.OPACITY)
  }

  /** The create flow's cards (failure, language, snap, message): one at a time, as before. */
  @Builder
  createNotices() {
    if (this.voiceError.length > 0) {
      ErrorCard({ title: this.voiceError })
    } else if (this.snapNeedsCloud) {
      this.snapCloudNote()
    } else if (this.languageFailed) {
      this.languageCard()
    } else if (this.failed && this.unsupported.length > 0) {
      this.unsupportedCard()
    } else if (this.failed) {
      this.failedCard()
    } else if (this.message.length > 0) {
      Text(this.message)
        .fontSize(Flags.NEW_ERRORS ? 14 : $r('sys.float.Body_M'))
        .fontColor(Flags.NEW_ERRORS ? Palette.text2 : $r('sys.color.font_secondary'))
        .width('100%')
    }
  }

  /** Redesign (NEW_CREATE): host bar, title, Recent, suggestions, and the prompt bar docked above the tab bar. */
  @Builder
  createTab() {
    Column() {
      Scroll() {
        Column({ space: 14 }) {
          Row() {
            HostBar({ showScan: false })
              .layoutWeight(1)
            // The existing import (file or QR scan); nothing is saved until the consent sheet's Run.
            SharingBar({
              showShare: false,
              compact: true,
              onPairCode: (code: string) => this.claimDevice(code),
              onImported: (prepared: PreparedImport) => this.handleImported(prepared)
            })
              .margin({ right: 16 })
          }
          .width('100%')
          // Brand, then the big question about 40% down, then the prompt bar (host bar is about 56vp).
          Column()
            .width('100%')
            .height(Math.max(8, this.createHeight * 0.4 - 56 - 28))
          Column({ space: 4 }) {
            Text('What do you need?')
              .fontSize(24)
              .fontWeight(800)
              .fontColor(Palette.text)
              .width('100%')
            Text("Tiny apps you don't need to download.")
              .fontSize(13)
              .fontWeight(500)
              .fontColor(Palette.text2)
              .width('100%')
          }
          .padding({ left: 20, right: 20 })
          Column({ space: 14 }) {
            if (Flags.NEW_BUILD_LIVE) {
              this.buildLive()
            } else if (Flags.NEW_PROGRESS && this.busy) {
              BuildCard({
                request: this.request.trim().length > 0 ? this.request.trim() : 'Reading your photo',
                steps: this.buildSteps()
              })
            }
            this.createNotices()
            if (Flags.CREATE_RECENT) {
              RecentRow({ tiles: this.recentTiles(), onOpen: (id: string) => this.open(id) })
            }
            if (Flags.CREATE_SUGGESTIONS && this.request.trim().length === 0) {
              SuggestionChips({ suggestions: this.suggestions(), onPick: (text: string) => {
                this.request = text;
              } })
            }
            Text(this.statusLine())
              .fontSize(13)
              .fontWeight(500)
              .fontColor(Palette.text2)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          .padding({ left: 16, right: 16 })
        }
        .width('100%')
        .constraintSize({ maxWidth: this.wide ? 640 : undefined })
        .padding({ bottom: 16 })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      PromptBar({
        text: this.request,
        placeholder: this.promptPlaceholder(),
        busy: this.busy,
        onTextChange: (v: string) => {
          this.request = v;
        },
        onSend: () => this.create(),
        onSnap: () => {
          this.cameraBounce++;
          this.snap();
        },
        onVoiceText: (t: string) => this.onVoiceText(t),
        onVoiceError: (m: string) => this.onVoiceError(m),
        onListening: (on: boolean) => {
          this.listening = on;
        },
        onFocusChange: (focused: boolean) => {
          this.inputFocused = focused;
        }
      })
        .margin({ left: 12, right: 12, bottom: 64 + 12 + 10 }) // above the floating tab bar
        .constraintSize({ maxWidth: this.wide ? 640 : undefined })
    }
    .width('100%')
    .height('100%')
    .onAreaChange((o: Area, n: Area) => {
      this.createHeight = n.height as number;
    })
  }

  private recentTiles(): RecentTile[] {
    return this.entries.slice(0, 8).map((e: CapsuleEntry): RecentTile => {
      const t: RecentTile = {
        id: e.capsule.id, name: e.capsule.name, icon: capsuleIcon(e.capsule), originText: originBadge(e.origin),
        originKind: originKindOf(e.origin)
      };
      return t;
    });
  }

  /** The order the core tries sources (core/CapsuleGenerator.ets), as the build card lists it. */
  private buildSteps(): BuildStep[] {
    const steps: BuildStep[] = [{ label: 'On your phone', detail: 'Built-in rules and templates, no internet' }];
    steps.push({ label: 'On-device AI', detail: this.onDeviceStatus });
    if (this.settings.aiMode === 'smart' && this.cloudUsable()) {
      steps.push({ label: this.cloudName(), detail: 'Only when your phone cannot build it' });
    }
    return steps;
  }

  /** The existing rotating examples, without their "Try: " prefix. */
  private suggestions(): string[] {
    return PLACEHOLDERS.map((p: string) => p.replace(/^Try: /, ''));
  }

  /** Home "Recent": the four newest capsules as live mini widgets; "See all" opens the Capsules tab. */
  @Builder
  recentSection() {
    Column({ space: 12 }) {
      Row() {
        Text('Recent')
          .fontSize(Flags.NEW_CREATE_CLASSIC ? 17 : $r('sys.float.Subtitle_L'))
          .fontWeight(Flags.NEW_CREATE_CLASSIC ? 700 : FontWeight.Bold)
          .fontColor(Flags.NEW_CREATE_CLASSIC ? Palette.text : $r('sys.color.font_primary'))
          .layoutWeight(1)
        if (this.entries.length > 0) {
          Text('See all')
            .fontSize(Flags.NEW_CREATE_CLASSIC ? 15 : $r('sys.float.Body_M'))
            .fontColor(Flags.NEW_CREATE_CLASSIC ? Palette.blue : $r('sys.color.brand'))
            .fontWeight(FontWeight.Medium)
            .onClick(() => this.selectTab(TAB_CAPSULES))
        }
      }
      .width('100%')
      if (this.entries.length === 0) {
        Text('Your capsules will appear here')
          .fontSize(Flags.NEW_CREATE_CLASSIC ? 15 : $r('sys.float.Body_M'))
          .fontColor(Flags.NEW_CREATE_CLASSIC ? Palette.text2 : $r('sys.color.font_tertiary'))
          .width('100%')
      } else {
        Grid() {
          ForEach(this.entries.slice(0, 4), (entry: CapsuleEntry) => {
            GridItem() {
              Column({ space: 8 }) {
                MiniPreview({ runtime: entry.runtime })
                Text(entry.capsule.name)
                  .fontSize(Flags.NEW_CREATE_CLASSIC ? 15 : $r('sys.float.Body_M'))
                  .fontWeight(Flags.NEW_CREATE_CLASSIC ? 600 : FontWeight.Medium)
                  .fontColor(Flags.NEW_CREATE_CLASSIC ? Palette.text : $r('sys.color.font_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
              }
              .onClick(() => this.open(entry.capsule.id))
            }
          }, (entry: CapsuleEntry) => `${entry.capsule.id}-${entry.runtime.serial}`)
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(12)
        .rowsGap(16)
        .width('100%')
        .maxCount(2)
        .layoutDirection(GridDirection.Row)
      }
    }
    .width('100%')
    .margin({ top: 8 })
  }

  /** UI-2: the Capsules tab (live previews come with UI-3). */
  @Builder
  capsulesTab() {
    Scroll() {
      Column({ space: 16 }) {
        Row({ space: 8 }) {
          Text('Capsules')
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
          if (this.entries.length > 0) {
            Text(`${this.entries.length}`)
              .fontSize($r('sys.float.Body_L'))
              .fontColor($r('sys.color.font_tertiary'))
          }
          Blank()
          // Import from another phone (moved here from the home header). Nothing is saved until the sheet's Run.
          SharingBar({
            showShare: false,
            compact: true,
            onPairCode: (code: string) => this.claimDevice(code), // a scanned device pairing QR
            onImported: (prepared: PreparedImport) => this.handleImported(prepared)
          })
        }
        .width('100%')
        .margin({ top: 4 })
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
      .padding({ left: 16, right: 16, top: 12, bottom: 120 })
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .edgeEffect(EdgeEffect.Spring)
    .scrollBar(BarState.Off)
  }

  /** Redesign (NEW_CAPSULES): page title, the existing import, and a grid of live tiles. */
  @Builder
  capsulesTabNew() {
    Scroll() {
      Column({ space: 14 }) {
        Row({ space: 8 }) {
          Text('Capsules')
            .fontSize(28)
            .fontWeight(800)
            .fontColor(Palette.text)
          if (this.entries.length > 0) {
            Text(`${this.entries.length}`)
              .fontSize(15)
              .fontWeight(600)
              .fontColor(Palette.text2)
          }
          Blank()
          // Import from another phone. Nothing is saved until the sheet's Run.
          SharingBar({
            showShare: false,
            compact: true,
            onPairCode: (code: string) => this.claimDevice(code),
            onImported: (prepared: PreparedImport) => this.handleImported(prepared)
          })
        }
        .width('100%')
        if (this.entries.length === 0) {
          EmptyState({ title: 'Capsules you create appear here.', action: 'Create one',
            onAction: () => this.selectTab(TAB_CREATE) })
        } else {
          Grid() {
            ForEach(this.entries, (entry: CapsuleEntry) => {
              GridItem() {
                CapsuleTile({
                  name: entry.capsule.name,
                  icon: capsuleIcon(entry.capsule),
                  value: entry.runtime.summary(),
                  originText: originBadge(entry.origin),
                  originKind: originKindOf(entry.origin),
                  widget: entry.route.widget,
                  onOpen: () => this.open(entry.capsule.id)
                })
              }
            }, (entry: CapsuleEntry) => `${entry.capsule.id}-${entry.runtime.serial}`)
          }
          .columnsTemplate(this.wide ? '1fr 1fr 1fr' : '1fr 1fr')
          .columnsGap(10)
          .rowsGap(10)
          .width('100%')
          .layoutDirection(GridDirection.Row)
        }
      }
      .padding({ left: 16, right: 16, top: 16, bottom: 120 })
      .width('100%')
      .constraintSize({ maxWidth: this.wide ? 960 : undefined })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .edgeEffect(EdgeEffect.Spring)
    .scrollBar(BarState.Off)
  }

  private selectTab(index: number): void {
    this.tabTaps = this.tabTaps.map((n: number, i: number) => i === index ? n + 1 : n);
    this.tab = index;
    this.tabsController.changeIndex(index);
  }

  /** UI-2: one item of the floating tab bar: an HM Symbol that bounces when tapped, and a short label. */
  @Builder
  tabItem(index: number, icon: Resource, label: string) {
    Column({ space: 2 }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([this.tab === index ? $r('sys.color.brand') : $r('sys.color.icon_secondary')])
        .symbolEffect(new BounceSymbolEffect(EffectScope.WHOLE, EffectDirection.DOWN), this.tabTaps[index])
      Text(label)
        .fontSize(10)
        .fontWeight(this.tab === index ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.tab === index ? $r('sys.color.brand') : $r('sys.color.font_secondary'))
        .maxLines(1)
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .accessibilityText(label)
    .onClick(() => this.selectTab(index))
  }

  /** UI-2: a floating, frosted pill above the home indicator. */
  @Builder
  tabBar() {
    Row() {
      this.tabItem(TAB_CREATE, $r('sys.symbol.plus_circle'), 'Create')
      this.tabItem(TAB_CAPSULES, $r('sys.symbol.square_grid_2x2'), 'Capsules')
      this.tabItem(TAB_MARKET, $r('sys.symbol.bag'), 'Marketplace')
      this.tabItem(TAB_SETTINGS, $r('sys.symbol.gearshape'), 'Settings')
    }
    .width('92%')
    .height(64)
    .padding({ left: 6, right: 6 })
    .borderRadius(32)
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
    .shadow({ radius: 24, color: '#1F000000', offsetY: 6 })
    .margin({ bottom: 12 })
  }

  @Builder
  mainTabs() {
    Stack({ alignContent: Alignment.Bottom }) {
      // Native Tabs hold the pages; their own bar is hidden in favour of the floating pill below.
      Tabs({ barPosition: BarPosition.End, controller: this.tabsController, index: this.tab }) {
        TabContent() {
          if (Flags.NEW_CREATE) {
            this.createTab()
          } else {
            this.home()
          }
        }
        TabContent() {
          if (Flags.NEW_CAPSULES) {
            this.capsulesTabNew()
          } else {
            this.capsulesTab()
          }
        }
        TabContent() {
          MarketplaceView({
            client: this.market,
            embedded: true,
            wide: this.wide,
            onDeviceOnly: this.settings.aiMode === 'on-device',
            onOpenSettings: () => this.selectTab(TAB_SETTINGS),
            onInstall: (item: MarketItem) => this.installFromMarket(item)
          })
        }
        TabContent() {
          SettingsView({
            settings: this.settings,
            embedded: true,
            cloudStatus: this.cloudConfigured ? '' : this.modelStatus,
            smartDetail: this.smartModeDetail(),
            onMotionScopeChange: () => this.syncMotion()
          })
        }
      }
      .barHeight(0)
      .scrollable(false)
      .animationDuration(reduceMotion() ? 0 : 250)
      .onChange((index: number) => {
        this.tab = index;
      })
      .width('100%')
      .height('100%')
      if (Flags.NEW_SHELL) {
        TabBar({
          items: TAB_ITEMS,
          selected: this.tab,
          taps: this.tabTaps,
          onSelect: (i: number) => this.selectTab(i)
        })
          .margin({ left: 16, right: 16, bottom: 12 })
          .constraintSize({ maxWidth: this.wide ? 640 : undefined })
      } else {
        this.tabBar()
      }
    }
    .width('100%')
    .height('100%')
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
          CapsuleView({
            runtime: entry.runtime,
            motionNote: this.motionNoteFor(entry.capsule),
            onPickCity: () => this.openCityPicker(entry.capsule.id)
          })
          this.changeCard(entry)
          if ((entry.capsule.triggers ?? []).length > 0) {
            TriggerCard({
              triggers: entry.capsule.triggers ?? [],
              allowed: this.triggersAllowed(entry),
              now: this.triggerNow,
              onRunNow: (i: number) => this.runTriggerNow(entry, i),
              onEditTime: (i: number) => this.editTriggerTime(entry, i),
              onRemove: (i: number) => this.removeTrigger(entry, i)
            })
          }
          if (this.canMakeSmarter(entry)) {
            this.smarterButton(entry)
          }
          // PROTECTED: owned by T4. Do not remove or modify. See /tmp/hy-tasks.
          // Adds exactly this capsule (its id) to the home screen; scripts/check-add-to-home.sh checks this mount.
          AddToHomeButton({ capsuleId: entry.capsule.id, capsuleName: entry.capsule.name })
          if (this.devicesEnabled && payloadFor(entry.capsule) !== null) {
            DevicePanel({
              devices: this.devices,
              simulated: this.relaySimulated,
              status: this.deviceCapsuleId === entry.capsule.id ? this.deviceStatus : '',
              onPairScan: () => this.pairScan(),
              onPairPhrase: (phrase: string) => this.claimDevice(phrase),
              onShow: (id: string) => this.showOnDevice(entry, id),
              onUnpair: (id: string) => this.unpairDevice(id)
            })
          }
          // Share only: importing lives on the home screen.
          SharingBar({ capsule: entry.capsule, showImport: false })
          if (this.marketConfigured) {
            if (this.publishedIds.includes(entry.capsule.id)) {
              Row({ space: 8 }) {
                Text('In the marketplace')
                  .fontSize($r('sys.float.Body_M'))
                  .fontColor($r('sys.color.font_secondary'))
                Button('Remove from marketplace', { buttonStyle: ButtonStyleMode.TEXTUAL })
                  .onClick(() => this.unpublishFromMarket(entry))
              }
            } else {
              Button('Publish to marketplace', { buttonStyle: ButtonStyleMode.TEXTUAL })
                .onClick(() => this.publishToMarket(entry))
            }
          }
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

  /** Redesign (NEW_FRAME): the open capsule inside CapsuleFrame. Same parts as detail(), restyled. */
  @Builder
  frameDetail(entry: CapsuleEntry) {
    Column() {
      CapsuleFrame({
        name: entry.capsule.name,
        icon: capsuleIcon(entry.capsule),
        originText: originBadge(entry.origin),
        originKind: originKindOf(entry.origin),
        wide: this.wide,
        hasSidePanel: this.frameHasSide(),
        onClose: () => this.close(),
        onChangeIt: () => {
          this.changeOpenId = this.changeOpenId === entry.capsule.id ? '' : entry.capsule.id;
        },
        onShare: () => this.shareFromFrame(entry),
        body: () => {
          this.frameBody(entry)
        },
        sidePanel: () => {
          this.frameSide(entry)
        },
        addToHome: () => {
          this.frameAddToHome(entry)
        }
      })
    }
    .width('100%')
    .height('100%')
    .padding({ top: 8 })
    .geometryTransition(entry.capsule.id)
    .transition(TransitionEffect.OPACITY)
  }

  @Builder
  frameBody(entry: CapsuleEntry) {
    // "Change it…" (footer pill) opens here, at the top, so it is seen at once.
    if (this.changeOpenId === entry.capsule.id || this.undoIds.includes(entry.capsule.id) ||
      (this.changeId === entry.capsule.id &&
        (this.changeBusy || this.changeSummary.length > 0 || this.changeIssue.length > 0))) {
      this.changeCard(entry)
    }
    CapsuleView({
      runtime: entry.runtime,
      motionNote: this.motionNoteFor(entry.capsule),
      onPickCity: () => this.openCityPicker(entry.capsule.id)
    })
    // Wide windows (NEW_WIDE): the rest goes in the frame's side panel (frameExtras), next to the capsule.
    if (!this.frameHasSide()) {
      this.frameExtras(entry)
    }
  }

  /** The side panel on wide windows: the frame extras, stacked. */
  @Builder
  frameSide(entry: CapsuleEntry) {
    Column({ space: 12 }) {
      this.frameExtras(entry)
    }
    .width('100%')
  }

  /** Triggers, Make it smarter, devices, share, publish, remove and the log: under the capsule, or beside it. */
  @Builder
  frameExtras(entry: CapsuleEntry) {
    if ((entry.capsule.triggers ?? []).length > 0) {
      TriggerCard({
        triggers: entry.capsule.triggers ?? [],
        allowed: this.triggersAllowed(entry),
        now: this.triggerNow,
        onRunNow: (i: number) => this.runTriggerNow(entry, i),
        onEditTime: (i: number) => this.editTriggerTime(entry, i),
        onRemove: (i: number) => this.removeTrigger(entry, i)
      })
    }
    if (this.canMakeSmarter(entry)) {
      this.smarterButton(entry)
    }
    if (this.devicesEnabled && payloadFor(entry.capsule) !== null) {
      DevicePanel({
        devices: this.devices,
        simulated: this.relaySimulated,
        status: this.deviceCapsuleId === entry.capsule.id ? this.deviceStatus : '',
        onPairScan: () => this.pairScan(),
        onPairPhrase: (phrase: string) => this.claimDevice(phrase),
        onShow: (id: string) => this.showOnDevice(entry, id),
        onUnpair: (id: string) => this.unpairDevice(id)
      })
    }
    // Share only (with "Show as QR code"); the footer's Share opens the same share panel.
    SharingBar({ capsule: entry.capsule, showImport: false })
    if (this.marketConfigured) {
      if (this.publishedIds.includes(entry.capsule.id)) {
        Row({ space: 8 }) {
          Text('In the marketplace')
            .fontSize($r('sys.float.Body_M'))
            .fontColor($r('sys.color.font_secondary'))
          Button('Remove from marketplace', { buttonStyle: ButtonStyleMode.TEXTUAL })
            .onClick(() => this.unpublishFromMarket(entry))
        }
      } else {
        Button('Publish to marketplace', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .onClick(() => this.publishToMarket(entry))
      }
    }
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
    Row() {
      Button('Activity log', { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
        .onClick(() => this.nav.pushPath({ name: LOG_PAGE }))
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  /** The frame footer's slot for T4's button, mounted exactly as T4 provides it. */
  @Builder
  frameAddToHome(entry: CapsuleEntry) {
    // PROTECTED: owned by T4. Do not remove or modify. See /tmp/hy-tasks.
    AddToHomeButton({ capsuleId: entry.capsule.id, capsuleName: entry.capsule.name })
  }

  /** System back on an open capsule closes it (redesign frame); pushed pages and the tabs behave as before. */
  onBackPress(): boolean {
    if (Flags.NEW_FRAME && this.nav.size() === 0 && this.openEntry() !== undefined) {
      this.close();
      return true;
    }
    return false;
  }

  /** Footer Share: the same share panel as SharingBar; if it can't open, point to "Show as QR code". */
  private shareFromFrame(entry: CapsuleEntry): void {
    if (!this.ctx) {
      return;
    }
    shareCapsule(this.ctx, entry.capsule).catch(() => {
      this.toast("Couldn't open the share panel. Use Show as QR code below.");
    });
  }

  build() {
    Navigation(this.nav) {
      Stack({ alignContent: Alignment.Top }) {
        if (Flags.NEW_THEME) {
          // The one gradient: 360vp at the top, #DCE5FF into the page background.
          Column()
            .width('100%')
            .height(360)
            .linearGradient({ direction: GradientDirection.Bottom, colors: [[Palette.gradientTop, 0], [Palette.bg, 1]] })
            .hitTestBehavior(HitTestMode.None)
            // Background layer only: runs under the status bar; content stays in the safe area.
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        }
        if (this.openEntry()) {
          if (Flags.NEW_FRAME) {
            this.frameDetail(this.openEntry() as CapsuleEntry)
          } else {
            this.detail(this.openEntry() as CapsuleEntry)
          }
        } else {
          this.mainTabs()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Flags.NEW_THEME ? Palette.bg : $r('sys.color.background_secondary'))
      .onAreaChange((o: Area, n: Area) => {
        storeWidthClass(n.width as number);
        this.wide = Flags.NEW_WIDE && (n.width as number) >= 600;
      })
      // One sheet only: ArkUI keeps the last bindSheet on a node, so the consent sheet and the city picker
      // must share this single binding (the builder branches on cityPickerId).
      .bindSheet(this.showSheet || this.cityPickerId.length > 0, this.sheetBody(), {
        height: this.cityPickerId.length > 0 ? 520 : SheetSize.FIT_CONTENT,
        dragBar: true,
        // Still the one sheet binding on this node (never add a second); only its look changes.
        backgroundColor: Flags.NEW_CONSENT ? Palette.surface : $r('sys.color.background_secondary'),
        radius: Flags.NEW_CONSENT ? { topLeft: 28, topRight: 28 } : undefined,
        onDisappear: () => {
          this.cityPickerId = '';
          if (this.pending) {
            this.cancelPending();
          }
        }
      })
    }
    .hideTitleBar(true)
    .backgroundColor(Flags.NEW_THEME ? Palette.bg : $r('sys.color.background_secondary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .mode(NavigationMode.Stack)
    .navDestination(this.pageMap)
  }
}
