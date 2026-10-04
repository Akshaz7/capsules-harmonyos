import { Effects, Palette, Radius } from '../theme/Tokens';
import { Flags } from '../theme/Flags';
import { reduceMotion } from '../pages/Motion';
import { Chip, IconTile, OriginChip, OriginKind, originIconOf } from './Surfaces';

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
  /** Polish: one-line origin label for the chip (originShort); originText stays as its spoken label. */
  @Param shortOrigin: string = '';
  /** True when the capsule fits a home-screen widget ("Add to home screen"); else no hint (T4-19). */
  @Param widget: boolean = false;
  /** Polish: one featured tile (e.g. the last-opened capsule) gets a gradient icon tile. */
  @Param featured: boolean = false;
  @Event onOpen: () => void = () => {
  };
  @Local pressed: boolean = false;
  private still: boolean = reduceMotion();

  build() {
    if (Flags.NEW_POLISH) {
      this.polished()
    } else {
      this.classic()
    }
  }

  /**
   * Polish (4.3): sized to its content. Icon, then the name (2 lines), the live value on its own line
   * (tabular, wraps, not truncated), then a one-line origin chip and a small widget badge. No fixed or
   * minimum height: the Grid makes each row as tall as its taller tile. Pressed 0.97.
   */
  @Builder
  polished() {
    Column({ space: 6 }) {
      IconTile({ icon: this.icon, tileSize: 36, iconSize: 20, featured: this.featured })
      Text(this.name)
        .fontSize(15)
        .fontWeight(700)
        .fontColor(Palette.text)
        .maxLines(2)
        .lineHeight(19)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.value.length > 0) {
        Text(this.value)
          .fontSize(13)
          .fontWeight(600)
          .lineHeight(17)
          .fontColor(Palette.blue)
          .fontFeature('"tnum" on')
          .width('100%')
      }
      Blank()
      Row({ space: 6 }) {
        if (this.shortOrigin.length > 0) {
          Chip({ text: this.shortOrigin, icon: originIconOf(this.originKind) })
            .accessibilityText(this.originText)
        }
        if (this.widget) {
          // Icon only, so the chip and the badge always fit on one line.
          Stack() {
            SymbolGlyph($r('sys.symbol.square_grid_2x2'))
              .fontSize(12)
              .fontColor([Palette.chipText])
          }
          .width(24)
          .height(24)
          .borderRadius(Radius.pill)
          .border({ width: 1, color: Palette.hairline })
          .accessibilityText('Can be added to the home screen')
        }
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(12)
    .borderRadius(Radius.tileCard)
    .backgroundColor(Palette.surface)
    .linearGradient({ angle: 180, colors: [[Palette.cardTintTop, 0], [Palette.cardTintBottom, 1]] })
    .border({ width: 1, color: Palette.hairline })
    .shadow(Effects.cardShadow)
    .scale({ x: this.pressed && !this.still ? Effects.pressedScale : 1,
      y: this.pressed && !this.still ? Effects.pressedScale : 1 })
    .animation({ duration: this.still ? 0 : Effects.pressMs, curve: Curve.EaseOut })
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.pressed = true;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    .accessibilityText(this.name)
    .onClick(() => this.onOpen())
  }

  @Builder
  classic() {
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
      if (this.widget) {
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.square_grid_2x2'))
            .fontSize(13)
            .fontColor([Palette.chipText])
          Text('Add to home screen')
            .fontSize(13)
            .fontWeight(500)
            .fontColor(Palette.chipText)
        }
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
