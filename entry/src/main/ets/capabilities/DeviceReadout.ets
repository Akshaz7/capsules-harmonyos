/**
 * Read-only host readings shown by "device" components. Pure data and formatting, so it is unit-tested
 * without platform APIs. A reading is host state, never capsule state: nothing here can be written by the
 * capsule's buttons or triggers.
 */

import { DeviceComponent } from '../core/CapsuleTypes';

export type DeviceState = 'pending' | 'ok' | 'stale' | 'offline' | 'unavailable';

export interface DeviceReadout {
  state: DeviceState;
  /** Card label, e.g. "Battery" or the chosen city; '' falls back to the component's label. */
  title: string;
  /** The main line, e.g. "72% · Charging" or "11°C · Partly cloudy". */
  value: string;
  /** The second line, e.g. "Updated 00:45". */
  detail: string;
  /** Attribution, e.g. "Weather data by Open-Meteo.com"; '' when there is none. */
  source: string;
  /* Field values, for the icon and tests. */
  percent: number;
  charging: boolean;
  weatherCode: number;
}

export function emptyReadout(): DeviceReadout {
  return {
    state: 'pending', title: '', value: '', detail: '', source: '', percent: -1, charging: false, weatherCode: -1
  };
}

/** The runtime stores one reading per bind ('battery', 'weather'); weather has at most one per capsule. */
export function deviceKey(c: DeviceComponent): string {
  return c.bind;
}

/** "72%" or "72% · Charging". */
export function batteryValue(soc: number, charging: boolean): string {
  return charging ? `${soc}% · Charging` : `${soc}%`;
}

/** "Charging" or "Not charging". */
export function batteryDetail(charging: boolean): string {
  return charging ? 'Charging' : 'Not charging';
}
