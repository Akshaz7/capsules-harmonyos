import { Palette } from '../theme/Tokens';
import { IconTile, OriginChip, OriginKind } from './Surfaces';

/**
 * Capsules tab tile (NEW_CAPSULES): icon tile, name (2 lines), the capsule's live one-line summary, origin
 * chip, and the existing widget hint. White, radius 22, padding 14, and one fixed height (T3-27) so every
 * tile matches: line 2 of the name is always reserved, and the chip and hint sit at the bottom.
 */
export const CAPSULE_TILE_HEIGHT: number = 208; // fits a 2-line name, the value, a 2-line chip and the hint
@ComponentV2
export struct CapsuleTile {
  @Require @Param name: string;
  @Require @Param icon: Resource;
  /** The runtime's live summary, e.g. "3:00 left" or "2/5 ticked". */
  @Param value: string = '';
  @Param originText: string = '';
  @Param originKind: OriginKind = 'phone';
  /** True when the capsule fits a home-screen widget ("Add to home screen"), else "In app". */
  @Param widget: boolean = false;
  @Event onOpen: () => void = () => {
  };

  build() {
    Column({ space: 6 }) {
      IconTile({ icon: this.icon, tileSize: 36, iconSize: 20 })
      Text(this.name)
        .fontSize(15)
        .fontWeight(700)
        .fontColor(Palette.text)
        .maxLines(2)
        .lineHeight(20)
        .constraintSize({ minHeight: 40 }) // line 2 reserved even for a one-line name
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.value.length > 0) {
        Text(this.value)
          .fontSize(14)
          .fontWeight(600)
          .fontColor(Palette.text2)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      Blank()
      OriginChip({ text: this.originText, kind: this.originKind })
      Row({ space: 4 }) {
        if (this.widget) {
          SymbolGlyph($r('sys.symbol.square_grid_2x2'))
            .fontSize(13)
            .fontColor([Palette.chipText])
        }
        Text(this.widget ? 'Add to home screen' : 'In app')
          .fontSize(13)
          .fontWeight(500)
          .fontColor(this.widget ? Palette.chipText : Palette.text2)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height(CAPSULE_TILE_HEIGHT)
    .clip(true)
    .padding(14)
    .borderRadius(22)
    .backgroundColor(Palette.surface)
    .accessibilityText(this.name)
    .onClick(() => this.onOpen())
  }
}
