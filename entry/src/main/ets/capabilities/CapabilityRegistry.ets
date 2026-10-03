/**
 * The single typed list of host capabilities capsules may use. Pure data and small helpers only, so the
 * core (generator prompt), the pages (consent and status) and the adapters all read the same source.
 *
 * "implemented" is what the app actually does today: only implemented capabilities are advertised to the
 * generator and offered to capsules. Everything else stays documented here as planned, never advertised.
 * OS permissions and grant modes come from the installed SDK: toolchains/lib/PermissionDefinitions.json
 * and the @ohos.* declarations of DevEco Studio 6.1.1 (API 24).
 */

export type CapabilityId = 'motion' | 'battery' | 'weather' | 'location' | 'gyroscope' | 'pedometer';

/** How the OS grants a permission (SDK PermissionDefinitions.json). */
export type GrantMode = 'system_grant' | 'user_grant' | 'none';

export interface OsPermission {
  /** e.g. 'ohos.permission.ACCELEROMETER'. */
  name: string;
  grantMode: GrantMode;
  /** First API version of the declaration we use, from the installed SDK. */
  minApi: number;
}

export interface Capability {
  id: CapabilityId;
  /** Permission id inside the capsule JSON, or '' when capsules cannot use it. */
  schemaPermission: string;
  label: string;
  rationale: string;
  osPermissions: OsPermission[];
  minApi: number;
  /** '' when every phone has it. */
  hardware: string;
  /** True only when the app implements it end to end. */
  implemented: boolean;
  foregroundOnly: boolean;
  /** What it reads or sends, in one line, for consent copy and review. */
  disclosure: string;
  rateLimits: string;
  /** Noun phrase for prose, e.g. "the motion sensor"; used in the generator's plan prompt. */
  prose: string;
  /** One line for the generator prompt; only implemented capabilities are advertised. */
  generatorText: string;
}

const MOTION: Capability = {
  id: 'motion',
  schemaPermission: 'motion',
  label: 'Motion sensor',
  rationale: 'React to shaking the phone while a capsule is open. It does not count steps or reps.',
  osPermissions: [{ name: 'ohos.permission.ACCELEROMETER', grantMode: 'system_grant', minApi: 9 }],
  minApi: 9,
  hardware: 'accelerometer',
  implemented: true,
  foregroundOnly: true,
  disclosure: 'Acceleration is read in memory while the capsule is open. Raw samples are never stored or sent.',
  rateLimits: 'one subscription; about 6 counted shakes a second at most; a trigger fires once per shake burst',
  prose: 'the motion sensor (it reacts to shakes while a capsule is open, not to steps or reps)',
  generatorText: 'a counter with source "motion" counts shakes while the capsule is open (never steps, reps or ' +
    'distance), and a "motion" trigger runs once each time shaking starts; needs permission "motion"'
};

const BATTERY: Capability = {
  id: 'battery',
  schemaPermission: 'battery',
  label: 'Battery',
  rationale: 'Show the phone\'s battery level and charging state while the capsule is open.',
  osPermissions: [],
  minApi: 12,
  hardware: '',
  implemented: true,
  foregroundOnly: true,
  disclosure: 'The battery level and charging state are read on the phone. Nothing is sent anywhere.',
  rateLimits: 'read when the capsule opens and when the app returns to the foreground only',
  prose: 'the phone\'s battery level and charging state',
  generatorText: 'a device reading { "type": "device", "bind": "battery" } shows the battery level and whether ' +
    'it is charging; needs permission "battery"'
};

const WEATHER: Capability = {
  id: 'weather',
  schemaPermission: 'weather',
  label: 'Weather',
  rationale: 'Show current weather for a city you pick, fetched from Open-Meteo.',
  osPermissions: [{ name: 'ohos.permission.INTERNET', grantMode: 'system_grant', minApi: 9 }],
  minApi: 9,
  hardware: '',
  implemented: true,
  foregroundOnly: true,
  disclosure: 'Only the chosen city\'s coordinates are sent to Open-Meteo (open-meteo.com). Capsule text, state ' +
    'and identifiers never leave the phone.',
  rateLimits: 'one fetch per city per 15 minutes; a manual refresh is at least 60 seconds after the last one',
  prose: 'a weather reading from Open-Meteo for a city the user picks',
  generatorText: 'a device reading { "type": "device", "bind": "weather", "city"?: one of the bundled city ids } ' +
    'shows the current temperature, conditions and wind from Open-Meteo; needs permission "weather"'
};

const LOCATION: Capability = {
  id: 'location',
  schemaPermission: 'location',
  label: 'Approximate location',
  rationale: 'Planned: weather for where you are, using city-level coordinates only.',
  osPermissions: [
    { name: 'ohos.permission.APPROXIMATELY_LOCATION', grantMode: 'user_grant', minApi: 9 },
    { name: 'ohos.permission.LOCATION', grantMode: 'user_grant', minApi: 7 }
  ],
  minApi: 9,
  hardware: '',
  implemented: false,
  foregroundOnly: true,
  disclosure: 'Not built yet. If added, only an approximate, ephemeral location would be used, with its own consent.',
  rateLimits: 'not built',
  prose: 'not available',
  generatorText: 'not available'
};

const GYROSCOPE: Capability = {
  id: 'gyroscope',
  schemaPermission: '',
  label: 'Gyroscope',
  rationale: 'Planned: tilt and rotation effects.',
  osPermissions: [{ name: 'ohos.permission.GYROSCOPE', grantMode: 'system_grant', minApi: 9 }],
  minApi: 9,
  hardware: 'gyroscope',
  implemented: false,
  foregroundOnly: true,
  disclosure: 'Not built yet.',
  rateLimits: 'not built',
  prose: 'not available',
  generatorText: 'not available'
};

const PEDOMETER: Capability = {
  id: 'pedometer',
  schemaPermission: '',
  label: 'Step count (system)',
  rationale: 'Planned: the phone\'s own step counter, once it is verified on real hardware.',
  osPermissions: [{ name: 'ohos.permission.ACTIVITY_MOTION', grantMode: 'user_grant', minApi: 7 }],
  minApi: 9,
  hardware: 'step counter sensor',
  implemented: false,
  foregroundOnly: true,
  disclosure: 'Not built yet. Shaking the phone is not a step count.',
  rateLimits: 'not built',
  prose: 'not available',
  generatorText: 'not available'
};

/** The catalogue, in the order the app presents it. */
export const CAPABILITIES: Capability[] = [MOTION, BATTERY, WEATHER, LOCATION, GYROSCOPE, PEDOMETER];

export function capabilityById(id: string): Capability | undefined {
  return CAPABILITIES.find((c: Capability) => c.id === id);
}

/** Only what the app really does; the generator prompt is built from this. */
export function implementedCapabilities(): Capability[] {
  return CAPABILITIES.filter((c: Capability) => c.implemented);
}

/** The prompt section that tells the model which device capabilities exist. */
export function generatorCapabilitiesText(): string {
  return implementedCapabilities().map((c: Capability) => `- ${c.generatorText}`).join('\n');
}

/** "the motion sensor ... and the phone's battery ..." for the plan prompt's prose. */
export function implementedCapabilityProse(): string {
  const parts: string[] = implementedCapabilities().map((c: Capability) => c.prose);
  if (parts.length === 0) {
    return 'nothing else';
  }
  if (parts.length === 1) {
    return parts[0];
  }
  return `${parts.slice(0, parts.length - 1).join(', ')} and ${parts[parts.length - 1]}`;
}
