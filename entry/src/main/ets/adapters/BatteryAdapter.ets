/**
 * The phone's battery level and charging state (@kit.BasicServicesKit batteryInfo).
 *
 * API evidence (DevEco Studio 6.1.1 SDK declarations, API 24, @ohos.batteryInfo.d.ts):
 *   batteryInfo.batterySOC: number                       (percentage)
 *   batteryInfo.chargingStatus: BatteryChargeState       (NONE | ENABLE | DISABLE)
 * The documented read-only properties need no OS permission; capsule consent still applies.
 * Read-only: no power-management calls of any kind live here.
 */
import { batteryInfo } from '@kit.BasicServicesKit';

export type BatteryState = 'ok' | 'unavailable';

export interface BatteryReading {
  state: BatteryState;
  soc: number;
  charging: boolean;
}

export class BatteryAdapter {
  /** One on-demand read. Never throws; an unreadable battery stays 'unavailable'. */
  read(): BatteryReading {
    try {
      const raw: number = batteryInfo.batterySOC;
      if (!Number.isFinite(raw) || raw < 0) {
        return { state: 'unavailable', soc: 0, charging: false };
      }
      const soc: number = Math.max(0, Math.min(100, Math.round(raw)));
      const charging: boolean = batteryInfo.chargingStatus === batteryInfo.BatteryChargeState.ENABLE;
      return { state: 'ok', soc: soc, charging: charging };
    } catch (e) {
      return { state: 'unavailable', soc: 0, charging: false };
    }
  }
}
