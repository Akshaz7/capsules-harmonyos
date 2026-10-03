/**
 * Redesign controls (section 4): segmented control, stepper, progress bar, rings, checkbox row.
 * Every touch target is at least 44vp.
 */
import { Palette, Radius, Space } from '../theme/Tokens';

/**
 * Track softButton, items 44 tall. Selected item: surface with a soft shadow, or blue/white with `strong`
 * (value pickers such as a tip percentage).
 */
@ComponentV2
export struct SegmentedControl {
  @Require @Param items: string[];
  @Param selected: number = 0;
  @Param strong: boolean = false;
  @Event onSelect: (index: number) => void = () => {
  };

  build() {
    Row({ space: 3 }) {
      ForEach(this.items, (item: string, i: number) => {
        Text(item)
          .fontSize(15)
          .fontWeight(600)
          .fontColor(i === this.selected ? (this.strong ? Palette.surface : Palette.text) : Palette.text2)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height(Space.touch)
          .borderRadius(11)
          .backgroundColor(i === this.selected ? (this.strong ? Palette.blue : Palette.surface) : Color.Transparent)
          .shadow(i === this.selected && !this.strong ? { radius: 6, offsetY: 2, color: Palette.shadow } :
            { radius: 0, color: Color.Transparent })
          .accessibilityText(item)
          .onClick(() => this.onSelect(i))
      }, (item: string, i: number) => `${i}-${item}`)
    }
    .width('100%')
    .padding(3)
    .borderRadius(Radius.chipLarge)
    .backgroundColor(Palette.softButton)
  }
}

/** Minus and plus 44vp circles with the value (20/800) between. */
@ComponentV2
export struct ValueStepper {
  @Require @Param value: string;
  @Param canDecrease: boolean = true;
  @Event onMinus: () => void = () => {
  };
  @Event onPlus: () => void = () => {
  };

  @Builder
  step(icon: Resource, label: string, enabledState: boolean, action: () => void) {
    Stack() {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([enabledState ? Palette.text : Palette.disabled])
    }
    .width(Space.touch)
    .height(Space.touch)
    .borderRadius(Space.touch / 2)
    .backgroundColor(Palette.softButton)
    .enabled(enabledState)
    .accessibilityText(label)
    .onClick(action)
  }

  build() {
    Row({ space: 10 }) {
      this.step($r('sys.symbol.minus'), 'Decrease', this.canDecrease, () => this.onMinus())
      Text(this.value)
        .fontSize(20)
        .fontWeight(800)
        .fontColor(Palette.text)
        .constraintSize({ minWidth: 32 })
        .textAlign(TextAlign.Center)
      this.step($r('sys.symbol.plus'), 'Increase', true, () => this.onPlus())
    }
  }
}

/** 8vp tall, track colour, blue fill. `value` and `total` as in Progress. */
@ComponentV2
export struct ProgressBar {
  @Param value: number = 0;
  @Param total: number = 1;
  @Param barHeight: number = 8;
  @Param barWidth: Length = '100%';

  build() {
    Progress({ value: this.value, total: this.total > 0 ? this.total : 1, type: ProgressType.Linear })
      .width(this.barWidth)
      .height(this.barHeight)
      .color(Palette.blue)
      .backgroundColor(Palette.track)
      .style({ strokeWidth: this.barHeight, strokeRadius: this.barHeight / 2 })
  }
}

/** A ring: stroke 14, track colour, blue (orange with `warm`, e.g. break/rest). Content sits in the middle. */
@ComponentV2
export struct RingProgress {
  @Param value: number = 0;
  @Param total: number = 1;
  @Param ringSize: number = 252;
  @Param stroke: number = 14;
  @Param warm: boolean = false;
  @BuilderParam content: () => void = emptyRingContent;

  build() {
    Stack() {
      Progress({ value: this.value, total: this.total > 0 ? this.total : 1, type: ProgressType.Ring })
        .width(this.ringSize)
        .height(this.ringSize)
        .color(this.warm ? Palette.orange : Palette.blue)
        .backgroundColor(Palette.track)
        .style({ strokeWidth: this.stroke, shadow: false })
      this.content()
    }
    .width(this.ringSize)
    .height(this.ringSize)
  }
}

/** N segments with gaps (one per unit), `filled` of them blue. Stroke 20. */
@ComponentV2
export struct SegmentRing {
  @Param segments: number = 8;
  @Param filled: number = 0;
  @Param ringSize: number = 240;
  @Param stroke: number = 20;
  @BuilderParam content: () => void = emptyRingContent;

  private dash(): number[] {
    const n = Math.max(1, Math.min(this.segments, 60));
    const r = (this.ringSize - this.stroke) / 2;
    const circumference = 2 * Math.PI * r;
    const gap = n > 1 ? Math.min(8, circumference / n / 3) : 0;
    return [circumference / n - gap, gap];
  }

  build() {
    Stack() {
      // Track, then the filled arc drawn with the same dashes so segment edges line up.
      Circle({ width: this.ringSize - this.stroke, height: this.ringSize - this.stroke })
        .fill(Color.Transparent)
        .stroke(Palette.track)
        .strokeWidth(this.stroke)
        .strokeDashArray(this.dash())
        .rotate({ angle: -90 })
      Circle({ width: this.ringSize - this.stroke, height: this.ringSize - this.stroke })
        .fill(Color.Transparent)
        .stroke(Palette.blue)
        .strokeWidth(this.stroke)
        .strokeDashArray(this.filledDash())
        .rotate({ angle: -90 })
      this.content()
    }
    .width(this.ringSize)
    .height(this.ringSize)
  }

  /** The dash pattern repeated `filled` times, then one long gap covering the rest. */
  private filledDash(): number[] {
    const n = Math.max(1, Math.min(this.segments, 60));
    const k = Math.max(0, Math.min(this.filled, n));
    const d = this.dash();
    const r = (this.ringSize - this.stroke) / 2;
    const circumference = 2 * Math.PI * r;
    if (k === 0) {
      return [0, circumference];
    }
    const out: number[] = [];
    for (let i = 0; i < k; i++) {
      out.push(d[0]);
      out.push(i === k - 1 ? circumference : d[1]);
    }
    return out;
  }
}

@Builder
function emptyRingContent() {
}

/** A 44vp-tall row: a 26vp checkbox (blue + white check when on) and its label. */
@ComponentV2
export struct CheckboxRow {
  @Param checked: boolean = false;
  @Param label: string = '';
  @Param doneDims: boolean = true;
  @Event onToggle: () => void = () => {
  };

  build() {
    Row({ space: 12 }) {
      Stack() {
        if (this.checked) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(16)
            .fontColor([Palette.surface])
        }
      }
      .width(26)
      .height(26)
      .borderRadius(Radius.checkbox)
      .backgroundColor(this.checked ? Palette.blue : Palette.surface)
      .border(this.checked ? { width: 0 } : { width: 2, color: Palette.checkboxOff })
      if (this.label.length > 0) {
        Text(this.label)
          .fontSize(15)
          .fontWeight(500)
          .fontColor(this.checked && this.doneDims ? Palette.text2 : Palette.text)
          .layoutWeight(1)
      }
    }
    .constraintSize({ minHeight: Space.touch })
    .accessibilityText(this.label.length > 0 ? this.label : 'Checkbox')
    .accessibilityChecked(this.checked)
    .onClick(() => this.onToggle())
  }
}
