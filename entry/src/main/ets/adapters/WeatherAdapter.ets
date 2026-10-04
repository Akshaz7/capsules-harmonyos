/**
 * Weather from Open-Meteo (non-commercial demo use; attribution is shown by the card).
 *
 * Privacy: the only thing that leaves the phone is the chosen bundled city's coordinates on one fixed
 * HTTPS endpoint — no capsule text, state, identifiers or custom headers, and never an arbitrary URL.
 * Caching: one reading per city for 15 minutes; a manual refresh is at least 60 seconds after the last one.
 */
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { http } from '@kit.NetworkKit';
import { cityById, City, MAX_WEATHER_BYTES, parseOpenMeteo, WeatherReading } from '../capabilities/WeatherData';

const DOMAIN = 0x0001;
const TAG = 'WeatherAdapter';
const TIMEOUT_MS: number = 6000;
const API = 'https://api.open-meteo.com/v1/forecast';
export const WEATHER_TTL_MS: number = 15 * 60 * 1000;
export const WEATHER_COOLDOWN_MS: number = 60 * 1000;

export type WeatherState = 'ok' | 'stale' | 'empty' | 'offline' | 'error';

export interface WeatherResult {
  state: WeatherState;
  /** Present when a reading exists (fresh or cached); null when there is none. */
  reading: WeatherReading | null;
}

interface CacheEntry {
  reading: WeatherReading;
  at: number;
}

export class WeatherAdapter {
  private cache: Map<string, CacheEntry> = new Map();
  private lastFetch: Map<string, number> = new Map();

  /** Cache-only read for rendering: fresh -> ok, older than 15 min -> stale, nothing -> empty. */
  read(cityId: string, now: number): WeatherResult {
    const entry = this.cache.get(cityId);
    if (entry === undefined) {
      return { state: 'empty', reading: null };
    }
    return now - entry.at <= WEATHER_TTL_MS ?
      { state: 'ok', reading: entry.reading } : { state: 'stale', reading: entry.reading };
  }

  /** Fetches once, with the 60-second manual cooldown. Falls back to the cached reading on failure. */
  async refresh(cityId: string, now: number): Promise<WeatherResult> {
    const cached: CacheEntry | undefined = this.cache.get(cityId);
    const last: number | undefined = this.lastFetch.get(cityId);
    if (last !== undefined && now - last < WEATHER_COOLDOWN_MS) {
      return cached === undefined ? { state: 'empty', reading: null } : this.read(cityId, now);
    }
    const city: City | undefined = cityById(cityId);
    if (city === undefined) {
      return { state: 'error', reading: null };
    }
    const body: string | null = await this.get(city);
    if (body === null) {
      return cached === undefined ?
        { state: 'offline', reading: null } : { state: 'stale', reading: cached.reading };
    }
    const reading: WeatherReading | null = parseOpenMeteo(body, Date.now());
    if (reading === null) {
      hilog.warn(DOMAIN, TAG, 'open-meteo replied with an unexpected body');
      return cached === undefined ?
        { state: 'error', reading: null } : { state: 'stale', reading: cached.reading };
    }
    // The cooldown starts only after a successful fetch, so a failure can be retried at once.
    this.lastFetch.set(cityId, Date.now());
    this.cache.set(cityId, { reading: reading, at: Date.now() });
    return { state: 'ok', reading: reading };
  }

  private urlFor(city: City): string {
    return `${API}?latitude=${city.latitude}&longitude=${city.longitude}` +
      '&current=temperature_2m,weather_code,wind_speed_10m&timezone=auto';
  }

  private async get(city: City): Promise<string | null> {
    const req = http.createHttp();
    try {
      const resp = await req.request(this.urlFor(city), {
        method: http.RequestMethod.GET,
        connectTimeout: TIMEOUT_MS,
        readTimeout: TIMEOUT_MS,
        expectDataType: http.HttpDataType.STRING
      });
      if (resp.responseCode !== 200) {
        hilog.warn(DOMAIN, TAG, 'open-meteo replied %{public}d', resp.responseCode);
        return null;
      }
      const body: string = typeof resp.result === 'string' ? resp.result : '';
      return body.length === 0 || body.length > MAX_WEATHER_BYTES ? null : body;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'open-meteo unreachable: %{public}s', (e as BusinessError).message);
      return null;
    } finally {
      req.destroy();
    }
  }
}
