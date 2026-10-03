/**
 * Live marketplace matching, merged with the built-in templates (T6-5).
 *
 * matchTemplateAsync(library, request, market) searches the marketplace (GET <baseUrl>/api/capsules?q=...),
 * scores its results together with the local templates on one scale (same TemplateLibrary scorer, one corpus),
 * and returns the best match above the threshold:
 * - a local template: filled from the request by rules (origin "template");
 * - a marketplace capsule: fetched (GET /api/capsules/<id>), size-checked, validated as untrusted JSON and given a
 *   fresh id (origin "community"). Marketplace capsules have no slots, so nothing is filled.
 * A local template wins a tie. The whole marketplace part has one time budget (default 1.5 s); it is skipped
 * when there is no base URL or the phone is offline, and any error, timeout or bad reply means local only.
 * Pure: the HTTP GET is injected (MarketTransport); templates/index.ets plugs in @kit.NetworkKit.
 */
import { Capsule } from '../CapsuleTypes';
import { validateCapsule } from '../CapsuleValidator';
import { fillTemplate, matchTemplateIn, TEMPLATE_MATCH_THRESHOLD, TemplateEntry, TemplateHit, TemplateLibrary,
  TemplateMatch } from './TemplateLibrary';

export const MARKET_TIMEOUT_MS: number = 1500;
/** Same limit as a shared capsule file (sharing/CapsuleShare MAX_SHARE_BYTES). */
export const MAX_MARKET_CAPSULE_CHARS: number = 8192;
const MARKET_PREFIX: string = 'community:';
const MAX_RESULTS: number = 20;

export interface MarketReply {
  status: number; // 0 = no answer
  body: string;
}

/** One HTTP GET with a timeout. Must not throw (return status 0 instead), but a throw is handled too. */
export interface MarketTransport {
  get(url: string, timeoutMs: number): Promise<MarketReply>;
}

export interface MarketOptions {
  /** marketplace.baseUrl from config; '' skips the marketplace. */
  baseUrl: string;
  transport: MarketTransport;
  /** False when the phone has no network: skips the marketplace without trying. Default true. */
  online?: boolean;
  /** Budget for the whole marketplace part (search + fetch). Default MARKET_TIMEOUT_MS. */
  timeoutMs?: number;
}

interface MarketItem {
  id: string;
  name: string;
  description: string;
  tags: string[];
}

/** Parses GET /api/capsules ({capsules: [{id, name, description, tags}]}); null if it is not that. */
export function parseMarketSearch(body: string): MarketItem[] | null {
  try {
    const o = JSON.parse(body) as Record<string, Object>;
    if (!Array.isArray(o['capsules'])) {
      return null;
    }
    const items: MarketItem[] = [];
    (o['capsules'] as Object[]).forEach((x: Object) => {
      if (x === null || typeof x !== 'object') {
        return;
      }
      const c = x as Record<string, Object>;
      if (typeof c['id'] !== 'string' || typeof c['name'] !== 'string') {
        return;
      }
      const tags = Array.isArray(c['tags']) ? (c['tags'] as Object[]).filter((t: Object) => typeof t === 'string')
        .map((t: Object) => (t as string).replace(/[-_]+/g, ' ')) : [];
      items.push({
        id: c['id'] as string, name: c['name'] as string,
        description: typeof c['description'] === 'string' ? c['description'] as string : '', tags: tags
      });
    });
    return items.slice(0, MAX_RESULTS);
  } catch (e) {
    return null;
  }
}

/** The capsule from GET /api/capsules/<id> ({capsule: {...}}), validated, with a fresh id; or null. */
export function marketCapsule(body: string): Capsule | null {
  if (body.length > MAX_MARKET_CAPSULE_CHARS * 2) {
    return null; // far too big to be one capsule; don't even parse it
  }
  try {
    const o = JSON.parse(body) as Record<string, Object>;
    const raw = o['capsule'];
    if (raw === undefined || raw === null || typeof raw !== 'object') {
      return null;
    }
    const json = JSON.stringify(raw);
    if (json.length > MAX_MARKET_CAPSULE_CHARS) {
      return null;
    }
    const v = validateCapsule(json);
    if (!v.ok || v.capsule === undefined) {
      return null;
    }
    const capsule = v.capsule;
    capsule.id = `community-${Date.now().toString(36)}-${Math.floor(Math.random() * 0x100000000).toString(36)}`;
    return capsule;
  } catch (e) {
    return null;
  }
}

