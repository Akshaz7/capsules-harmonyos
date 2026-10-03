/**
 * Redesign buttons (section 4). Labels never truncate: they wrap instead. Every button is at least 44vp tall.
 */
import { Palette, Radius, Space } from '../theme/Tokens';

/** Blue fill, white 17/700. */
@ComponentV2
export struct PrimaryButton {
  @Require @Param label: string;
  @Param icon: Resource | undefined = undefined;
  @Param buttonHeight: number = 54;
  @Param enabledState: boolean = true;
  @Param fullWidth: boolean = true;
  @Event onTap: () => void = () => {
  };

  build() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row({ space: 8 }) {
        if (this.icon !== undefined) {
          SymbolGlyph(this.icon)
            .fontSize(20)
            .fontColor([Palette.surface])
        }
        Text(this.label)
          .fontSize(17)
          .fontWeight(700)
          .fontColor(Palette.surface)
          .textAlign(TextAlign.Center)
      }
      .padding({ left: 18, right: 18 })
      .justifyContent(FlexAlign.Center)
    }
    .width(this.fullWidth ? '100%' : undefined)
    .constraintSize({ minHeight: Math.max(this.buttonHeight, Space.touch) })
    .borderRadius(this.buttonHeight >= 54 ? Radius.buttonLarge : Radius.button)
    .backgroundColor(this.enabledState ? Palette.blue : Palette.disabled)
    .enabled(this.enabledState)
    .onClick(() => this.onTap())
  }
}

/** Surface fill, 1vp inputBorder, text colour. */
@ComponentV2
export struct SecondaryButton {
  @Require @Param label: string;
  @Param icon: Resource | undefined = undefined;
  @Param buttonHeight: number = 46;
  @Param fullWidth: boolean = true;
  @Event onTap: () => void = () => {
  };

  build() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row({ space: 8 }) {
        if (this.icon !== undefined) {
          SymbolGlyph(this.icon)
            .fontSize(18)
            .fontColor([Palette.text])
        }
        Text(this.label)
          .fontSize(15)
          .fontWeight(600)
          .fontColor(Palette.text)
          .textAlign(TextAlign.Center)
      }
      .padding({ left: 16, right: 16 })
      .justifyContent(FlexAlign.Center)
    }
    .width(this.fullWidth ? '100%' : undefined)
    .constraintSize({ minHeight: Math.max(this.buttonHeight, Space.touch) })
    .borderRadius(Radius.button)
    .backgroundColor(Palette.surface)
    .border({ width: 1, color: Palette.inputBorder })
    .onClick(() => this.onTap())
  }
}

/** No fill, chipText label: a quiet action. */
@ComponentV2
export struct GhostButton {
  @Require @Param label: string;
  @Param icon: Resource | undefined = undefined;
  @Event onTap: () => void = () => {
  };

  build() {
    Row({ space: 6 }) {
      if (this.icon !== undefined) {
        SymbolGlyph(this.icon)
          .fontSize(16)
          .fontColor([Palette.chipText])
      }
      Text(this.label)
        .fontSize(15)
        .fontWeight(600)
        .fontColor(Palette.chipText)
    }
    .constraintSize({ minHeight: Space.touch })
    .padding({ left: 12, right: 12 })
    .justifyContent(FlexAlign.Center)
    .onClick(() => this.onTap())
  }
}

/** orangeTint fill, orangeText label (e.g. a timer's secondary action). */
@ComponentV2
export struct SoftButton {
  @Require @Param label: string;
  @Param icon: Resource | undefined = undefined;
  @Param buttonHeight: number = 54;
  @Param fullWidth: boolean = true;
  @Event onTap: () => void = () => {
  };

  build() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row({ space: 8 }) {
        if (this.icon !== undefined) {
          SymbolGlyph(this.icon)
            .fontSize(18)
            .fontColor([Palette.orangeText])
        }
        Text(this.label)
          .fontSize(17)
          .fontWeight(700)
          .fontColor(Palette.orangeText)
          .textAlign(TextAlign.Center)
      }
      .padding({ left: 16, right: 16 })
      .justifyContent(FlexAlign.Center)
    }
    .width(this.fullWidth ? '100%' : undefined)
    .constraintSize({ minHeight: Math.max(this.buttonHeight, Space.touch) })
    .borderRadius(Radius.buttonLarge)
    .backgroundColor(Palette.orangeTint)
    .onClick(() => this.onTap())
  }
}

/** A 44vp circle with one symbol; `soft` uses the softButton fill instead of surface + border. */
@ComponentV2
export struct IconButton {
  @Require @Param icon: Resource;
  /** Required: icon-only buttons need a spoken label. */
  @Require @Param label: string;
  @Param soft: boolean = false;
  @Param diameter: number = 44;
  @Param iconColor: ResourceColor = Palette.text;
  @Param fill: ResourceColor | undefined = undefined;
  @Event onTap: () => void = () => {
  };

  build() {
    Stack() {
      SymbolGlyph(this.icon)
        .fontSize(20)
        .fontColor([this.iconColor])
    }
    .width(this.diameter)
    .height(this.diameter)
    .borderRadius(this.diameter / 2)
    .backgroundColor(this.fill !== undefined ? this.fill : (this.soft ? Palette.softButton : Palette.surface))
    .border(this.soft || this.fill !== undefined ? { width: 0 } : { width: 1, color: Palette.inputBorder })
    .responseRegion({ x: -(Math.max(0, Space.touch - this.diameter) / 2), y: -(Math.max(0, Space.touch - this.diameter) / 2),
      width: Math.max(this.diameter, Space.touch), height: Math.max(this.diameter, Space.touch) })
    .accessibilityText(this.label)
    .onClick(() => this.onTap())
  }
}
