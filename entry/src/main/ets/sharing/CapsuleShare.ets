/**
 * Pure sharing logic for schema v0 capsules: export a capsule as JSON text and
 * prepare JSON text from someone else as an import.
 *
 * No UI and no system APIs live here, so the local unit tests can run it directly.
 * prepareImport never saves anything: it only validates, re-identifies and returns
 * a capsule for the consent screen. Grants are never carried over, because the
 * validator rebuilds the capsule from the fields SCHEMA.md allows and the fresh id
 * means the gatekeeper has no stored approval for it.
 */
import { Capsule, ValidationResult } from '../core/CapsuleTypes';
import { validateCapsule } from '../core/CapsuleValidator';

/** Largest accepted capsule file, in UTF-8 bytes (not string length). */
export const MAX_SHARE_BYTES: number = 8192;

const TOO_LARGE: string = 'File too large (max 8 KB)';
const EMPTY_FILE: string = 'The file is empty';
const NOT_JSON: string = 'This file is not valid JSON';

type JsonValue = Object | null | undefined;

/** A capsule from someone else, ready for the consent screen. */
export interface PreparedImport {
  capsule: Capsule;
  json: string;
}

/** Result of prepareImport: either a prepared capsule or one clear error message. */
export interface ImportResult {
  ok: boolean;
  capsule?: Capsule;
  json?: string;
  error?: string;
}

/**
 * UTF-8 byte length of a string. Written by hand (no TextEncoder) so it also runs
 * in local unit tests, and so an emoji counts as the 4 bytes it really takes.
 */
export function utf8ByteLength(text: string): number {
  let bytes: number = 0;
  for (let i = 0; i < text.length; i++) {
    const code: number = text.charCodeAt(i);
    if (code < 0x80) {
      bytes += 1;
    } else if (code < 0x800) {
      bytes += 2;
    } else if (code >= 0xd800 && code <= 0xdbff) {
      const next: number = i + 1 < text.length ? text.charCodeAt(i + 1) : 0;
      if (next >= 0xdc00 && next <= 0xdfff) {
        bytes += 4;
        i++;
      } else {
        bytes += 3;
      }
    } else {
      bytes += 3;
    }
  }
  return bytes;
}

/** A fresh capsule id. The sender's id is never reused. */
function freshId(): string {
  const time: string = Date.now().toString(36);
  const random: string = Math.floor(Math.random() * 0x100000000).toString(36);
  return `imported-${time}-${random}`;
}

/** The capsule as compact JSON: exactly what a shared .json file carries. */
export function exportCapsuleJson(capsule: Capsule): string {
  return JSON.stringify(capsule);
}

/**
 * Turns text from a .json file or a static QR code into a capsule for the consent
 * screen. Steps, in order: (1) reject anything over MAX_SHARE_BYTES; (2) reject
 * empty or non-JSON text; (3) run validateCapsule and return its message when the
 * capsule is invalid; (4) replace the id with a fresh one.
 */
export function prepareImport(rawText: string): ImportResult {
  if (utf8ByteLength(rawText) > MAX_SHARE_BYTES) {
    return { ok: false, error: TOO_LARGE };
  }
  const text: string = rawText.trim();
  if (text.length === 0) {
    return { ok: false, error: EMPTY_FILE };
  }
  let parsed: JsonValue = undefined;
  try {
    parsed = JSON.parse(text) as JsonValue;
  } catch (e) {
    return { ok: false, error: NOT_JSON };
  }
  if (parsed === undefined) {
    return { ok: false, error: NOT_JSON };
  }
  const validated: ValidationResult = validateCapsule(text);
  if (!validated.ok || validated.capsule === undefined) {
    return { ok: false, error: `Not a valid capsule. ${validated.errors.join(' ')}` };
  }
  // The validator rebuilds the capsule from the accepted fields only, so unknown
  // fields (anything grant-shaped, for example) were already rejected above.
  const capsule: Capsule = validated.capsule;
  capsule.id = freshId();
  return { ok: true, capsule: capsule, json: JSON.stringify(capsule) };
}

/**
 * Hands a prepared import to the app through `deliver`. Returns false and calls
 * nothing when the result is an error. This never saves the capsule: the app
 * decides that when the user runs it.
 */
export function onImported(prepared: ImportResult, deliver: (payload: PreparedImport) => void): boolean {
  if (!prepared.ok || prepared.capsule === undefined || prepared.json === undefined) {
    return false;
  }
  deliver({ capsule: prepared.capsule, json: prepared.json });
  return true;
}
