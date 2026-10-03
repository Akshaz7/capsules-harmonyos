/**
 * Motion and haptics for the home polish (UI-1). Everything decorative checks reduceMotion() first:
 * no springs, shimmer, typing or moving gradient when the system's "reduce animations" setting is on.
 */
import { accessibility } from '@kit.AccessibilityKit';
import { curves } from '@kit.ArkUI';
import { vibrator } from '@kit.SensorServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

/** The system setting (API 23+). Older systems have no such switch: motion stays on. */
export function reduceMotion(): boolean {
  try {
    return accessibility.isAnimationReduceEnabledSync();
  } catch (e) {
    return false;
  }
}

/** A soft spring for presses and arrivals; a plain ease when motion is reduced. */
export function springCurve(): ICurve | Curve {
  return reduceMotion() ? Curve.EaseOut : curves.springMotion(0.42, 0.78);
}

/** One short tick on success (needs ohos.permission.VIBRATE, a normal permission granted at install). */
export function successTick(): void {
  try {
    vibrator.startVibration({ type: 'time', duration: 30 }, { id: 0, usage: 'notification' })
      .catch((e: BusinessError) => hilog.warn(0x0001, 'Motion', 'vibrate failed: %{public}d', e.code));
  } catch (e) {
    hilog.warn(0x0001, 'Motion', 'vibrate unavailable');
  }
}