/** Resolves to `fallback` after `ms` if `work` has not settled; a rejection also gives `fallback`. */
function withDeadline<T>(work: Promise<T>, ms: number, fallback: T): Promise<T> {
  return new Promise<T>((resolve: (v: T) => void) => {
    let done = false;
    const timer = setTimeout(() => {
      if (!done) {
        done = true;
        resolve(fallback);
      }
    }, Math.max(0, ms));
    work.then((v: T) => {
      if (!done) {
        done = true;
        clearTimeout(timer);
        resolve(v);
      }
    }).catch(() => {
      if (!done) {
        done = true;
        clearTimeout(timer);
        resolve(fallback);
      }
    });
  });
}

const NO_REPLY: MarketReply = { status: 0, body: '' };

function marketEntry(item: MarketItem): TemplateEntry {
  return {
    id: `${MARKET_PREFIX}${item.id}`, name: item.name, description: item.description, tags: item.tags, slots: [],
    capsule: new Object(), category: 'community', language: 'en'
  };
}

/**
 * The best template or marketplace capsule for the request, or null below the threshold. Never throws.
 * With no `market` (or no base URL, or offline) this is matchTemplateIn.
 */
export async function matchTemplateAsync(library: TemplateLibrary, request: string, market?: MarketOptions,
  threshold?: number): Promise<TemplateMatch | null> {
  const min = threshold ?? TEMPLATE_MATCH_THRESHOLD;
  const base = market !== undefined ? market.baseUrl.trim().replace(/\/+$/, '') : '';
  if (market === undefined || base.length === 0 || market.online === false || request.trim().length === 0) {
    return matchTemplateIn(library, request, min);
  }
  const budget = market.timeoutMs ?? MARKET_TIMEOUT_MS;
  const started = Date.now();
  const q = encodeURIComponent(request.trim().substring(0, 100));
  const reply = await withDeadline(market.transport.get(`${base}/api/capsules?q=${q}&limit=${MAX_RESULTS}`, budget),
    budget, NO_REPLY);
  const items = reply.status === 200 ? parseMarketSearch(reply.body) : null;
  if (items === null || items.length === 0) {
    return matchTemplateIn(library, request, min);
  }
  // One corpus, one scale: local templates and marketplace entries scored together; local first, so it wins ties.
  const merged = new TemplateLibrary(library.all().concat(items.map((i: MarketItem) => marketEntry(i))));
  // Equal scores: the local template first (it is filled from the request and needs no download).
  const isMarket = (h: TemplateHit): number => h.template.id.startsWith(MARKET_PREFIX) ? 1 : 0;
  const hits: TemplateHit[] = merged.search(request, 8)
    .sort((x: TemplateHit, y: TemplateHit) => y.score - x.score || isMarket(x) - isMarket(y));
  for (const hit of hits) {
    if (hit.score < min) {
      break;
    }
    const id = hit.template.id;
    if (!id.startsWith(MARKET_PREFIX)) {
      const f = fillTemplate(hit.template, request);
      if (f.capsule !== undefined) {
        return {
          capsule: f.capsule, score: hit.score, unfilledSlots: f.unclear, template: hit.template, values: f.values,
          origin: 'template', source: hit.template.name
        };
      }
      continue;
    }
    const left = budget - (Date.now() - started);
    if (left <= 0) {
      continue; // out of time for the marketplace: only local hits from here
    }
    const url = `${base}/api/capsules/${encodeURIComponent(id.substring(MARKET_PREFIX.length))}`;
    const got = await withDeadline(market.transport.get(url, left), left, NO_REPLY);
    const capsule = got.status === 200 ? marketCapsule(got.body) : null;
    if (capsule !== null) {
      return {
        capsule: capsule, score: hit.score, unfilledSlots: [], template: hit.template, values: {},
        origin: 'community', source: hit.template.name
      };
    }
  }
  return matchTemplateIn(library, request, min);
}
