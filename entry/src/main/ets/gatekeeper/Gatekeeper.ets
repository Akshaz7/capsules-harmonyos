import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { allComponents } from '../core/CapsuleProgram';
import {
  Capsule,
  CapsuleComponent,
  ButtonComponent,
  ButtonStep,
  ParsedAction,
  Permission,
  parseAction,
  permissionForAction,
  permissionForComponent
} from '../core';
import { canSendToDevice, grantsWith, grantsWithout } from '../core/Consent';

const DOMAIN = 0x0001;
const TAG = 'Gatekeeper';
const STORE = 'gatekeeper';
const LOG_KEY = 'log';
const MAX_LOG = 200;

export type LogKind = 'allow' | 'deny' | 'blocked' | 'undo';

export interface LogEntry {
  time: number;
  capsuleId: string;
  kind: LogKind;
  detail: string;
}

@ObservedV2
export class GateLog {
  @Trace entries: LogEntry[] = [];
}

/**
 * Decides what a capsule may do. A permission is usable only if the capsule declares it
 * AND the user allowed it on the consent screen. Anything else is blocked and logged.
 * Grants and the log persist in Preferences.
 */
export class Gatekeeper {
  readonly log: GateLog = new GateLog();
  private prefs: preferences.Preferences;

  constructor(ctx: common.Context) {
    const options: preferences.Options = { name: STORE };
    this.prefs = preferences.getPreferencesSync(ctx, options);
    const raw = this.get(LOG_KEY, '[]') as string;
    try {
      this.log.entries = JSON.parse(raw) as LogEntry[];
    } catch (e) {
      this.log.entries = [];
    }
  }

  /** True once the user has answered the consent screen for this capsule. */
  hasDecided(capsuleId: string): boolean {
    return this.get(`decided:${capsuleId}`, false) as boolean;
  }

  isRemoved(capsuleId: string): boolean {
    return this.get(`removed:${capsuleId}`, false) as boolean;
  }

  grants(capsuleId: string): string[] {
    const empty: string[] = [];
    return this.get(`grants:${capsuleId}`, empty) as string[];
  }

  /** Stores the consent answers. `allowed` must be a subset of capsule.permissions. */
  decide(capsule: Capsule, allowed: Permission[]): void {
    const granted: string[] = capsule.permissions.filter((p: Permission) => allowed.includes(p));
    this.put(`grants:${capsule.id}`, granted);
    this.put(`decided:${capsule.id}`, true);
    this.remove(`removed:${capsule.id}`);
    capsule.permissions.forEach((p: Permission) => {
      const ok = granted.includes(p);
      this.add(capsule.id, ok ? 'allow' : 'deny', `${p} ${ok ? 'allowed' : 'denied'} by user`);
    });
    this.save();
  }

  isAllowed(capsule: Capsule, p: Permission): boolean {
    return capsule.permissions.includes(p) && this.grants(capsule.id).includes(p);
  }

  /**
   * Returns, for each component in allComponents(capsule.ui) order (so a timer nested in a v1
   * when/row is checked too), '' if it may render or the reason it is blocked.
   * Every blocked component is logged.
   */
  checkComponents(capsule: Capsule): string[] {
    const all = allComponents(capsule.ui);
    const reasons = all.map((c: CapsuleComponent) => this.componentBlockReason(capsule, c));
    reasons.forEach((r: string, i: number) => {
      if (r.length > 0) {
        this.add(capsule.id, 'blocked', `component ${i} (${all[i].type}): ${r}`);
      }
    });
    this.save();
    return reasons;
  }

  /** True if the action may run; otherwise logs it and returns false. */
  allowAction(capsule: Capsule, action: string): boolean {
    const reason = this.actionBlockReason(capsule, action);
    if (reason.length === 0) {
      return true;
    }
    this.add(capsule.id, 'blocked', `action ${action}: ${reason}`);
    this.save();
    return false;
  }

  /**
   * "devices" (T4-13): true once the user allowed sending this capsule to a paired device. Until then the app
   * asks (once); the answer is stored with allowDevices / denyDevices and undone with revoke or forget.
   */
  canSendToDevice(capsuleId: string): boolean {
    return canSendToDevice(this.grants(capsuleId));
  }

