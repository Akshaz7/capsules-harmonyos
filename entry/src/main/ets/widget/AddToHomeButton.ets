/**
 * "Add to home screen" for ONE capsule. Owned by T4 (see /tmp/hy-tasks): the capsule screen only mounts it,
 * passing the id of the capsule open on screen. It never reads a "latest" or "current" capsule.
 *
 *   AddToHomeButton({ capsuleId: entry.capsule.id, capsuleName: entry.capsule.name })
 *
 * Tap: a blank widget shows this capsule at once; otherwise this capsule becomes the pending one and the
 * system's add-widget page opens, so the widget the user adds shows it (WidgetService.addCapsuleToHomeScreen).
 * scripts/check-add-to-home.sh fails if the capsule screen stops mounting it.
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { addCapsuleToHomeScreen, AddToHomeResult, clearPendingFor, listWidgets, WidgetInfo } from './WidgetService';

@ComponentV2
export struct AddToHomeButton {
  /** The capsule open on screen. Required: the button adds exactly this capsule. */
  @Require @Param capsuleId: string;
  @Param capsuleName: string = '';
  @Local onHome: boolean = false;
  @Local showSteps: boolean = false;
  @Local busy: boolean = false;

  aboutToAppear(): void {
    this.refresh(false);
  }

  private context(): common.UIAbilityContext | undefined {
    try {
      return this.getUIContext().getHostContext() as common.UIAbilityContext;
    } catch (e) {
      return undefined;
    }
  }

  /**
   * `back`: the user returned to this screen (e.g. from the add-widget page). Only then is a widget showing
   * this capsule proof it was added, so the pending capsule is cleared; right after the tap the system's
   * preview widgets already show it and clearing then would leave the real widget blank.
   */
  private refresh(back: boolean): void {
    const ctx = this.context();
    if (ctx !== undefined) {
      this.onHome = listWidgets(ctx).some((w: WidgetInfo) => w.capsuleId === this.capsuleId);
      if (this.onHome && back) {
        clearPendingFor(ctx, this.capsuleId); // the widget was added: later widgets start blank again
      }
    }
  }

  private toast(text: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: text });
    } catch (e) {
      hilog.warn(0x0002, 'AddToHome', 'toast failed: %{public}s', text);
    }
  }

  private async add(): Promise<void> {
    const ctx = this.context();
    if (ctx === undefined || this.busy) {
      return;
    }
    this.busy = true;
    const name = this.capsuleName.length > 0 ? this.capsuleName : 'This capsule';
    let result: AddToHomeResult = 'manual';
    try {
      result = await addCapsuleToHomeScreen(ctx, this.capsuleId);
    } catch (e) {
      hilog.error(0x0002, 'AddToHome', 'add failed for %{public}s', this.capsuleId);
    }
    this.busy = false;
    hilog.info(0x0002, 'AddToHome', '%{public}s -> %{public}s', this.capsuleId, result);
    if (result === 'already') {
      this.toast(`${name} is already on your home screen`);
    } else if (result === 'filled') {
      this.toast(`${name} is now on your home screen`);
    } else if (result === 'opened') {
      this.toast(`Add the widget: it will show ${name}`);
    } else {
      this.showSteps = true; // the add-widget page could not open; the next widget added still shows this capsule
    }
    this.refresh(false);
  }

  build() {
    Column({ space: 8 }) {
      Button() {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.square_grid_2x2'))
            .fontSize(18)
            .fontColor([$r('sys.color.brand')])
          Text(this.onHome ? 'On your home screen · Add another' : 'Add to home screen')
            .fontSize($r('sys.float.Body_L'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.brand'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      }
      .width('100%')
      .constraintSize({ minHeight: 48 }) // grows with the system font size
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      .enabled(!this.busy)
      .onClick(() => {
        this.add();
      })

      if (this.showSteps) {
        Text('Long-press the Harmoniser app icon, pick the Harmoniser widget and tap "Add to home screen". ' +
          'The new widget will show this capsule.')
          .fontSize($r('sys.float.Body_M'))
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
      }
    }
    .width('100%')
    .onVisibleAreaChange([0.0, 1.0], (visible: boolean) => {
      if (visible) {
        this.refresh(true); // e.g. back from the add-widget page
      }
    })
  }
}
