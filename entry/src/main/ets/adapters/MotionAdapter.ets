/**
 * The phone's accelerometer as one shared subscription (schema permission "motion").
 * ohos.permission.ACCELEROMETER is a normal permission with system_grant (SDK PermissionDefinitions.json),
 * so it is declared in module.json5 and there is no runtime permission dialog.
 *
 * API evidence (DevEco Studio 6.1.1 SDK declarations, API 24):
 *   @kit.SensorServiceKit -> sensor.getSensorList(): Promise<Array<sensor.Sensor>>
 *                            sensor.getSingleSensor(sensor.SensorId.ACCELEROMETER): Promise<sensor.Sensor>
 *                            sensor.on(sensor.SensorId.ACCELEROMETER, cb, { interval: 'ui' })
 *                            sensor.off(sensor.SensorId.ACCELEROMETER, cb)   (callback-specific cleanup)
 * Errors: 201 = permission denied; 14500101 = sensor service exception.
 */
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { sensor } from '@kit.SensorServiceKit';
import { MotionEvent, ShakeDetector } from '../capabilities/ShakeDetector';

const DOMAIN = 0x0001;
const TAG = 'MotionAdapter';

/** 'available' with a working sensor; 'unsupported' when the phone has no accelerometer. */
export type MotionStatus = 'available' | 'unsupported' | 'denied' | 'error';

export class MotionAdapter {
  private status: MotionStatus = 'unsupported';
  private detector: ShakeDetector = new ShakeDetector();
  private callback: ((data: sensor.AccelerometerResponse) => void) | undefined = undefined;
  private running: boolean = false;

  /** Is there an accelerometer on this device? Never assumes one, and never logs raw readings. */
  async probe(): Promise<MotionStatus> {
    try {
      const list: sensor.Sensor[] = await sensor.getSensorList();
      const found: boolean = list.some((s: sensor.Sensor) => s.sensorId === sensor.SensorId.ACCELEROMETER);
      if (!found) {
        this.status = 'unsupported';
        return this.status;
      }
      await sensor.getSingleSensor(sensor.SensorId.ACCELEROMETER);
      this.status = 'available';
    } catch (e) {
      const err = e as BusinessError;
      this.status = err.code === 201 ? 'denied' : 'error';
      hilog.warn(DOMAIN, TAG, 'probe failed: %{public}d %{public}s', err.code, err.message);
    }
    return this.status;
  }

  statusOf(): MotionStatus {
    return this.status;
  }

  isRunning(): boolean {
    return this.running;
  }

  /** Starts the one subscription. Does nothing when already running or when the sensor is not usable. */
  start(onEvent: (e: MotionEvent) => void, onFailure: (s: MotionStatus) => void): void {
    if (this.running || this.status !== 'available') {
      return;
    }
    const options: sensor.Options = { interval: 'ui' };
    const callback = (data: sensor.AccelerometerResponse): void => {
      const events: MotionEvent[] = this.detector.sample(data.x, data.y, data.z, Date.now());
      events.forEach((e: MotionEvent) => onEvent(e));
    };
    try {
      sensor.on(sensor.SensorId.ACCELEROMETER, callback, options);
      this.callback = callback;
      this.running = true;
    } catch (e) {
      const err = e as BusinessError;
      this.status = err.code === 201 ? 'denied' : 'error';
      hilog.warn(DOMAIN, TAG, 'subscribe failed: %{public}d %{public}s', err.code, err.message);
      onFailure(this.status);
    }
  }

  /** Stops and unsubscribes this adapter's callback only, so other listeners are never removed. */
  stop(): void {
    if (!this.running || this.callback === undefined) {
      return;
    }
    try {
      sensor.off(sensor.SensorId.ACCELEROMETER, this.callback);
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'unsubscribe failed: %{public}d %{public}s', err.code, err.message);
    }
    this.callback = undefined;
    this.running = false;
    this.detector.reset();
  }
}
