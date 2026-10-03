/**
 * The capsule frame (redesign section 5): a floating card holding one open capsule.
 *   title bar: icon tile | name + origin chip | close
 *   body:      the capsule (pattern from the renderer), scrolling; on wide screens an optional side panel
 *   footer:    "Change it…" pill | Share | the addToHome slot (T4's protected AddToHomeButton, mounted by
 *              the page exactly as T4 provides it; the frame only gives it a place)
 */
import { Effects, Palette, Radius, Space } from '../theme/Tokens';
import { IconButton } from './Buttons';
import { IconTile, OriginChip, OriginKind } from './Surfaces';

@Builder
function nothing() {
}

@ComponentV2
export struct CapsuleFrame {
  @Require @Param name: string;
  @Require @Param icon: Resource;
  /** The app's existing origin wording, e.g. "Made on your phone · no internet". */
  @Param originText: string = '';
  @Param originKind: OriginKind = 'phone';
  /** True on wide windows (theme/Breakpoint): body + side panel, or a centred 560vp body. */
  @Param wide: boolean = false;
  @Param hasSidePanel: boolean = false;
  @Event onClose: () => void = () => {
  };
  @Event onChangeIt: () => void = () => {
  };
  @Event onShare: () => void = () => {
  };
  @BuilderParam body: () => void = nothing;
  @BuilderParam sidePanel: () => void = nothing;
  @BuilderParam addToHome: () => void = nothing;

  @Builder
  titleBar() {
    Row({ space: 12 }) {
      IconTile({ icon: this.icon, tileSize: 42, iconSize: 22 })
      Column({ space: 4 }) {
        Text(this.name)
          .fontSize(17)
          .fontWeight(700)
          .fontColor(Palette.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        OriginChip({ text: this.originText, kind: this.originKind })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      IconButton({ icon: $r('sys.symbol.xmark'), label: 'Close', soft: true, onTap: () => this.onClose() })
    }
    .width('100%')
    .padding({ top: 12, bottom: 12, left: 14, right: 10 })
    .border({ width: { bottom: 1 }, color: Palette.line2 })
  }

  @Builder
  footer() {
    Row({ space: 8 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.square_and_pencil'))
          .fontSize(18)
          .fontColor([Palette.blue])
        Text('Change it…')
          .fontSize(15)
          .fontWeight(500)
          .fontColor(Palette.text2)
      }
      .layoutWeight(1)
      .height(Space.touch)
      .padding({ left: 14, right: 14 })
      .borderRadius(Radius.pill)
      .backgroundColor(Palette.card)
      .border({ width: 1, color: Palette.inputBorder })
      .accessibilityText('Change it')
      .onClick(() => this.onChangeIt())
      IconButton({ icon: $r('sys.symbol.share'), label: 'Share', onTap: () => this.onShare() })
      this.addToHome()
    }
    .width('100%')
    .padding({ top: 10, left: 12, right: 12, bottom: 12 })
    .border({ width: { top: 1 }, color: Palette.line2 })
  }

  build() {
    Column() {
      this.titleBar()
      if (this.wide && this.hasSidePanel) {
        Row({ space: Space.block }) {
          Scroll() {
            Column({ space: Space.block }) {
              this.body()
            }
            .width('100%')
            .padding(Space.body)
          }
          .layoutWeight(1)
          .height('100%')
          .align(Alignment.Top)
          .scrollBar(BarState.Off)
          Column() {
            this.sidePanel()
          }
          .width(280)
          .height('100%')
          .padding({ top: Space.body, right: Space.body })
        }
        .layoutWeight(1)
        .width('100%')
      } else {
        Scroll() {
          Column({ space: Space.block }) {
            this.body()
          }
          .width('100%')
          .constraintSize({ maxWidth: this.wide ? 560 : undefined })
          .padding(Space.body)
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      this.footer()
    }
    .layoutWeight(1)
    .margin({ top: Space.frameTop, left: Space.frameSide, right: Space.frameSide, bottom: Space.frameBottom })
    .borderRadius(Radius.frame)
    .backgroundColor(Palette.frameBg)
    .border({ width: 1, color: Palette.frameBorder })
    .shadow(Effects.frameShadow)
    .clip(true)
  }
}
