/**
 * "Show on another device": the app side of the device relay (esp32-companion/README.md, "For the app:
 * sending a capsule to another device"). The app never talks to a board directly. Only the capsule type,
 * its label and one number leave the phone. Every call has a short timeout and never throws: the capsule
 * keeps working on the phone whatever the relay does. The gatekeeper decides whether anything is sent.
 */
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Capsule, CapsuleComponent, CounterComponent, TimerComponent, allComponents } from '../core';
import { TOKEN_HEADER } from './InstallToken';

const DOMAIN = 0x0001;
const TAG = 'DeviceRelay';

export const LABEL_MAX_BYTES = 47;
export const MAX_SECONDS = 359999;
export const MAX_COUNT = 999999;
/** A device not heard from for longer than this is offline. */
export const OFFLINE_AFTER_MS = 15000;
const TIMEOUT_MS = 4000;

export type DeviceAction = 'start' | 'pause' | 'toggle' | 'reset' | 'increment';

/** What is sent: a timer or a counter, a label and one number. Nothing else. */
export interface DevicePayload {
  type: 'timer' | 'counter';
  label: string;
  seconds?: number;
  count?: number;
}

export interface PairedDevice {
  id: string;
  kind: string; // "wrist" (the board) or "web" (a browser tab)
}

export interface DeviceState {
  type: string;
  label: string;
  count: number;
  seconds: number;
  remaining_seconds: number;
  running: boolean;
  done: boolean;
  version: number;
  last_seen_ms_ago: number;
}

export interface ClaimResult {
  device?: PairedDevice;
  error?: string;
}

// ---- Pure helpers (unit tested) ----

/** A pairing code: three words of letters, any case, hyphens or spaces between. Normalised, or ''. */
export function normalizePairCode(text: string): string {
  const words = text.trim().split(/[\s-]+/).filter((w: string) => w.length > 0);
  if (words.length !== 3 || words.some((w: string) => !/^[A-Za-z]+$/.test(w))) {
    return '';
  }
  return words.map((w: string) => w.toLowerCase()).join('-');
}

/** The code from a scanned pairing QR (https://<host>/pair?code=...), or '' if the text is anything else. */
export function pairCodeFromQr(text: string): string {
  const m = text.trim().match(/^https?:\/\/[^\/?#\s]+(\/[^?#\s]*)?\?([^#\s]*)/i);
  if (m === null || (m[1] ?? '').replace(/\/+$/, '') !== '/pair') {
    return '';
  }
  for (const part of m[2].split('&')) {
    const eq = part.indexOf('=');
    if (eq > 0 && part.substring(0, eq) === 'code') {
      try {
        return normalizePairCode(decodeURIComponent(part.substring(eq + 1).replace(/\+/g, ' ')));
      } catch (e) {
        return '';
      }
    }
  }
  return '';
}

function utf8Bytes(codePoint: number): number {
  return codePoint < 0x80 ? 1 : codePoint < 0x800 ? 2 : codePoint < 0x10000 ? 3 : 4;
}

/** Cuts text to at most `maxBytes` of UTF-8, never inside a character. */
export function cutUtf8(text: string, maxBytes: number): string {
  let bytes = 0;
  let out = '';
  for (const ch of text) {
    const n = utf8Bytes(ch.codePointAt(0) ?? 0);
    if (bytes + n > maxBytes) {
      break;
    }
    bytes += n;
    out += ch;
  }
  return out;
}

function clamp(n: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, Math.round(n)));
}

/**
 * What a capsule shows on another device: its first timer, else its first counter (with `counterValue`, the
 * phone's current count, when known). null when it has neither: only timers and counters can be sent.
 */
export function payloadFor(capsule: Capsule, counterValue?: number): DevicePayload | null {
  const all = allComponents(capsule.ui);
  const timer = all.find((c: CapsuleComponent) => c.type === 'timer') as TimerComponent | undefined;
  if (timer !== undefined) {
    const p: DevicePayload = {
      type: 'timer',
      label: cutUtf8(timer.label || capsule.name, LABEL_MAX_BYTES),
      seconds: clamp(timer.minutes * 60, 1, MAX_SECONDS)
    };
    return p;
  }
  const counter = all.find((c: CapsuleComponent) => c.type === 'counter') as CounterComponent | undefined;
  if (counter !== undefined) {
    const p: DevicePayload = {
      type: 'counter',
      label: cutUtf8(counter.label || capsule.name, LABEL_MAX_BYTES),
      count: clamp(counterValue ?? 0, 0, MAX_COUNT)
    };
    return p;
  }
  return null;
}

function num(v: Object | undefined): number {
  return typeof v === 'number' && Number.isFinite(v) ? v : 0;
}

