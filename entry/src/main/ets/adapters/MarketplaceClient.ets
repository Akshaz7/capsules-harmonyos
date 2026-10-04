/**
 * The capsule marketplace (SimpsonLWH/harmoniser-web, README "API" and docs/native-integration.md).
 * The marketplace never runs a capsule: an install only downloads the JSON, which then goes through the
 * app's own import flow (size check, validator, fresh id, "From the marketplace" consent). Network
 * failures never block anything; when the API is unreachable or answers 503 the app shows the examples
 * it ships (rawfile/templates/library.json) and says it is offline.
 */
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { Capsule, validateCapsule } from '../core';
import { TOKEN_HEADER } from './InstallToken';

const DOMAIN = 0x0001;
const TAG = 'Marketplace';
const TIMEOUT_MS = 6000;
const LIBRARY_FILE = 'templates/library.json';

/** One catalogue entry. `capsuleJson` is set for offline examples (the live list fetches it on install). */
export interface MarketItem {
  id: string;
  name: string;
  description: string;
  tags: string[];
  installs: number;
  widget: boolean;
  capsuleJson?: string;
}

export interface MarketPage {
  items: MarketItem[];
  nextCursor: string;
  /** True when this page is the on-phone examples because the marketplace could not be reached. */
  offline: boolean;
}

export interface MarketCapsule {
  json?: string;
  error?: string;
}

export interface PublishResult {
  id?: string;
  /** 409: the same capsule is already published; this is its public id. */
  duplicateId?: string;
  error?: string;
}

/** Categories offered as chips (the shipped examples' categories, used as tags on the live API). */
export const MARKET_CATEGORIES: string[] = ['timers', 'fitness', 'habits', 'games', 'calculators', 'cooking',
  'household', 'study', 'money', 'quizzes'];

// ---- Pure helpers (unit tested) ----

/** The message of an error body {"error":{"code","message"}}, else a short status text. */
export function marketErrorMessage(status: number, body: string): string {
  try {
    const o = JSON.parse(body) as Record<string, Object>;
    const e = o['error'] as Record<string, Object> | undefined;
    if (e !== undefined && typeof e['message'] === 'string') {
      return e['message'] as string;
    }
  } catch (err) {
    // not JSON
  }
  return status === 0 ? "The marketplace didn't answer" : `The marketplace answered ${status}`;
}

function strings(v: Object | undefined): string[] {
  return Array.isArray(v) ? (v as Object[]).filter((x: Object) => typeof x === 'string').map((x: Object) => x as string) : [];
}

function str(o: Record<string, Object>, key: string): string {
  return typeof o[key] === 'string' ? o[key] as string : '';
}

/** Parses GET /api/capsules: {capsules: [...], nextCursor}. Entries without an id are dropped. */
export function parseMarketList(body: string): MarketPage | null {
  try {
    const o = JSON.parse(body) as Record<string, Object>;
    if (!Array.isArray(o['capsules'])) {
      return null;
    }
    const items: MarketItem[] = [];
    (o['capsules'] as Object[]).forEach((x: Object) => {
      const c = x as Record<string, Object>;
      if (typeof c['id'] !== 'string') {
        return;
      }
      items.push({
        id: c['id'] as string, name: str(c, 'name'), description: str(c, 'description'), tags: strings(c['tags']),
        installs: typeof c['installs'] === 'number' ? c['installs'] as number : 0, widget: c['widget'] === true
      });
    });
    const page: MarketPage = { items: items, nextCursor: str(o, 'nextCursor'), offline: false };
    return page;
  } catch (e) {
    return null;
  }
}

/** Does an item match a search text and a category/tag? Case-insensitive, name/description/tags. */
export function matchesSearch(item: MarketItem, q: string, tag: string): boolean {
  if (tag.length > 0 && !item.tags.some((t: string) => t.toLowerCase() === tag.toLowerCase())) {
    return false;
  }
  const needle = q.trim().toLowerCase();
  if (needle.length === 0) {
    return true;
  }
  return item.name.toLowerCase().includes(needle) || item.description.toLowerCase().includes(needle) ||
    item.tags.some((t: string) => t.toLowerCase().includes(needle));
}

