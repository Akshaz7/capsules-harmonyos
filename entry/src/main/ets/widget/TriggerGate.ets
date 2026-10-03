/**
 * The app's Gatekeeper as a core TriggerGuard, so triggers run through the same per-capsule grants and
 * block log as buttons. A trigger whose permission was not granted is refused (Gatekeeper.isAllowed);
 * v0 actions go through Gatekeeper.allowAction, which logs anything it blocks.
 */
import { Capsule, Permission, Trigger } from '../core/CapsuleTypes';
import { TriggerGuard } from '../core/Triggers';
import { Gatekeeper } from '../gatekeeper/Gatekeeper';

export class GatekeeperTriggerGuard implements TriggerGuard {
  private gate: Gatekeeper;

  constructor(gate: Gatekeeper) {
    this.gate = gate;
  }

  allowTrigger(capsule: Capsule, trigger: Trigger, permission: Permission): boolean {
    return !this.gate.isRemoved(capsule.id) && this.gate.isAllowed(capsule, permission);
  }

  allowAction(capsule: Capsule, action: string): boolean {
    return this.gate.allowAction(capsule, action);
  }
}
