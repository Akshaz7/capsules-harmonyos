import { AiMode, AppSettings } from './AppSettings';
import { LIMITS_TEXT } from './CreateText';

/** Settings page (NavDestination). */
@ComponentV2
export struct SettingsView {
  /** Shown as a home tab (UI-2) instead of a pushed page. */
  @Param embedded: boolean = false;
  @Require @Param settings: AppSettings;
  @Param cloudStatus: string = '';
  /** Second line of the Smart option: which cloud provider Smart mode would use. */
  @Param smartDetail: string = 'On-device + Mistral EU when needed';

  @Builder
  modeRow(mode: AiMode, icon: Resource, title: string, detail: string) {
    Row({ space: 12 }) {
      Stack() {
        SymbolGlyph(icon)
          .fontSize(20)
          .fontColor([$r('sys.color.icon_emphasize')])
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      Column({ space: 2 }) {
        Text(title)
          .fontSize($r('sys.float.Body_L'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
        Text(detail)
          .fontSize($r('sys.float.Caption_M'))
          .fontColor($r('sys.color.font_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Radio({ value: mode, group: 'aiMode' })
        .checked(this.settings.aiMode === mode)
        .onChange((isChecked: boolean) => {
          if (isChecked) {
            this.settings.setAiMode(mode);
          }
        })
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .onClick(() => this.settings.setAiMode(mode))
  }

  @Builder
  content() {
    Column({ space: 8 }) {
      Text('AI mode')
        .fontSize($r('sys.float.Subtitle_S'))
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
        .padding({ left: 4, right: 4, top: 4 })
      Column() {
        this.modeRow('smart', $r('sys.symbol.wand_and_stars'), 'Smart', this.smartDetail)
        Divider()
          .color($r('sys.color.comp_divider'))
          .margin({ left: 52 })
        this.modeRow('on-device', $r('sys.symbol.lock'), 'On-device only',
          'Requests never leave the device')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 4 })
      .borderRadius(20)
      .backgroundColor($r('sys.color.comp_background_primary'))

      Text(this.settings.aiMode === 'smart' ?
        `Only your request text is sent, and only when the device can't build it. ${this.cloudStatus}` :
        'Capsules are made by rules and the on-device model only.')
        .fontSize($r('sys.float.Caption_M'))
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
        .padding({ left: 4, right: 4 })
      Text(LIMITS_TEXT)
        .fontSize($r('sys.float.Caption_M'))
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
        .padding({ left: 4, right: 4 })

      Text('Advanced')
        .fontSize($r('sys.float.Subtitle_S'))
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
        .padding({ left: 4, right: 4, top: 16 })
      Row({ space: 12 }) {
        Column({ space: 2 }) {
          Text('Allow non-EU providers')
            .fontSize($r('sys.float.Body_L'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
          Text('Let Smart mode use cloud AI providers outside the EU')
            .fontSize($r('sys.float.Caption_M'))
            .fontColor($r('sys.color.font_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.settings.allowNonEu })
          .selectedColor($r('sys.color.brand'))
          .enabled(this.settings.aiMode === 'smart')
          .onChange((isOn: boolean) => {
            this.settings.setAllowNonEu(isOn);
          })
      }
      .width('100%')
      .padding(16)
      .borderRadius(20)
      .backgroundColor($r('sys.color.comp_background_primary'))
      .opacity(this.settings.aiMode === 'smart' ? 1 : 0.5)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8 })
  }

  build() {
    if (this.embedded) {
      // A tab of the home screen (UI-2): no title bar, a large title, room for the floating tab bar.
      Column({ space: 8 }) {
        Text('Settings')
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
          .padding({ left: 16, right: 16, top: 12 })
        Column() {
          this.content()
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('100%')
    } else {
      NavDestination() {
        this.content()
      }
      .title('Settings')
      .backgroundColor($r('sys.color.background_secondary'))
    }
  }
}
