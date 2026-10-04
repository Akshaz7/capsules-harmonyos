/**
 * Pure consent rules shared by the gatekeeper (T4-13). A grant list is the permissions the user allowed for one
 * capsule; these helpers never change their input.
 */
import { Permission } from './CapsuleTypes';

/** "Show on another device" may send without asking only once the user allowed "devices" for this capsule. */
export function canSendToDevice(grants: string[]): boolean {
  return grants.includes('devices');
}

/** The grants with `p` added (once). */
export function grantsWith(grants: string[], p: Permission): string[] {
  return grants.includes(p) ? grants.slice() : grants.concat([p]);
}

/** The grants without `p` (undo). */
export function grantsWithout(grants: string[], p: Permission): string[] {
  return grants.filter((g: string) => g !== p);
}