/**
 * The shipped example library as marketplace items: only capsules the app's validator accepts, with the
 * category as the first tag.
 */
export function libraryItems(libraryJson: string): MarketItem[] {
  try {
    const o = JSON.parse(libraryJson) as Record<string, Object>;
    const list = Array.isArray(o['templates']) ? o['templates'] as Object[] : [];
    const items: MarketItem[] = [];
    list.forEach((x: Object) => {
      const t = x as Record<string, Object>;
      const json = JSON.stringify(t['capsule']);
      if (typeof t['id'] !== 'string' || json === undefined || !validateCapsule(json).ok) {
        return;
      }
      if (t['listed'] === false) {
        return; // curated out of the marketplace list (plan h.1); Create still builds it
      }
      const category = str(t, 'category');
      items.push({
        id: `example:${t['id'] as string}`, name: str(t, 'name'), description: str(t, 'description'),
        tags: (category.length > 0 ? [category] : []).concat(strings(t['tags']).slice(0, 4)), installs: 0,
        widget: false, capsuleJson: json
      });
    });
    return items;
  } catch (e) {
    return [];
  }
}

// ---- Clients ----

interface Reply {
  status: number; // 0 = no answer
  body: string;
}

interface PublishBody {
  capsule: Capsule;
  name: string;
  description?: string;
  tags?: string[];
}

/** Talks to the live marketplace; falls back to the shipped examples whenever it can't. Never throws. */
export class MarketplaceClient {
  private base: string;
  private token: string;
  private library: MarketItem[] = [];

  /** `baseUrl` '' means no marketplace configured: offline examples only. */
  constructor(baseUrl: string, token: string, libraryJson: string) {
    this.base = baseUrl.replace(/\/+$/, '');
    this.token = token;
    this.library = libraryItems(libraryJson);
  }

  get configured(): boolean {
    return this.base.length > 0;
  }

