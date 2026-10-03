/**
 * Hook for the on-device model to fill template slots the rules left unclear, in the same style as the
 * Cactus slot-filling (CactusProvider.ets): one line of JSON, <placeholders> instead of example values to copy,
 * and grounding (every word slot shares a word with the request, every number appears in it). Anything the
 * model gets wrong is dropped and the rules' values stay, so this can only improve a match, never break it.
 *
 * The model itself is plugged in by the caller (T4 wires CactusProvider):
 *   const better = await fillUnclearSlots(match, request, (prompt) => runOnDevice(prompt, 120));
 */
import { fillTemplate, foldText, SlotValue, TemplateEntry, TemplateMatch, TemplateSlot } from './TemplateLibrary';

/** Runs one prompt on the on-device model and returns its raw reply. May throw. */
export type SlotModel = (prompt: string) => Promise<string>;

function placeholder(slot: TemplateSlot): string {
  switch (slot.kind) {
    case 'number':
      return 'NUMBER';
    case 'list':
      return '[ITEM]';
    default:
      return 'NAME';
  }
}

/** The prompt for the unclear slots only. The request goes last, as in the Cactus prompts. */
export function slotPrompt(template: TemplateEntry, request: string, slots: string[]): string {
  const wanted = template.slots.filter((s: TemplateSlot) => slots.indexOf(s.name) >= 0);
  const shape = wanted.map((s: TemplateSlot) => `"${s.name}":${placeholder(s)}`).join(',');
  const notes = wanted.map((s: TemplateSlot) => {
    const hint = (s.hints ?? []).length > 0 ? ` (${(s.hints ?? []).join(', ')})` : '';
    return `${s.name}: ${s.kind}${hint}`;
  }).join('\n');
  return `Fill the details of a "${template.name}" app from the request. Reply with ONE line of JSON only, ` +
    `no prose, no code fences: {${shape}}\n${notes}\n` +
    'Use only words and numbers from the request. Leave out a key if the request does not say it.\n' +
    `Request: ${request.trim()} ->`;
}

function grounded(value: SlotValue, requestFolded: string, requestNumbers: number[]): boolean {
  if (typeof value === 'number') {
    return requestNumbers.indexOf(value as number) >= 0;
  }
  const items: string[] = Array.isArray(value) ? value as string[] : [value as string];
  return items.length > 0 && items.every((v: string) => {
    const ws = foldText(String(v)).split(/[^a-z0-9㐀-鿿]+/).filter((w: string) => w.length > 0);
    return ws.length > 0 && ws.some((w: string) => requestFolded.indexOf(w) >= 0);
  });
}

/** Reads the model's reply: the first {...} object; keeps only grounded values of the asked slots. */
export function parseSlotReply(reply: string, template: TemplateEntry, request: string, slots: string[]):
  Record<string, SlotValue> {
  const out: Record<string, SlotValue> = {};
  const start = reply.indexOf('{');
  const end = reply.indexOf('}', start);
  if (start < 0 || end < 0) {
    return out;
  }
  let obj: Record<string, Object>;
  try {
    obj = JSON.parse(reply.substring(start, end + 1)) as Record<string, Object>;
  } catch (e) {
    return out;
  }
  const folded = foldText(request);
  const numbers = (folded.match(/\d+(?:\.\d+)?/g) ?? []).map((n: string) => Number(n));
  template.slots.filter((s: TemplateSlot) => slots.indexOf(s.name) >= 0).forEach((s: TemplateSlot) => {
    const v = obj[s.name];
    let value: SlotValue | undefined = undefined;
    if (s.kind === 'number' && typeof v === 'number') {
      value = v as number;
    } else if (s.kind === 'number' && typeof v === 'string' && /^\d+(\.\d+)?$/.test(v as string)) {
      value = Number(v as string);
    } else if (s.kind === 'list' && Array.isArray(v)) {
      value = (v as Object[]).filter((x: Object) => typeof x === 'string').map((x: Object) => x as string);
    } else if (s.kind === 'text' && typeof v === 'string') {
      value = v as string;
    }
    if (value !== undefined && grounded(value, folded, numbers)) {
      out[s.name] = value;
    }
  });
  return out;
}

/**
 * Asks the model for the match's unclear slots and refills the template. Returns the match unchanged when
 * nothing is unclear, the model fails, or its values are ungrounded or make the capsule invalid.
 */
export async function fillUnclearSlots(match: TemplateMatch, request: string, model: SlotModel): Promise<TemplateMatch> {
  if (match.unfilledSlots.length === 0) {
    return match;
  }
  let reply = '';
  try {
    reply = await model(slotPrompt(match.template, request, match.unfilledSlots));
  } catch (e) {
    return match;
  }
  const extra = parseSlotReply(reply, match.template, request, match.unfilledSlots);
  const names = Object.keys(extra);
  if (names.length === 0) {
    return match;
  }
  const given: Record<string, SlotValue> = {};
  match.template.slots.forEach((s: TemplateSlot) => {
    if (extra[s.name] !== undefined) {
      given[s.name] = extra[s.name];
    } else if (match.unfilledSlots.indexOf(s.name) < 0) {
      given[s.name] = match.values[s.name];
    }
  });
  const f = fillTemplate(match.template, request, given);
  if (f.capsule === undefined) {
    return match;
  }
  return {
    capsule: f.capsule, score: match.score, template: match.template, values: f.values,
    unfilledSlots: match.unfilledSlots.filter((n: string) => names.indexOf(n) < 0)
  };
}
