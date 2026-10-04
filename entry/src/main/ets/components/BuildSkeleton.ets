/**
 * T3-28: what Create shows while a capsule is being built. A live step line (a dot per step, filled once
 * done) above a skeleton capsule card (header, three rows, a button pill) with a shimmer sweeping left to
 * right every ~1.2 s, and a small Cancel. With reduce motion on there is no shimmer and no pulse.
 */
import { Palette, Radius } from '../theme/Tokens';

const SHIMMER_MS = 1200;

@ComponentV2
export struct BuildSkeleton {
  /** The current step's text, e.g. "Asking Claude…". */
  @Require @Param stepText: string;
  @Param stepIndex: number = 0;
  @Param stepCount: number = 5;
  @Param reduceMotion: boolean = false;
  @Event onCancel: () => void = () => {
  };
  /** Shimmer band position, in its own widths: -1 is off the left edge, 2.7 off the right. */
  @Local shimmerX: number = -1;
  @Local pulse: number = 1;

  aboutToAppear(): void {
    if (this.reduceMotion) {
      return;
    }
    // Started after the first frame so the loops run from the initial values.
    setTimeout(() => {
      this.getUIContext().animateTo({ duration: SHIMMER_MS, curve: Curve.Linear, iterations: -1 }, () => {
        this.shimmerX = 2.7;
      });
      this.getUIContext().animateTo({ duration: 600, curve: Curve.EaseInOut, iterations: -1,
        playMode: PlayMode.Alternate }, () => {
        this.pulse = 0.35;
      });
    }, 16);
  }

  private dots(): number[] {
    const out: number[] = [];
    for (let i = 0; i < this.stepCount; i++) {
      out.push(i);
    }
    return out;
  }

  @Builder
  bar(width: Length, barHeight: number) {
    Column()
      .width(width)
      .height(barHeight)
      .borderRadius(barHeight / 2)
      .backgroundColor(Palette.track)
  }

  @Builder
  stepLine() {
    Row({ space: 8 }) {
      Row({ space: 4 }) {
        ForEach(this.dots(), (i: number) => {
          Circle()
            .width(7)
            .height(7)
            .fill(i <= this.stepIndex ? Palette.blue : Palette.track)
            .opacity(i === this.stepIndex && !this.reduceMotion ? this.pulse : 1)
        }, (i: number) => `${i}`)
      }
      Text(this.stepText)
        .fontSize(14)
        .fontWeight(600)
        .fontColor(Palette.text)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text('Cancel')
        .fontSize(14)
        .fontWeight(600)
        .fontColor(Palette.blue)
        .padding({ left: 8, top: 10, bottom: 10 }) // a 44vp-ish touch target
        .accessibilityText('Cancel building')
        .onClick(() => this.onCancel())
    }
    .width('100%')
  }

  build() {
    Column({ space: 10 }) {
      this.stepLine()
      Stack() {
        Column({ space: 12 }) {
          Row({ space: 10 }) {
            Column()
              .width(36)
              .height(36)
              .borderRadius(Radius.iconTile)
              .backgroundColor(Palette.track)
            this.bar('45%', 14)
          }
          .width('100%')
          this.bar('100%', 12)
          this.bar('85%', 12)
          this.bar('60%', 12)
          this.bar('100%', 40)
        }
        .width('100%')
        .padding(16)
        if (!this.reduceMotion) {
          Column()
            .width('37%')
            .height('100%')
            .linearGradient({ angle: 90, colors: [['#00FFFFFF', 0], [Palette.white90, 0.5], ['#00FFFFFF', 1]] })
            .opacity(0.8)
            .translate({ x: `${this.shimmerX * 100}%` })
            .hitTestBehavior(HitTestMode.None)
        }
      }
      .alignContent(Alignment.Start)
      .width('100%')
      .clip(true)
      .borderRadius(22)
      .backgroundColor(Palette.surface)
      .border({ width: 1, color: Palette.line2 })
    }
    .width('100%')
    .accessibilityText(this.stepText)
  }
}
