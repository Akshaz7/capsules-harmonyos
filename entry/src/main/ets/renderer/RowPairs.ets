import { CapsuleComponent } from '../core/CapsuleTypes';

/** A row's children two at a time (the last pair may hold one). */
export function rowPairs(items: CapsuleComponent[]): CapsuleComponent[][] {
  const out: CapsuleComponent[][] = [];
  for (let i = 0; i < items.length; i += 2) {
    out.push(items.slice(i, i + 2));
  }
  return out;
}
