/**
 * Request cache: the same request (after normalising) reuses the capsule made last time, on the phone and
 * without a model. Least recently used entries are dropped above MAX_CACHE_ENTRIES. Every cached capsule is
 * validated again when read, so a stale or corrupted entry is never returned.
 *
 * RequestCache is pure (any CacheStore); openRequestCache(context) in index.ets backs it with Preferences.
 */
import { Capsule, CapsuleOrigin } from '../CapsuleTypes';
import { validateCapsule } from '../CapsuleValidator';
import { foldText } from './TemplateLibrary';

export const MAX_CACHE_ENTRIES: number = 200;

/** Where the cache keeps its one JSON text. */
export interface CacheStore {
  read(): string;
  write(text: string): Promise<void>;
}

export interface CachedCapsule {
  capsule: Capsule;
  /** Where it was first made: "template", "rules", "on-device", "cloud-eu:mistral", ... */
  origin: string;
}

interface CacheEntry {
  key: string;
  capsule: string;
  origin: string;
  t: number;
}

/** "  Tennis scoreboard, me vs SAM! " -> "tennis scoreboard me vs sam". Numbers and word order are kept. */
export function normaliseRequest(request: string): string {
  return foldText(request).replace(/[^a-z0-9぀-ヿ㐀-鿿가-힯./]+/g, ' ')
    .replace(/(^|\s)[./]+|[./]+(\s|$)/g, ' ').replace(/\s+/g, ' ').trim();
}

export class RequestCache {
  private store: CacheStore;
  private entries: CacheEntry[] = [];
  private max: number;
  private clock: () => number;

  constructor(store: CacheStore, max?: number, clock?: () => number) {
    this.store = store;
    this.max = max ?? MAX_CACHE_ENTRIES;
    this.clock = clock ?? ((): number => Date.now());
    try {
      const parsed = JSON.parse(store.read()) as CacheEntry[];
      if (Array.isArray(parsed)) {
        this.entries = parsed.filter((e: CacheEntry) => typeof e.key === 'string' && typeof e.capsule === 'string');
      }
    } catch (e) {
      this.entries = []; // empty or unreadable: start over
    }
  }

  get size(): number {
    return this.entries.length;
  }

  /** The capsule cached for this request, re-validated, or null. Marks it as recently used. */
  get(request: string): CachedCapsule | null {
    const key = normaliseRequest(request);
    const i = this.entries.findIndex((e: CacheEntry) => e.key === key);
    if (key.length === 0 || i < 0) {
      return null;
    }
    const entry = this.entries[i];
    const v = validateCapsule(entry.capsule);
    if (!v.ok || v.capsule === undefined) {
      this.entries.splice(i, 1);
      this.save();
      return null;
    }
    entry.t = this.clock();
    this.entries.splice(i, 1);
    this.entries.push(entry);
    this.save();
    return { capsule: v.capsule, origin: entry.origin };
  }

  /** Stores a validated capsule for the request; drops the least recently used above the cap. */
  async put(request: string, capsule: Capsule, origin: CapsuleOrigin | string): Promise<void> {
    const key = normaliseRequest(request);
    const text = JSON.stringify(capsule);
    if (key.length === 0 || !validateCapsule(text).ok) {
      return;
    }
    this.entries = this.entries.filter((e: CacheEntry) => e.key !== key);
    this.entries.push({ key: key, capsule: text, origin: origin, t: this.clock() });
    while (this.entries.length > this.max) {
      this.entries.shift();
    }
    await this.save();
  }

  async remove(request: string): Promise<void> {
    const key = normaliseRequest(request);
    this.entries = this.entries.filter((e: CacheEntry) => e.key !== key);
    await this.save();
  }

  async clear(): Promise<void> {
    this.entries = [];
    await this.save();
  }

  private async save(): Promise<void> {
    try {
      await this.store.write(JSON.stringify(this.entries));
    } catch (e) {
      // the cache is an optimisation: a failed write only means the next run makes the capsule again
    }
  }
}

/** In-memory store, for tests and when Preferences are unavailable. */
export class MemoryStore implements CacheStore {
  text: string = '';

  read(): string {
    return this.text;
  }

  async write(text: string): Promise<void> {
    this.text = text;
  }
}
