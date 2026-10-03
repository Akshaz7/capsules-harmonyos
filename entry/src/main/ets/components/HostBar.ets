import { Palette } from '../theme/Tokens';

/** Top of the Create tab: logo + wordmark left, a 44vp "Scan QR" circle (white 72%) right. */
@ComponentV2
export struct HostBar {
  @Param showScan: boolean = true;
  @Event onScan: () => void = () => {
  };

  build() {
    Row({ space: 10 }) {
      Image($r('app.media.logo'))
        .width(30)
        .height(30)
        .accessibilityText('Harmoniser')
      Text('Harmoniser')
        .fontSize(19)
        .fontWeight(700)
        .fontColor(Palette.text)
        .layoutWeight(1)
      if (this.showScan) {
        Stack() {
          SymbolGlyph($r('sys.symbol.viewfinder_square'))
            .fontSize(20)
            .fontColor([Palette.text])
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .backgroundColor(Palette.white72)
        .accessibilityText('Scan QR code')
        .onClick(() => this.onScan())
      }
    }
    .width('100%')
    .padding({ top: 18, left: 20, right: 16, bottom: 10 })
  }
}
