/**
 * Redesign switches, one per area. When a switch is false, that area renders exactly as before.
 * At the code freeze, anything unfinished is set to false here.
 */
export class Flags {
  static readonly NEW_THEME: boolean = true;
  static readonly NEW_SHELL: boolean = true;
  static readonly NEW_FRAME: boolean = true;
  static readonly NEW_PATTERNS: boolean = true;
  static readonly NEW_CREATE: boolean = true;
  static readonly NEW_PROGRESS: boolean = true;
  static readonly NEW_CONSENT: boolean = true;
  static readonly NEW_CAPSULES: boolean = true;
  static readonly NEW_MARKET: boolean = true;
  static readonly NEW_SETTINGS: boolean = true;
  static readonly NEW_LOG: boolean = true;
  static readonly NEW_SNAP: boolean = true;
  static readonly NEW_SHARE: boolean = true;
  static readonly NEW_WIDE: boolean = true;
}
