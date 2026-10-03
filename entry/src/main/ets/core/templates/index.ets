/**
 * App-facing entry point of the template library and the request cache.
 *
 *   await initTemplates(context);            // once, e.g. next to initCapsuleModel; never throws
 *   const m = matchTemplate('pomodoro 50/10'); // { capsule, score, unfilledSlots, ... } | null, origin "template"
 *   const cache = getRequestCache();          // cache.get(request) / cache.put(request, capsule, origin)
 *   const live = await matchTemplateAsync('darts 501 me vs Tom'); // + live marketplace, origin "community"
 *
 * Until initTemplates has loaded rawfile/templates/library.json, the built-in CORE_TEMPLATES are used.
 */
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { connection, http } from '@kit.NetworkKit';
import { CORE_TEMPLATES } from './CoreTemplates';
import { matchTemplateIn, TemplateLibrary, TemplateMatch } from './TemplateLibrary';
import { CacheStore, MemoryStore, RequestCache } from './RequestCache';
import { MarketOptions, MarketReply, MarketTransport, matchTemplateAsync as matchWithMarket } from './MarketMatch';

export {
  TemplateEntry, TemplateSlot, SlotKind, SlotValue, TemplateHit, TemplateFill, TemplateMatch, TemplateLibrary,
  TEMPLATE_MATCH_THRESHOLD, fillTemplate, matchTemplateIn, applySlots, foldText
} from './TemplateLibrary';
export { SlotModel, slotPrompt, parseSlotReply, fillUnclearSlots } from './SlotFill';
export { RequestCache, CacheStore, CachedCapsule, MemoryStore, MAX_CACHE_ENTRIES, normaliseRequest } from './RequestCache';
export { CORE_TEMPLATES } from './CoreTemplates';
export { MarketOptions, MarketTransport, MarketReply, MARKET_TIMEOUT_MS, parseMarketSearch, marketCapsule
} from './MarketMatch';

/** The origin and badge for capsules made from a template. */
export const TEMPLATE_ORIGIN: string = 'template';
export const TEMPLATE_BADGE: string = 'Made on your phone · no internet';
export const LIBRARY_FILE: string = 'templates/library.json';

let library: TemplateLibrary = new TemplateLibrary(CORE_TEMPLATES);
let cache: RequestCache = new RequestCache(new MemoryStore());
let marketBase: string = '';

class HttpGet implements MarketTransport {
  async get(url: string, timeoutMs: number): Promise<MarketReply> {
    let req: http.HttpRequest | null = null;
    try {
      req = http.createHttp();
      const resp = await req.request(url, {
        method: http.RequestMethod.GET, connectTimeout: timeoutMs, readTimeout: timeoutMs,
        expectDataType: http.HttpDataType.STRING
      });
      const r: MarketReply = { status: resp.responseCode, body: typeof resp.result === 'string' ? resp.result : '' };
      return r;
    } catch (e) {
      const none: MarketReply = { status: 0, body: '' };
      return none;
    } finally {
      req?.destroy();
    }
  }
}

const httpGet: HttpGet = new HttpGet();

/** marketplace.baseUrl from config.local.json in the app's files dir (https only), or ''. */
function readMarketBase(context: common.Context): string {
  const dirs: string[] = [context.getApplicationContext().filesDir, context.filesDir];
  for (const dir of dirs) {
    try {
      const path = `${dir}/config.local.json`;
      if (!fileIo.accessSync(path)) {
        continue;
      }
      const o = JSON.parse(fileIo.readTextSync(path)) as Record<string, Object>;
      const m = o['marketplace'] as Record<string, Object> | undefined;
      const base = m !== undefined && typeof m['baseUrl'] === 'string' ? (m['baseUrl'] as string).trim() : '';
      return /^https:\/\/[^\s/]+/i.test(base) ? base : '';
    } catch (e) {
      // unreadable: try the next location
    }
  }
  return '';
}

/** False only when the system says there is no network; true when it can't tell (e.g. no GET_NETWORK_INFO). */
function isOnline(): boolean {
  try {
    return connection.hasDefaultNetSync();
  } catch (e) {
    return true;
  }
}

class PreferencesStore implements CacheStore {
  private prefs: preferences.Preferences;

  constructor(prefs: preferences.Preferences) {
    this.prefs = prefs;
  }

  read(): string {
    try {
      return this.prefs.getSync('entries', '[]') as string;
    } catch (e) {
      return '[]';
    }
  }

  async write(text: string): Promise<void> {
    try {
      this.prefs.putSync('entries', text);
      await this.prefs.flush();
    } catch (e) {
      // a failed write only means the capsule is made again next time
    }
  }
}

/** Loads the template library from rawfile and opens the request cache in Preferences. Never throws. */
export async function initTemplates(context: common.Context): Promise<number> {
  try {
    const options: preferences.Options = { name: 'request-cache' };
    cache = new RequestCache(new PreferencesStore(preferences.getPreferencesSync(context, options)));
  } catch (e) {
    cache = new RequestCache(new MemoryStore()); // memory only: still avoids repeats in this run
  }
  try {
    const bytes = await context.resourceManager.getRawFileContent(LIBRARY_FILE);
    library = TemplateLibrary.fromJson(util.TextDecoder.create('utf-8').decodeToString(bytes), CORE_TEMPLATES);
  } catch (e) {
    library = new TemplateLibrary(CORE_TEMPLATES);
  }
  marketBase = readMarketBase(context);
  return library.size;
}

/** The loaded library (core templates only before initTemplates). */
export function getTemplateLibrary(): TemplateLibrary {
  return library;
}

/** The best template for the request, filled from it and validated, or null when nothing scores high enough. */
export function matchTemplate(request: string, threshold?: number): TemplateMatch | null {
  return matchTemplateIn(library, request, threshold);
}

/** The live marketplace for matching: base URL from config, 1.5 s budget, skipped offline. */
export function getMarketOptions(): MarketOptions {
  return { baseUrl: marketBase, transport: httpGet, online: isOnline() };
}

/**
 * Like matchTemplate, plus the live marketplace: the best of both on one score scale. Returns origin "template"
 * (local, filled from the request) or "community" (a validated marketplace capsule with a fresh id) and `source`
 * (what it was made from). Local only when offline, without marketplace.baseUrl, or on any error or timeout.
 */
export async function matchTemplateAsync(request: string, threshold?: number): Promise<TemplateMatch | null> {
  return matchWithMarket(library, request, getMarketOptions(), threshold);
}

export function getRequestCache(): RequestCache {
  return cache;
}