/** Parses GET /state. null if it isn't the expected object. */
export function parseDeviceState(body: string): DeviceState | null {
  try {
    const o = JSON.parse(body) as Record<string, Object>;
    if (o === null || typeof o !== 'object' || typeof o['version'] !== 'number') {
      return null;
    }
    const s: DeviceState = {
      type: typeof o['type'] === 'string' ? o['type'] as string : '',
      label: typeof o['label'] === 'string' ? o['label'] as string : '',
      count: num(o['count']),
      seconds: num(o['seconds']),
      remaining_seconds: num(o['remaining_seconds']),
      running: o['running'] === true,
      done: o['done'] === true,
      version: num(o['version']),
      last_seen_ms_ago: typeof o['last_seen_ms_ago'] === 'number' ? o['last_seen_ms_ago'] as number : Infinity
    };
    return s;
  } catch (e) {
    return null;
  }
}

/** A state from before our last send (its `version` is older): ignore it. */
export function isStaleState(s: DeviceState, lastSentVersion: number): boolean {
  return s.version < lastSentVersion;
}

export function isOffline(s: DeviceState): boolean {
  return s.last_seen_ms_ago > OFFLINE_AFTER_MS;
}

/** The message of a relay error body {"error":{"code","message"}}, else a short status text. */
export function relayErrorMessage(status: number, body: string): string {
  try {
    const o = JSON.parse(body) as Record<string, Object>;
    const e = o['error'] as Record<string, Object> | undefined;
    if (e !== undefined && typeof e['message'] === 'string') {
      return e['message'] as string;
    }
  } catch (err) {
    // not JSON
  }
  return status === 0 ? 'The relay did not answer' : `The relay answered ${status}`;
}

/** Friendly text for a failed claim. */
export function claimErrorText(status: number, body: string): string {
  if (status === 404) {
    return "That code isn't valid any more. Check the device for a new one.";
  }
  if (status === 429) {
    return 'Too many tries. Wait a minute and try again.';
  }
  return relayErrorMessage(status, body);
}

// ---- The relay ----

export interface DeviceRelay {
  /** True for the in-app simulation (no relay configured). The UI must say so. */
  readonly simulated: boolean;
  claim(code: string): Promise<ClaimResult>;
  /** Shows the payload on the device; returns the new version, or -1. */
  send(deviceId: string, payload: DevicePayload): Promise<number>;
  action(deviceId: string, action: DeviceAction): Promise<boolean>;
  state(deviceId: string): Promise<DeviceState | null>;
  unpair(deviceId: string): Promise<boolean>;
}

interface ClaimBody {
  code: string;
}

interface ActionBody {
  action: string;
}

function claimBody(code: string): ClaimBody {
  const b: ClaimBody = { code: code };
  return b;
}

function actionBody(action: DeviceAction): ActionBody {
  const b: ActionBody = { action: action };
  return b;
}

interface Reply {
  status: number; // 0 = no answer
  body: string;
}

export class HttpDeviceRelay implements DeviceRelay {
  readonly simulated: boolean = false;
  private base: string;
  private token: string;

  constructor(baseUrl: string, token: string) {
    this.base = baseUrl.replace(/\/+$/, '');
    this.token = token;
  }

  private async call(method: http.RequestMethod, path: string, body?: string): Promise<Reply> {
    let req: http.HttpRequest | null = null;
    try {
      req = http.createHttp();
      const headers: Record<string, string> = { 'Content-Type': 'application/json' };
      headers[TOKEN_HEADER] = this.token;
      const resp = await req.request(`${this.base}${path}`, {
        method: method,
        header: headers,
        extraData: body,
        connectTimeout: TIMEOUT_MS,
        readTimeout: TIMEOUT_MS,
        expectDataType: http.HttpDataType.STRING
      });
      const r: Reply = { status: resp.responseCode, body: typeof resp.result === 'string' ? resp.result : '' };
      if (r.status >= 400) {
        hilog.warn(DOMAIN, TAG, '%{public}s %{public}s -> %{public}d %{public}s', method, path.split('/')[2] ?? '',
          r.status, relayErrorMessage(r.status, r.body));
      }
      return r;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'relay unreachable: %{public}s', (e as BusinessError).message);
      const r: Reply = { status: 0, body: '' };
      return r;
    } finally {
      req?.destroy();
    }
  }

  async claim(code: string): Promise<ClaimResult> {
    const r = await this.call(http.RequestMethod.POST, '/api/devices/claim', JSON.stringify(claimBody(code)));
    if (r.status !== 200) {
      const failed: ClaimResult = { error: claimErrorText(r.status, r.body) };
      return failed;
    }
    try {
      const o = JSON.parse(r.body) as Record<string, Object>;
      if (typeof o['id'] === 'string') {
        const ok: ClaimResult = { device: { id: o['id'] as string, kind: typeof o['kind'] === 'string' ? o['kind'] as string : '' } };
        return ok;
      }
    } catch (e) {
      // fall through
    }
    const bad: ClaimResult = { error: 'The relay sent an answer the app does not understand' };
    return bad;
  }

  async send(deviceId: string, payload: DevicePayload): Promise<number> {
    const r = await this.call(http.RequestMethod.PUT, `/api/devices/${encodeURIComponent(deviceId)}/capsule`,
      JSON.stringify(payload));
    if (r.status !== 200) {
      return -1;
    }
    try {
      const o = JSON.parse(r.body) as Record<string, Object>;
      return typeof o['version'] === 'number' ? o['version'] as number : -1;
    } catch (e) {
      return -1;
    }
  }

  async action(deviceId: string, action: DeviceAction): Promise<boolean> {
    const r = await this.call(http.RequestMethod.POST, `/api/devices/${encodeURIComponent(deviceId)}/action`,
      JSON.stringify(actionBody(action)));
    return r.status === 200;
  }

  async state(deviceId: string): Promise<DeviceState | null> {
    const r = await this.call(http.RequestMethod.GET, `/api/devices/${encodeURIComponent(deviceId)}/state`);
    return r.status === 200 ? parseDeviceState(r.body) : null;
  }

  async unpair(deviceId: string): Promise<boolean> {
    const r = await this.call(http.RequestMethod.DELETE, `/api/devices/${encodeURIComponent(deviceId)}`);
    return r.status === 200 || r.status === 204;
  }
}

