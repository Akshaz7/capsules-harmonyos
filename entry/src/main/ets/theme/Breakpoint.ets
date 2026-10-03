import { mediaquery } from '@kit.ArkUI';

/** AppStorage key holding the window's width class: 'phone' (< 600vp) or 'wide' (600vp and up). */
export const WIDTH_CLASS_KEY = 'widthClass';
export const WIDE_MIN_VP = 600;

export type WidthClass = 'phone' | 'wide';

export function widthClassFor(widthVp: number): WidthClass {
  return widthVp >= WIDE_MIN_VP ? 'wide' : 'phone';
}

/** The current width class (phone until the root has measured). */
export function widthClass(): WidthClass {
  return (AppStorage.get<string>(WIDTH_CLASS_KEY) ?? 'phone') === 'wide' ? 'wide' : 'phone';
}

/**
 * Watches the window width and keeps WIDTH_CLASS_KEY current. Call once from the root page with its
 * UIContext; keep the returned listener alive (and off() it when the page goes away).
 */
export function watchWidthClass(ui: UIContext): mediaquery.MediaQueryListener {
  const listener = ui.getMediaQuery().matchMediaSync(`(width >= ${WIDE_MIN_VP}vp)`);
  AppStorage.setOrCreate<string>(WIDTH_CLASS_KEY, listener.matches ? 'wide' : 'phone');
  listener.on('change', (r: mediaquery.MediaQueryResult) => {
    AppStorage.setOrCreate<string>(WIDTH_CLASS_KEY, r.matches ? 'wide' : 'phone');
  });
  return listener;
}

/** Same rule from a measured width, for a root onAreaChange. */
export function storeWidthClass(widthVp: number): void {
  AppStorage.setOrCreate<string>(WIDTH_CLASS_KEY, widthClassFor(widthVp));
}
