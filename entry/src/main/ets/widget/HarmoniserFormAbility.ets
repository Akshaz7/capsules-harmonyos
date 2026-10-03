import { Want } from '@kit.AbilityKit';
import { formBindingData, FormExtensionAbility, formInfo } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { removeBinding } from './WidgetStore';
import { bindingData, bindNewForm, handleWidgetMessage, refreshCapsuleWidgets, viewFor } from './WidgetService';

const DOMAIN = 0x0002;
const TAG = 'HarmoniserForm';

/** Provider for the Harmoniser widget: one capsule per widget, 2x2 or 2x4. */
export default class HarmoniserFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const params = want.parameters ?? {};
    const formId = String(params[formInfo.FormParam.IDENTITY_KEY] ?? '');
    const wide = params[formInfo.FormParam.DIMENSION_KEY] === formInfo.FormDimension.Dimension_2_4;
    const binding = bindNewForm(this.context, formId, wide);
    hilog.info(DOMAIN, TAG, 'onAddForm %{public}s wide=%{public}s', formId, String(wide));
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
    removeBinding(this.context, formId);
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }
}
