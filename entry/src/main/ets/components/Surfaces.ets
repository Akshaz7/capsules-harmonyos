/**
 * Redesign surfaces (section 4): chips, cards, icon tiles, group headers, empty states, error cards.
 */
import { Palette, Radius, Space } from '../theme/Tokens';
import { PrimaryButton } from './Buttons';

/** Which origin chip icon to show: made on the phone, in the cloud, or from the community. */
export type OriginKind = 'phone' | 'cloud' | 'community' | '';

/** Maps the app's stored origin ('rules', 'template', 'on-device', 'cloud-eu:mistral', 'marketplace', ...). */
export function originKindOf(origin: string): OriginKind {
  if (origin.length === 0) {
    return '';
  }
  if (origin === 'cloud' || origin.startsWith('cloud-eu:') || origin.startsWith('cloud:')) {
    return 'cloud';
  }
  if (origin === 'marketplace' || origin === 'community' || origin === 'imported') {
    return 'community';
  }
  return 'phone';
}

export function originIconOf(kind: OriginKind): Resource {
  switch (kind) {
    case 'cloud':
      return $r('sys.symbol.cloud');
    case 'community':
      return $r('sys.symbol.person_2');
    default:
      return $r('sys.symbol.phone');
  }
}

/** A plain chip: chip fill, chipText 12/600. */
@ComponentV2
export struct Chip {
  @Require @Param text: string;
  @Param icon: Resource | undefined = undefined;
  @Param fill: ResourceColor = Palette.chip;
  @Param color: ResourceColor = Palette.chipText;

  build() {
    Row({ space: 4 }) {
      if (this.icon !== undefined) {
        SymbolGlyph(this.icon)
          .fontSize(13)
          .fontColor([this.color])
      }
      Text(this.text)
        .fontSize(12)
        .fontWeight(600)
        .fontColor(this.color)
    }
    .padding({ top: 2, right: 8, bottom: 2, left: this.icon !== undefined ? 6 : 8 })
    .borderRadius(Radius.chip)
    .backgroundColor(this.fill)
  }
}

/** The origin badge with the app's existing wording ("Made on your phone · no internet", ...). */
@ComponentV2
export struct OriginChip {
  /** Existing badge text; nothing renders when empty. */
  @Require @Param text: string;
  @Param kind: OriginKind = 'phone';

  build() {
    if (this.text.length > 0) {
      Chip({ text: this.text, icon: originIconOf(this.kind) })
    }
  }
}

/** A rounded square holding a symbol (tint fill, blue icon). */
@ComponentV2
export struct IconTile {
  @Require @Param icon: Resource;
  @Param tileSize: number = 42;
  @Param iconSize: number = 22;
  @Param fill: ResourceColor = Palette.tint;
  @Param color: ResourceColor = Palette.blue;

  build() {
    Stack() {
      SymbolGlyph(this.icon)
        .fontSize(this.iconSize)
        .fontColor([this.color])
    }
    .width(this.tileSize)
    .height(this.tileSize)
    .borderRadius(this.tileSize >= 42 ? Radius.iconTile : 10)
    .backgroundColor(this.fill)
  }
}

/** Card fill, radius 18 (or 20 with `large`). Content goes in the trailing closure. */
@ComponentV2
export struct Card {
  @Param large: boolean = false;
  @Param fill: ResourceColor = Palette.card;
  @Param pad: number = 14;
  @BuilderParam content: () => void = emptyContent;

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .padding(this.pad)
    .borderRadius(this.large ? Radius.cardLarge : Radius.card)
    .backgroundColor(this.fill)
  }
}

/** Blue fill, radius 22, white content. */
@ComponentV2
export struct HeroCard {
  @BuilderParam content: () => void = emptyContent;

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .padding(18)
    .borderRadius(Radius.heroCard)
    .backgroundColor(Palette.blue)
  }
}

@Builder
function emptyContent() {
}

/** A collapsible group's header: name 16/700, count 13/600, chevron; 48 tall. */
@ComponentV2
export struct GroupHeader {
  @Require @Param name: string;
  @Param count: string = '';
  @Param expanded: boolean = true;
  @Event onTap: () => void = () => {
  };

  build() {
    Row({ space: 8 }) {
      Text(this.name)
        .fontSize(16)
        .fontWeight(700)
        .fontColor(Palette.text)
        .layoutWeight(1)
      if (this.count.length > 0) {
        Text(this.count)
          .fontSize(13)
          .fontWeight(600)
          .fontColor(Palette.text2)
      }
      SymbolGlyph(this.expanded ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
        .fontSize(16)
        .fontColor([Palette.text2])
    }
    .width('100%')
    .height(48)
    .onClick(() => this.onTap())
  }
}

/** Empty list: a 56vp tint circle with an icon, title, caption, and one optional primary action. */
@ComponentV2
export struct EmptyState {
  @Param icon: Resource = $r('sys.symbol.square_grid_2x2');
  @Require @Param title: string;
  @Param caption: string = '';
  @Param action: string = '';
  @Event onAction: () => void = () => {
  };

  build() {
    Column({ space: 8 }) {
      Stack() {
        SymbolGlyph(this.icon)
          .fontSize(26)
          .fontColor([Palette.blue])
      }
      .width(56)
      .height(56)
      .borderRadius(28)
      .backgroundColor(Palette.tint)
      Text(this.title)
        .fontSize(17)
        .fontWeight(700)
        .fontColor(Palette.text)
        .textAlign(TextAlign.Center)
      if (this.caption.length > 0) {
        Text(this.caption)
          .fontSize(13)
          .fontColor(Palette.text2)
          .textAlign(TextAlign.Center)
      }
      if (this.action.length > 0) {
        PrimaryButton({ label: this.action, buttonHeight: 48, fullWidth: false, onTap: () => this.onAction() })
          .margin({ top: 6 })
      }
    }
    .width('100%')
    .padding({ top: 24, bottom: 24 })
  }
}

/** Every error: orangeTintSoft fill, title 15/700 orangeText, body 14, one optional action. */
@ComponentV2
export struct ErrorCard {
  @Require @Param title: string;
  @Param body: string = '';
  @Param action: string = '';
  @Event onAction: () => void = () => {
  };

  build() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize(18)
          .fontColor([Palette.orangeIcon])
        Text(this.title)
          .fontSize(15)
          .fontWeight(700)
          .fontColor(Palette.orangeText)
          .layoutWeight(1)
      }
      .width('100%')
      if (this.body.length > 0) {
        Text(this.body)
          .fontSize(14)
          .fontColor(Palette.text)
          .width('100%')
      }
      if (this.action.length > 0) {
        Text(this.action)
          .fontSize(15)
          .fontWeight(700)
          .fontColor(Palette.orangeText)
          .constraintSize({ minHeight: Space.touch })
          .onClick(() => this.onAction())
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(16)
    .borderRadius(Radius.card)
    .backgroundColor(Palette.orangeTintSoft)
  }
}
