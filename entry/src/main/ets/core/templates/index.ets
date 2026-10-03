/**
 * App-facing entry point of the template library and the request cache.
 *
 *   await initTemplates(context);            // once, e.g. next to initCapsuleModel; never throws
 *   const m = matchTemplate('pomodoro 50/10'); // { capsule, score, unfilledSlots, ... } | null, origin "template"
 *   const cache = getRequestCache();          // cache.get(request) / cache.put(request, capsule, origin)
 *
 * Until initTemplates has loaded rawfile/templates/library.json, the built-in CORE_TEMPLATES are used.
 */
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { CORE_TEMPLATES } from './CoreTemplates';
import { matchTemplateIn, TemplateLibrary, TemplateMatch } from './TemplateLibrary';
import { CacheStore, MemoryStore, RequestCache } from './RequestCache';

export {
  TemplateEntry, TemplateSlot, SlotKind, SlotValue, TemplateHit, TemplateFill, TemplateMatch, TemplateLibrary,
  TEMPLATE_MATCH_THRESHOLD, fillTemplate, matchTemplateIn, applySlots, foldText
} from './TemplateLibrary';
export { SlotModel, slotPrompt, parseSlotReply, fillUnclearSlots } from './SlotFill';
export { RequestCache, CacheStore, CachedCapsule, MemoryStore, MAX_CACHE_ENTRIES, normaliseRequest } from './RequestCache';
export { CORE_TEMPLATES } from './CoreTemplates';

/** The origin and badge for capsules made from a template. */
export const TEMPLATE_ORIGIN: string = 'template';
export const TEMPLATE_BADGE: string = 'Made on your phone · no internet';
export const LIBRARY_FILE: string = 'templates/library.json';

let library: TemplateLibrary = new TemplateLibrary(CORE_TEMPLATES);
let cache: RequestCache = new RequestCache(new MemoryStore());

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

export function getRequestCache(): RequestCache {
  return cache;
}
