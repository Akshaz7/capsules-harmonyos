/**
 * Curated cities, WMO condition labels and strict response parsing for the weather capability.
 * Pure data and formatting (no platform APIs), so it is unit-tested directly. Capsules can never supply
 * coordinates, URLs or headers: they may only name one of these city ids.
 */

import { DeviceComponent } from '../core/CapsuleTypes';

export interface City {
  id: string;
  name: string;
  latitude: number;
  longitude: number;
}

/** The bundled list the user picks from; keep it small and reviewed. */
export const CITIES: City[] = [
  { id: 'krakow', name: 'Kraków', latitude: 50.0614, longitude: 19.9366 },
  { id: 'warsaw', name: 'Warsaw', latitude: 52.2297, longitude: 21.0122 },
  { id: 'wroclaw', name: 'Wrocław', latitude: 51.1079, longitude: 17.0385 },
  { id: 'gdansk', name: 'Gdańsk', latitude: 54.3520, longitude: 18.6466 },
  { id: 'poznan', name: 'Poznań', latitude: 52.4064, longitude: 16.9252 },
  { id: 'lodz', name: 'Łódź', latitude: 51.7592, longitude: 19.4560 },
  { id: 'katowice', name: 'Katowice', latitude: 50.2649, longitude: 19.0238 },
  { id: 'berlin', name: 'Berlin', latitude: 52.5200, longitude: 13.4050 },
  { id: 'prague', name: 'Prague', latitude: 50.0755, longitude: 14.4378 },
  { id: 'vienna', name: 'Vienna', latitude: 48.2082, longitude: 16.3738 },
  { id: 'london', name: 'London', latitude: 51.5072, longitude: -0.1276 },
  { id: 'paris', name: 'Paris', latitude: 48.8566, longitude: 2.3522 }
];

export const WEATHER_SOURCE: string = 'Weather data by Open-Meteo.com';
export const WEATHER_URL: string = 'https://open-meteo.com/';
/** Responses are tiny; anything larger is treated as malformed. */
export const MAX_WEATHER_BYTES: number = 8192;

export function cityById(id: string): City | undefined {
  return CITIES.find((c: City) => c.id === id);
}

export function cityName(id: string): string {
  const city = cityById(id);
  return city === undefined ? '' : city.name;
}

/** Lower-case and strip the Polish diacritics so "kraków" and "krakow" match. */
export function foldName(text: string): string {
  const map: Record<string, string> = {
    'ą': 'a', 'ć': 'c', 'ę': 'e', 'ł': 'l', 'ń': 'n', 'ó': 'o', 'ś': 's', 'ź': 'z', 'ż': 'z'
  };
  const lower: string = text.toLowerCase().trim();
  let out: string = '';
  for (let i = 0; i < lower.length; i++) {
    const ch: string = lower.charAt(i);
    out += map[ch] !== undefined ? map[ch] : ch;
  }
  return out;
}

/** The bundled city id a piece of text names, or '' when it is not one of them. */
export function cityIdFromText(text: string): string {
  const folded: string = foldName(text);
  const hit = CITIES.find((c: City) => c.id === folded || foldName(c.name) === folded);
  return hit === undefined ? '' : hit.id;
}

/** One city's current weather. */
export interface WeatherReading {
  tempC: number;
  code: number;
  windKmh: number;
  fetchedAt: number;
}

/** WMO weather code -> a short label. */
export function weatherLabel(code: number): string {
  if (code === 0) {
    return 'Clear';
  }
  if (code === 1) {
    return 'Mainly clear';
  }
  if (code === 2) {
    return 'Partly cloudy';
  }
  if (code === 3) {
    return 'Overcast';
  }
  if (code === 45 || code === 48) {
    return 'Fog';
  }
  if (code >= 51 && code <= 57) {
    return 'Drizzle';
  }
  if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) {
    return 'Rain';
  }
  if ((code >= 71 && code <= 77) || code === 85 || code === 86) {
    return 'Snow';
  }
  if (code >= 95) {
    return 'Thunderstorm';
  }
  return 'Unknown';
}

/** The weather symbol bucket, mapped to sys.symbol ids in the view. */
export function weatherSymbolKey(code: number): string {
  if (code === 0 || code === 1) {
    return 'sun';
  }
  if (code === 2) {
    return 'partly';
  }
  if (code === 3 || code === 45 || code === 48) {
    return 'cloud';
  }
  if ((code >= 71 && code <= 77) || code === 85 || code === 86) {
    return 'snow';
  }
  if (code >= 95) {
    return 'storm';
  }
  if (code >= 51) {
    return 'rain';
  }
  return 'cloud';
}

/** "11°C · Partly cloudy · Wind 4 km/h". */
export function weatherValue(r: WeatherReading): string {
  return `${Math.round(r.tempC)}°C · ${weatherLabel(r.code)} · Wind ${Math.round(r.windKmh)} km/h`;
}

/**
 * Strictly reads the Open-Meteo "current" fields we asked for. Returns null on anything unexpected, so the
 * caller shows an honest offline/error state instead of a half-parsed value.
 */
export function parseOpenMeteo(body: string, fetchedAt: number): WeatherReading | null {
  if (body.length === 0 || body.length > MAX_WEATHER_BYTES) {
    return null;
  }
  try {
    const root: Record<string, Object | null> = JSON.parse(body) as Record<string, Object | null>;
    const current: Object | null | undefined = root['current'];
    if (current === null || current === undefined || typeof current !== 'object') {
      return null;
    }
    const c = current as Record<string, Object | null>;
    const temp: Object | null = c['temperature_2m'];
    const code: Object | null = c['weather_code'];
    const wind: Object | null = c['wind_speed_10m'];
    if (typeof temp !== 'number' || !Number.isFinite(temp as number)) {
      return null;
    }
    if (typeof code !== 'number' || !Number.isInteger(code as number)) {
      return null;
    }
    if (typeof wind !== 'number' || !Number.isFinite(wind as number)) {
      return null;
    }
    const t: number = temp as number;
    const w: number = code as number;
    const s: number = wind as number;
    if (t < -90 || t > 70 || w < 0 || w > 99 || s < 0 || s > 500) {
      return null;
    }
    return { tempC: t, code: w, windKmh: s, fetchedAt: fetchedAt };
  } catch (e) {
    return null;
  }
}

/** The key the runtime stores this reading under: one weather component per capsule. */
export function weatherDeviceKey(c: DeviceComponent): string {
  return c.bind;
}
