import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { initCapsuleModel, initTemplates } from '../core';
import { takeWidgetWant } from '../pages/WidgetLaunch';
import { takeShareWant } from '../pages/ShareLaunch';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    takeWidgetWant(want); // a blank widget asking the user to choose a capsule
    takeShareWant(want, launchParam); // text, a link or an image from the system share sheet
    // Loads the optional AI fallback config; stays rules-only if missing. Never throws.
    initCapsuleModel(this.context).then((ready: boolean) => {
      hilog.info(DOMAIN, 'testTag', 'initCapsuleModel ready=%{public}s', String(ready));
    });
    // Built-in templates (rawfile) and the request cache; core templates work until this loads. Never throws.
    initTemplates(this.context).then((count: number) => {
      hilog.info(DOMAIN, 'testTag', 'initTemplates templates=%{public}d', count);
    });
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    takeWidgetWant(want);
    takeShareWant(want, launchParam);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}