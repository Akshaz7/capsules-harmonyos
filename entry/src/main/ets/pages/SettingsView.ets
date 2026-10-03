import { AppSettings } from './AppSettings';

/** Settings page (NavDestination). */
@ComponentV2
export struct SettingsView {
  @Require @Param settings: AppSettings;
  @Param cloudStatus: string = '';

  build() {
    NavDestination() {
      Column({ space: 8 }) {
        Row({ space: 12 }) {
          Stack() {
            SymbolGlyph($r('sys.symbol.cloud'))
              .fontSize(20)
              .fontColor([$r('sys.color.icon_emphasize')])
          }
          .width(40)
          .height(40)
          .borderRadius(20)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          Column({ space: 2 }) {
            Text('Allow cloud AI fallback')
              .fontSize($r('sys.float.Body_L'))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
            Text('When neither the rules nor the on-device model can handle a request, send it to a cloud AI model')
              .fontSize($r('sys.float.Caption_M'))
              .fontColor($r('sys.color.font_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.settings.allowCloud })
            .selectedColor($r('sys.color.brand'))
            .onChange((isOn: boolean) => {
              this.settings.setAllowCloud(isOn);
            })
        }
        .width('100%')
        .padding(16)
        .borderRadius(20)
        .backgroundColor($r('sys.color.comp_background_primary'))

        Text(this.settings.allowCloud ?
          `On: only your request text is sent, and only when nothing on the device can handle it. ${this.cloudStatus}` :
          'Off: requests never leave the device.')
          .fontSize($r('sys.float.Caption_M'))
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
          .padding({ left: 4, right: 4 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8 })
    }
    .title('Settings')
    .backgroundColor($r('sys.color.background_secondary'))
  }
}
