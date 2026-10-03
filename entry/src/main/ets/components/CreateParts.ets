/**
 * Create tab parts: the "Recent" row of mini tiles and the suggestion chips shown while the prompt is empty.
 */
import { Palette, Space } from '../theme/Tokens';
import { IconTile, OriginChip, OriginKind } from './Surfaces';

/** One recent capsule as the Create tab shows it. */
export interface RecentTile {
  id: string;
  name: string;
  icon: Resource;
  originText: string;
  originKind: OriginKind;
}

/** "Recent" 15/700 and a horizontal row of 148x120 tiles; tap opens the capsule. Nothing when empty. */
@ComponentV2
export struct RecentRow {
  @Param tiles: RecentTile[] = [];
  @Event onOpen: (id: string) => void = () => {
  };

  build() {
    if (this.tiles.length > 0) {
      Column({ space: 10 }) {
        Text('Recent')
          .fontSize(15)
          .fontWeight(700)
          .fontColor(Palette.text)
          .padding({ left: 4 })
        Scroll() {
          Row({ space: 10 }) {
            ForEach(this.tiles, (t: RecentTile) => {
              Column({ space: 6 }) {
                IconTile({ icon: t.icon, tileSize: 32, iconSize: 18 })
                Text(t.name)
                  .fontSize(15)
                  .fontWeight(700)
                  .fontColor(Palette.text)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Blank()
                OriginChip({ text: t.originText, kind: t.originKind })
              }
              .alignItems(HorizontalAlign.Start)
              .width(148)
              .constraintSize({ minHeight: 120 })
              .padding(12)
              .borderRadius(20)
              .backgroundColor(Palette.surface)
              .border({ width: 1, color: Palette.line2 })
              .accessibilityText(t.name)
              .onClick(() => this.onOpen(t.id))
            }, (t: RecentTile) => t.id)
          }
          .alignItems(VerticalAlign.Top)
          .padding({ left: 4, right: 4 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .align(Alignment.Start)
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
  }
}

/** Suggestion chips: 44 tall, radius 22, white, 1vp inputBorder, 15/600. Tapping fills the prompt. */
@ComponentV2
export struct SuggestionChips {
  @Param suggestions: string[] = [];
  @Event onPick: (text: string) => void = () => {
  };

  build() {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(this.suggestions, (s: string) => {
        Text(s)
          .fontSize(15)
          .fontWeight(600)
          .fontColor(Palette.text)
          .height(Space.touch)
          .padding({ left: 16, right: 16 })
          .margin({ right: 8, bottom: 8 })
          .borderRadius(22)
          .backgroundColor(Palette.surface)
          .border({ width: 1, color: Palette.inputBorder })
          .onClick(() => this.onPick(s))
      }, (s: string) => s)
    }
    .width('100%')
  }
}
