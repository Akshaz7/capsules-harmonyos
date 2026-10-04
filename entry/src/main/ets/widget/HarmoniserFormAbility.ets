import { Want } from '@kit.AbilityKit';
import { formBindingData, FormExtensionAbility, formInfo } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { markFormProcess, removeBinding } from './WidgetStore';
import { sizeForDimension } from '../core/WidgetModel';
import { bindForm, bindingData, handleWidgetMessage, refreshCapsuleWidgets, viewFor } from './WidgetService';

const DOMAIN = 0x0002;
const TAG = 'HarmoniserForm';

// This module only loads in the widget's own process: read the app's stores from disk here.
markFormProcess();

/** Provider for the Harmoniser widget: one capsule per widget, 2x2 or 2x4. */
export default class HarmoniserFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const params = want.parameters ?? {};
    const formId = String(params[formInfo.FormParam.IDENTITY_KEY] ?? '');
    const size = sizeForDimension(Number(params[formInfo.FormParam.DIMENSION_KEY] ?? 2));
    const binding = bindForm(this.context, formId, size);
    hilog.info(DOMAIN, TAG, 'onAddForm %{public}s size=%{public}s', formId, size);
    return bindingData(viewFor(this.context, binding));
  }

  onUpdateForm(formId: string): void {
    refreshCapsuleWidgets(this.context);
  }

  onChangeFormVisibility(newStatus: Record<string, number>): void {
    refreshCapsuleWidgets(this.context);
  }

  onFormEvent(formId: string, message: string): void {
    handleWidgetMessage(this.context, formId, message);
  }

  onRemoveForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onRemoveForm %{public}s', formId);
    removeBinding(this.context, formId);
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }
}
