/**
 * The install token: who this app install is, for the device relay and the marketplace API (same header,
 * same token). Made on first use from a cryptographic random source (32 bytes, base64url, 43 characters),
 * kept in Preferences and reused. It is a secret: whoever holds it controls the paired devices. Never log
 * it, never put it in a capsule or a shared file, never commit it.
 */
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0001;
const TAG = 'InstallToken';
const STORE = 'install';
const TOKEN_KEY = 'token';
const MARKETPLACE_TOKEN_KEY = 'marketplaceToken';
const TOKEN_BYTES = 32;
const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

/** The request header that carries the token. */
export const TOKEN_HEADER = 'X-Harmoniser-Token';

/** base64url without padding. */
export function toBase64Url(bytes: Uint8Array): string {
  let out = '';
  for (let i = 0; i < bytes.length; i += 3) {
    const b0 = bytes[i];
    const b1 = i + 1 < bytes.length ? bytes[i + 1] : 0;
    const b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;
    out += ALPHABET.charAt(b0 >> 2);
    out += ALPHABET.charAt(((b0 & 3) << 4) | (b1 >> 4));
    if (i + 1 < bytes.length) {
      out += ALPHABET.charAt(((b1 & 15) << 2) | (b2 >> 6));
    }
    if (i + 2 < bytes.length) {
      out += ALPHABET.charAt(b2 & 63);
    }
  }
  return out;
}

/** 43+ characters of A-Z a-z 0-9 - _ (at least 32 random bytes). */
export function isValidInstallToken(token: string): boolean {
  return /^[A-Za-z0-9_-]{43,}$/.test(token);
}

const cache: Map<string, string> = new Map();

function tokenFor(ctx: common.Context, key: string): string {
  const known = cache.get(key);
  if (known !== undefined) {
    return known;
  }
  try {
    const prefs = preferences.getPreferencesSync(ctx, { name: STORE } as preferences.Options);
    const saved = prefs.getSync(key, '') as string;
    if (isValidInstallToken(saved)) {
      cache.set(key, saved);
      return saved;
    }
    const random = cryptoFramework.createRandom().generateRandomSync(TOKEN_BYTES);
    const token = toBase64Url(random.data);
    prefs.putSync(key, token);
    prefs.flushSync();
    cache.set(key, token);
    hilog.info(DOMAIN, TAG, 'made a new %{public}s (%{public}d chars)', key, token.length); // never the token
    return token;
  } catch (e) {
    hilog.error(DOMAIN, TAG, '%{public}s failed: %{public}s', key, (e as BusinessError).message);
    return '';
  }
}

/** The relay install token, made and saved on first use. '' only if the random source or Preferences fail. */
export function getInstallToken(ctx: common.Context): string {
  return tokenFor(ctx, TOKEN_KEY);
}

/**
 * The marketplace owner token: one token for every marketplace call (publish, delete, install, report), and
 * separate from the relay's. It is the only way to delete what this install published.
 */
export function getMarketplaceToken(ctx: common.Context): string {
  return tokenFor(ctx, MARKETPLACE_TOKEN_KEY);
}
