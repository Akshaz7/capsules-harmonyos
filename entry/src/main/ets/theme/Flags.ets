/**
 * Redesign switches, one per area. When a switch is false, that area renders exactly as before.
 * At the code freeze, anything unfinished is set to false here.
 */
export class Flags {
  static readonly NEW_THEME: boolean = true;
  static readonly NEW_SHELL: boolean = true;
  static readonly NEW_FRAME: boolean = true;
  static readonly NEW_PATTERNS: boolean = true; // only FINISHED_PATTERNS (emulator-passed, T6-11) use it; the rest stay classic
  static readonly NEW_CREATE: boolean = false;
  static readonly NEW_PROGRESS: boolean = true;
  static readonly NEW_CONSENT: boolean = true;
  static readonly NEW_CAPSULES: boolean = true;
  static readonly NEW_MARKET: boolean = true;
  static readonly NEW_SETTINGS: boolean = true;
  static readonly NEW_LOG: boolean = true;
  static readonly NEW_SNAP: boolean = true;
  static readonly NEW_SHARE: boolean = true;
  static readonly NEW_WIDE: boolean = true;
  static readonly NEW_ERRORS: boolean = true;
  /** T3-28: the live build card (step line + shimmering skeleton + Cancel) on both Create layouts. */
  static readonly NEW_BUILD_LIVE: boolean = true;
  /** T3-29: Snap (camera) on Create. Off: the dictation mic takes its place; the Snap code stays. */
  static readonly CREATE_SNAP: boolean = false;
  /** The old Create layout (NEW_CREATE false) in the new theme. Off until the user has checked it. */
  static readonly NEW_CREATE_CLASSIC: boolean = false;
  /** Create screen extras: the Recent row and the suggestion chips (off: brand, question, prompt bar only). */
  static readonly CREATE_RECENT: boolean = false;
  static readonly CREATE_SUGGESTIONS: boolean = false;
}
