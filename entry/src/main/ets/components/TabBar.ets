import { Flags } from '../theme/Flags';
import { Effects, Palette } from '../theme/Tokens';

export interface TabItem {
  icon: Resource;
  label: string;
}

/**
 * Floating tab bar: 12vp from the bottom, 16vp sides, 64 tall, radius 32, white 90% + blur, soft shadow.
 * Selected: blue icon and label over a #EAF0FF 56x32 pill; unselected: text2. The page hides it while a
 * capsule is open.
 */
@ComponentV2
export struct TabBar {
  @Require @Param items: TabItem[];
  @Param selected: number = 0;
  /** Bumped per tab on tap: drives the symbol bounce. */
  @Param taps: number[] = [];
  @Event onSelect: (index: number) => void = () => {
  };

  build() {
    Row() {
      ForEach(this.items, (item: TabItem, i: number) => {
        Column({ space: 2 }) {
          Stack() {
            SymbolGlyph(item.icon)
              .fontSize(24)
              .fontColor([i === this.selected ? Palette.blue : Palette.text2])
              .symbolEffect(new BounceSymbolEffect(EffectScope.WHOLE, EffectDirection.DOWN),
                i < this.taps.length ? this.taps[i] : 0)
          }
          .width(56)
          .height(32)
          .borderRadius(16)
          .backgroundColor(i === this.selected ? Palette.tint : Color.Transparent)
          // Polish: the pill fades in and out as the selection moves (160 ms).
          .animation(Flags.NEW_POLISH ? { duration: 160, curve: Curve.EaseOut } : undefined)
          Text(item.label)
            .fontSize(12)
            .fontWeight(Flags.NEW_POLISH && i === this.selected ? 700 : 600)
            .fontColor(i === this.selected ? Palette.blue : Palette.text2)
            .maxLines(1)
        }
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .accessibilityText(item.label)
        .accessibilitySelected(i === this.selected)
        .onClick(() => this.onSelect(i))
      }, (item: TabItem) => item.label)
    }
    .height(64)
    .width('100%')
    .padding({ left: 6, right: 6 })
    .borderRadius(32)
    .backgroundColor(Palette.white90)
    .backgroundBlurStyle(Effects.frosted)
    .shadow(Effects.softShadow)
  }
}
