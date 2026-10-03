import { Capsule, CapsuleComponent, CapsuleRoute, CounterComponent } from '../core';
import { CapsuleRuntime } from '../renderer/CapsuleRuntime';

/** One saved, approved capsule plus its live runtime and widget route. */
@ObservedV2
export class CapsuleEntry {
  /** Traced: editing a capsule's triggers swaps it in place, and an open capsule page must follow. */
  @Trace capsule: Capsule;
  /** Traced: an edit (Change it…) can change where the capsule fits. */
  @Trace route: CapsuleRoute;
  readonly origin: string;
  @Trace runtime: CapsuleRuntime;

  constructor(capsule: Capsule, route: CapsuleRoute, runtime: CapsuleRuntime, origin: string) {
    this.capsule = capsule;
    this.route = route;
    this.runtime = runtime;
    this.origin = origin;
  }
}

/** T3-17: the consent sheet line for capsules a template (or a community capsule) explained. */
export const BUILT_FROM_TEMPLATE = 'Built from a template';
export const BUILT_FROM_COMMUNITY = 'Built from a community capsule';

/** 'cloud', 'cloud-eu:<provider>' or 'cloud:<provider>'. */
export function isCloudOrigin(origin: string): boolean {
  return origin === 'cloud' || origin.startsWith('cloud-eu:') || origin.startsWith('cloud:');
}

/** Badge text for a stored GenerateResult.origin; '' for capsules saved before origins were kept. */
export function originBadge(origin: string): string {
  switch (origin) {
    case 'rules':
      return 'Made by rules';
    case 'on-device':
      return 'Made on-device';
    case 'template':
      return 'Made on your phone · no internet';
    case 'cloud-eu:mistral':
    case 'cloud': // saved before core named the provider; only Mistral was used then
      return 'Made with Mistral (EU)';
    case 'cloud:anthropic':
      return 'Made with Claude';
    case 'cloud:openai':
      return 'Made with OpenAI';
    case 'imported':
      return 'From someone else';
    case 'marketplace':
      return 'From the marketplace';
    case 'community': // T3-17: a marketplace capsule matched to a request (T6-5)
      return 'Made from a community capsule';
    default:
      return '';
  }
}

export function originIcon(origin: string): Resource {
  if (origin === 'rules') {
    return $r('sys.symbol.list_bullet');
  }
  if (isCloudOrigin(origin)) {
    return $r('sys.symbol.cloud');
  }
  if (origin === 'imported') {
    return $r('sys.symbol.arrow_down_circle');
  }
  if (origin === 'marketplace') {
    return $r('sys.symbol.bag');
  }
  return $r('sys.symbol.wand_and_stars');
}

/** Icon for a capsule, picked from its name first, then its main component type. */
export function capsuleIcon(capsule: Capsule): Resource {
  const name = capsule.name.toLowerCase();
  if (name.includes('water') || name.includes('drink')) {
    return $r('sys.symbol.drop');
  }
  if (name.includes('squat') || name.includes('workout') || name.includes('push')) {
    return $r('sys.symbol.dumbbell');
  }
  if (name.includes('coffee') || name.includes('tea')) {
    return $r('sys.symbol.cup');
  }
  const types = capsule.ui.map((c: CapsuleComponent) => c.type);
  if (types.includes('timer')) {
    return $r('sys.symbol.timer');
  }
  if (types.includes('checklist')) {
    return $r('sys.symbol.checkmark_circle');
  }
  const counter = capsule.ui.find((c: CapsuleComponent) => c.type === 'counter');
  if (counter) {
    return (counter as CounterComponent).source === 'motion' ? $r('sys.symbol.figure_walk') :
    $r('sys.symbol.plus_circle');
  }
  if (types.includes('number')) {
    return $r('sys.symbol.list_number');
  }
  return $r('sys.symbol.doc_text');
}

/** Short, friendly version of the router's decision. */
export function routeHeadline(route: CapsuleRoute): string {
  return route.widget ? 'Simple enough for a widget' : 'Opens in the app';
}