  private async call(method: http.RequestMethod, path: string, body?: string, withToken: boolean = false):
    Promise<Reply> {
    if (!this.configured) {
      const none: Reply = { status: 0, body: '' };
      return none;
    }
    let req: http.HttpRequest | null = null;
    try {
      req = http.createHttp();
      const headers: Record<string, string> = { 'Content-Type': 'application/json' };
      if (withToken) {
        headers[TOKEN_HEADER] = this.token;
      }
      const resp = await req.request(`${this.base}${path}`, {
        method: method, header: headers, extraData: body, connectTimeout: TIMEOUT_MS, readTimeout: TIMEOUT_MS,
        expectDataType: http.HttpDataType.STRING
      });
      const r: Reply = { status: resp.responseCode, body: typeof resp.result === 'string' ? resp.result : '' };
      if (r.status >= 400) {
        hilog.warn(DOMAIN, TAG, '%{public}s %{public}s -> %{public}d %{public}s', method, path.split('?')[0], r.status,
          marketErrorMessage(r.status, r.body));
      }
      return r;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'marketplace unreachable: %{public}s', (e as BusinessError).message);
      const r: Reply = { status: 0, body: '' };
      return r;
    } finally {
      req?.destroy();
    }
  }

  private offlinePage(q: string, tag: string): MarketPage {
    const page: MarketPage = {
      items: this.library.filter((i: MarketItem) => matchesSearch(i, q, tag)), nextCursor: '', offline: true
    };
    return page;
  }

  /** Search the catalogue; the shipped examples (offline: true) when the marketplace can't be reached. */
  async search(q: string, tag: string, cursor: string = ''): Promise<MarketPage> {
    const params: string[] = ['limit=30'];
    if (q.trim().length > 0) {
      params.push(`q=${encodeURIComponent(q.trim().substring(0, 100))}`);
    }
    if (tag.length > 0) {
      params.push(`tag=${encodeURIComponent(tag.toLowerCase())}`);
    }
    if (cursor.length > 0) {
      params.push(`cursor=${encodeURIComponent(cursor)}`);
    }
    const r = await this.call(http.RequestMethod.GET, `/api/capsules?${params.join('&')}`);
    const page = r.status === 200 ? parseMarketList(r.body) : null;
    return page ?? this.offlinePage(q, tag);
  }

  /** The capsule JSON to import. Never runs anything. */
  async capsuleJson(item: MarketItem): Promise<MarketCapsule> {
    if (item.capsuleJson !== undefined) {
      const local: MarketCapsule = { json: item.capsuleJson };
      return local;
    }
    const r = await this.call(http.RequestMethod.GET, `/api/capsules/${encodeURIComponent(item.id)}`);
    if (r.status === 200) {
      try {
        const o = JSON.parse(r.body) as Record<string, Object>;
        if (o['capsule'] !== undefined) {
          const ok: MarketCapsule = { json: JSON.stringify(o['capsule']) };
          return ok;
        }
      } catch (e) {
        // fall through
      }
    }
    const failed: MarketCapsule = { error: marketErrorMessage(r.status, r.body) };
    return failed;
  }

  /** Best-effort install intent after the user ran an installed capsule. Ignored for offline examples. */
  installed(item: MarketItem): void {
    if (item.capsuleJson === undefined) {
      this.call(http.RequestMethod.POST, `/api/capsules/${encodeURIComponent(item.id)}/install`, '{}', true);
    }
  }

  /** Publishes a capsule (its definition only, never its state). */
  async publish(capsule: Capsule, description: string, tags: string[]): Promise<PublishResult> {
    if (!this.configured) {
      const off: PublishResult = { error: "The marketplace isn't set up on this phone" };
      return off;
    }
    const body: PublishBody = { capsule: capsule, name: capsule.name };
    if (description.length > 0) {
      body.description = description;
    }
    if (tags.length > 0) {
      body.tags = tags;
    }
    const r = await this.call(http.RequestMethod.POST, '/api/capsules', JSON.stringify(body), true);
    try {
      const o = JSON.parse(r.body) as Record<string, Object>;
      if (r.status === 201 && typeof o['id'] === 'string') {
        const ok: PublishResult = { id: o['id'] as string };
        return ok;
      }
      if (r.status === 409) {
        const e = o['error'] as Record<string, Object> | undefined;
        const d = e !== undefined ? e['details'] as Record<string, Object> | undefined : undefined;
        const existing = d !== undefined && typeof d['id'] === 'string' ? d['id'] as string :
          typeof o['id'] === 'string' ? o['id'] as string : '';
        const dup: PublishResult = { duplicateId: existing, error: 'This capsule is already in the marketplace' };
        return dup;
      }
    } catch (e) {
      // fall through
    }
    const failed: PublishResult = { error: marketErrorMessage(r.status, r.body) };
    return failed;
  }

  /** Takes a published capsule down (only this install's token can). */
  async unpublish(id: string): Promise<boolean> {
    const r = await this.call(http.RequestMethod.DELETE, `/api/capsules/${encodeURIComponent(id)}`, undefined, true);
    return r.status === 200 || r.status === 204;
  }
}

/** marketplace.baseUrl from the app's config.local.json (https only), or ''. */
export function loadMarketplaceBaseUrl(ctx: common.Context): string {
  const dirs: string[] = [ctx.getApplicationContext().filesDir, ctx.filesDir];
  for (const dir of dirs) {
    const path = `${dir}/config.local.json`;
    try {
      if (!fileIo.accessSync(path)) {
        continue;
      }
      const o = JSON.parse(fileIo.readTextSync(path)) as Record<string, Object>;
      const m = o['marketplace'] as Record<string, Object> | undefined;
      const base = m !== undefined && typeof m['baseUrl'] === 'string' ? (m['baseUrl'] as string).trim() : '';
      return /^https:\/\/[^\s/]+/i.test(base) || /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?/i.test(base) ? base : '';
    } catch (e) {
      // unreadable: try the next location
    }
  }
  return '';
}

/** The shipped example library (rawfile/templates/library.json), or '' if missing. */
export async function loadLibraryJson(ctx: common.Context): Promise<string> {
  try {
    const bytes = await ctx.resourceManager.getRawFileContent(LIBRARY_FILE);
    return util.TextDecoder.create('utf-8').decodeToString(bytes);
  } catch (e) {
    return '';
  }
}