/** In-app simulation used when no relay is configured. Clearly labelled as simulated in the UI. */
export class SimulatedDeviceRelay implements DeviceRelay {
  readonly simulated: boolean = true;
  private current: DeviceState | null = null;
  private version: number = 0;
  private sentAt: number = 0;

  async claim(code: string): Promise<ClaimResult> {
    if (normalizePairCode(code).length === 0) {
      const bad: ClaimResult = { error: claimErrorText(404, '') };
      return bad;
    }
    const ok: ClaimResult = { device: { id: 'sim-device', kind: 'web' } };
    return ok;
  }

  async send(deviceId: string, payload: DevicePayload): Promise<number> {
    this.version++;
    this.sentAt = Date.now();
    this.current = {
      type: payload.type, label: payload.label, count: payload.count ?? 0, seconds: payload.seconds ?? 0,
      remaining_seconds: payload.seconds ?? 0, running: payload.type === 'timer', done: false,
      version: this.version, last_seen_ms_ago: 0
    };
    return this.version;
  }

  async action(deviceId: string, action: DeviceAction): Promise<boolean> {
    const s = this.current;
    if (s === null) {
      return false;
    }
    if (action === 'increment' && s.type === 'counter') {
      s.count = Math.min(MAX_COUNT, s.count + 1);
    } else if (action === 'reset') {
      s.count = 0;
      s.remaining_seconds = s.seconds;
    } else if (action === 'start') {
      s.running = true;
    } else if (action === 'pause') {
      s.running = false;
    } else if (action === 'toggle') {
      s.running = !s.running;
    }
    return true;
  }

  async state(deviceId: string): Promise<DeviceState | null> {
    const s = this.current;
    if (s === null) {
      return null;
    }
    if (s.type === 'timer' && s.running) {
      s.remaining_seconds = Math.max(0, s.seconds - Math.floor((Date.now() - this.sentAt) / 1000));
      s.done = s.remaining_seconds === 0;
    }
    return s;
  }

  async unpair(deviceId: string): Promise<boolean> {
    this.current = null;
    return true;
  }
}

/**
 * The relay base URL from the app's config.local.json ({"devices": {"relayBaseUrl": "https://..."}}), or ''.
 * Only https, or http to this machine for the local mock. Never hard-coded, never committed.
 */
export function loadRelayBaseUrl(ctx: common.Context): string {
  const dirs: string[] = [ctx.getApplicationContext().filesDir, ctx.filesDir];
  for (const dir of dirs) {
    const path = `${dir}/config.local.json`;
    try {
      if (!fileIo.accessSync(path)) {
        continue;
      }
      const o = JSON.parse(fileIo.readTextSync(path)) as Record<string, Object>;
      const devices = o['devices'] as Record<string, Object> | undefined;
      const base = devices !== undefined && typeof devices['relayBaseUrl'] === 'string' ?
        (devices['relayBaseUrl'] as string).trim() : '';
      return isAllowedRelayUrl(base) ? base : '';
    } catch (e) {
      // unreadable: try the next location
    }
  }
  return '';
}

/** https anywhere; plain http only to localhost / 127.0.0.1 / 10.0.2.2 (the local mock). */
export function isAllowedRelayUrl(base: string): boolean {
  return /^https:\/\/[^\s/]+/i.test(base) || /^http:\/\/(localhost|127\.0\.0\.1|10\.0\.2\.2)(:\d+)?(\/|$)/i.test(base);
}
