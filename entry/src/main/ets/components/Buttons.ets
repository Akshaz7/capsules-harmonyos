/**
 * Redesign buttons (section 4). Labels never truncate: they wrap instead. Every button is at least 44vp tall.
 */
import { Effects, Palette, Radius, Space } from '../theme/Tokens';

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

/**
 * Polish: a compact pill (32 tall, gradient fill, 13/700) for small actions such as Install. With `done` it
 * shows a flat tint pill with a check, disabled. The tap area stays 44vp tall.
 */
@ComponentV2
export struct CompactPillButton {
  @Require @Param label: string;
  @Param icon: Resource | undefined = undefined;
  @Param done: boolean = false;
  @Param enabledState: boolean = true;
  @Event onTap: () => void = () => {
  };
  @Local pressed: boolean = false;

  build() {
    Row({ space: 4 }) {
      if (this.done) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(14)
          .fontColor([Palette.blue])
      } else if (this.icon !== undefined) {
        SymbolGlyph(this.icon)
          .fontSize(14)
          .fontColor([Palette.surface])
      }
      Text(this.label)
        .fontSize(13)
        .fontWeight(700)
        .fontColor(this.done ? Palette.blue : Palette.surface)
    }
    .height(32)
    .padding({ left: 14, right: 14 })
    .borderRadius(Radius.pill)
    .backgroundColor(this.done ? Palette.tint : (this.enabledState ? Palette.blue : Palette.disabled))
    .linearGradient(this.done || !this.enabledState ? { angle: 135, colors: [[Color.Transparent, 0], [Color.Transparent, 1]] } :
      { angle: 135, colors: [[Palette.blue, 0], [Palette.blueDeep, 1]] })
    .scale({ x: this.pressed ? Effects.pressedScale : 1, y: this.pressed ? Effects.pressedScale : 1 })
    .animation({ duration: Effects.pressMs, curve: Curve.EaseOut })
    .responseRegion({ x: 0, y: -6, width: '100%', height: 44 }) // 44vp tap area
    .enabled(this.enabledState && !this.done)
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.pressed = true;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    .onClick(() => this.onTap())
    .accessibilityText(this.label)
  }
}
