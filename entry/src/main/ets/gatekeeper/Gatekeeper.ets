import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  Capsule,
  CapsuleComponent,
  ButtonComponent,
  ParsedAction,
  Permission,
  parseAction,
  permissionForAction,
  permissionForComponent
} from '../core';

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
   * Returns, for each ui component, '' if it may render or the reason it is blocked.
   * Every blocked component is logged.
   */
  checkComponents(capsule: Capsule): string[] {
    const reasons = capsule.ui.map((c: CapsuleComponent) => this.componentBlockReason(capsule, c));
    reasons.forEach((r: string, i: number) => {
      if (r.length > 0) {
        this.add(capsule.id, 'blocked', `ui[${i}] ${capsule.ui[i].type}: ${r}`);
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
      return this.actionBlockReason(capsule, (c as ButtonComponent).action);
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