  /** The user allowed "devices" for this capsule: later sends do not ask again. Logged. */
  allowDevices(capsuleId: string, detail: string): void {
    this.put(`grants:${capsuleId}`, grantsWith(this.grants(capsuleId), 'devices'));
    this.add(capsuleId, 'allow', `devices allowed by user: ${detail}`);
    this.save();
  }

  /** The user refused "devices" for this capsule: nothing is sent. Logged; the app may ask again next time. */
  denyDevices(capsuleId: string, detail: string): void {
    this.put(`grants:${capsuleId}`, grantsWithout(this.grants(capsuleId), 'devices'));
    this.add(capsuleId, 'deny', `devices denied by user: ${detail}`);
    this.save();
  }

  /** Undoes one permission for a capsule (e.g. "devices" from the log screen). Logged as an undo. */
  revoke(capsuleId: string, p: Permission): void {
    this.put(`grants:${capsuleId}`, grantsWithout(this.grants(capsuleId), p));
    this.add(capsuleId, 'undo', `${p} revoked by user`);
    this.save();
  }

  /** Logs a "Show on another device" send ('allow') or a refusal ('blocked'): every send is on the record. */
  logDeviceSend(capsuleId: string, sent: boolean, detail: string): void {
    this.add(capsuleId, sent ? 'allow' : 'blocked', detail);
    this.save();
  }

  /** Forgets the capsule's grants and marks it removed. */
  forget(capsuleId: string, detail: string): void {
    this.remove(`grants:${capsuleId}`);
    this.remove(`decided:${capsuleId}`);
    this.put(`removed:${capsuleId}`, true);
    this.add(capsuleId, 'undo', detail);
    this.save();
  }

  private componentBlockReason(capsule: Capsule, c: CapsuleComponent): string {
    const p = permissionForComponent(c);
    if (p !== null && !this.isAllowed(capsule, p)) {
      return this.missing(capsule, p);
    }
    if (c.type === 'button') {
      // A v1 button may have no action ('') and run v0 actions as plain-string do-steps instead.
      const b = c as ButtonComponent;
      const actions: string[] = b.action.length > 0 ? [b.action] : [];
      (b.do ?? []).forEach((step: ButtonStep) => {
        if (typeof step === 'string') {
          actions.push(step as string);
        }
      });
      for (const action of actions) {
        const reason = this.actionBlockReason(capsule, action);
        if (reason.length > 0) {
          return reason;
        }
      }
    }
    return '';
  }

  private actionBlockReason(capsule: Capsule, action: string): string {
    const parsed: ParsedAction | null = parseAction(action);
    if (parsed === null) {
      return 'unknown action';
    }
    const p = permissionForAction(parsed);
    if (p !== null && !this.isAllowed(capsule, p)) {
      return this.missing(capsule, p);
    }
    return '';
  }

  private missing(capsule: Capsule, p: Permission): string {
    return capsule.permissions.includes(p) ? `needs ${p} (denied by user)` : `needs ${p} (not declared)`;
  }

  private add(capsuleId: string, kind: LogKind, detail: string): void {
    const entry: LogEntry = { time: Date.now(), capsuleId: capsuleId, kind: kind, detail: detail };
    hilog.info(DOMAIN, TAG, '%{public}s %{public}s: %{public}s', kind, capsuleId, detail);
    const next = [entry].concat(this.log.entries);
    this.log.entries = next.length > MAX_LOG ? next.slice(0, MAX_LOG) : next;
  }

  private save(): void {
    this.put(LOG_KEY, JSON.stringify(this.log.entries));
    this.prefs.flush().catch((e: BusinessError) => {
      hilog.error(DOMAIN, TAG, 'flush failed: %{public}d %{public}s', e.code, e.message);
    });
  }

  private get(key: string, def: preferences.ValueType): preferences.ValueType {
    try {
      return this.prefs.getSync(key, def);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'get %{public}s failed: %{public}s', key, (e as BusinessError).message);
      return def;
    }
  }

  private put(key: string, value: preferences.ValueType): void {
    try {
      this.prefs.putSync(key, value);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'put %{public}s failed: %{public}s', key, (e as BusinessError).message);
    }
  }

  private remove(key: string): void {
    try {
      this.prefs.deleteSync(key);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'delete %{public}s failed: %{public}s', key, (e as BusinessError).message);
    }
  }
}
