import { Want } from '@kit.AbilityKit';
import { AppStorageV2 } from '@kit.ArkUI';
import { CHOOSE_CAPSULE_ACTION, WIDGET_SOURCE } from '../widget/WidgetService';

/** Hands a blank widget's "choose a capsule" tap from EntryAbility to the Index page. */
@ObservedV2
export class WidgetLaunch {
  /** The blank widget waiting for a capsule; '' when none. */
  @Trace formId: string = '';
}

export function widgetLaunch(): WidgetLaunch {
  return AppStorageV2.connect(WidgetLaunch, 'widgetLaunch', () => new WidgetLaunch())!;
}

/** Records the widget if `want` came from a blank widget: { source: 'harmoniser', action: 'chooseCapsule', formId }. */
export function takeWidgetWant(want: Want): void {
  const params = want.parameters;
  if (params === undefined || params['source'] !== WIDGET_SOURCE || params['action'] !== CHOOSE_CAPSULE_ACTION) {
    return;
  }
  const formId = params['formId'];
  if (typeof formId === 'string' && formId.length > 0) {
    widgetLaunch().formId = formId;
  }
}
