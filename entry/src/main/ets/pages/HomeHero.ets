import { curves } from '@kit.ArkUI';
import { reduceMotion } from './Motion';

const TITLE_WORDS: string[] = ['What', 'do', 'you', 'need?'];
const WORD_STAGGER_MS = 90;
const DRIFT_MS = 9000;

/**
 * Home hero (UI-1): "What do you need?" springs in word by word over a slow, blurred colour gradient.
 * With reduce motion on, the title is simply there and the gradient stands still.
 */
@ComponentV2
export struct HomeHero {
  @Local shown: number = 0;
  @Local drift: boolean = false;
  private timers: number[] = [];

  aboutToAppear(): void {
    if (reduceMotion()) {
      this.shown = TITLE_WORDS.length;
      return;
    }
    TITLE_WORDS.forEach((w: string, i: number) => {
      this.timers.push(setTimeout(() => {
        this.getUIContext().animateTo({ curve: curves.springMotion(0.5, 0.7) }, () => {
          this.shown = i + 1;
        });
      }, 120 + i * WORD_STAGGER_MS));
    });
    this.timers.push(setTimeout(() => {
      this.getUIContext().animateTo({
        duration: DRIFT_MS, curve: Curve.EaseInOut, iterations: -1, playMode: PlayMode.Alternate
      }, () => {
        this.drift = true;
      });
    }, 50));
  }

  aboutToDisappear(): void {
    this.timers.forEach((t: number) => clearTimeout(t));
  }

  /** `color`: RRGGBB without '#'. */
  @Builder
  blob(color: string, size: number, x: number, y: number, dx: number, dy: number) {
    Column()
      .width(size)
      .height(size)
      // A soft colour field: a radial gradient that fades to transparent (no hard edge, no blur pass).
      .radialGradient({ center: [size / 2, size / 2], radius: size / 2,
        colors: [[`#99${color}`, 0], [`#33${color}`, 0.55], [`#00${color}`, 1]] })
      .position({ x: x, y: y })
      .translate({ x: this.drift ? dx : 0, y: this.drift ? dy : 0 })
  }

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      // The gradient: three soft colour fields, drifting slowly, behind the title.
      Stack() {
        this.blob('5B8CFF', 260, -60, -90, 60, 30)
        this.blob('A77BFF', 220, 130, -70, -50, 40)
        this.blob('3CCFC2', 200, 230, -20, -30, -30)
      }
      .width('100%')
      .height(150)
      .clip(false)
      .hitTestBehavior(HitTestMode.None)
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(TITLE_WORDS, (word: string, i: number) => {
          Text(word)
            .fontSize(34)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
            .margin({ right: 9 })
            .opacity(i < this.shown ? 1 : 0)
            .translate({ y: i < this.shown ? 0 : 14 })
        }, (word: string) => word)
      }
      .width('100%')
      .accessibilityText('What do you need?')
    }
    .width('100%')
    .height(96)
    .clip(false)
  }
}
