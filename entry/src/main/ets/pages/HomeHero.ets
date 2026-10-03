import { curves } from '@kit.ArkUI';
import { reduceMotion } from './Motion';

const TITLE_WORDS: string[] = ['What', 'do', 'you', 'need?'];
const WORD_STAGGER_MS = 90;

/**
 * Home hero: "What do you need?" springs in word by word (simply there with reduce motion on).
 */
@ComponentV2
export struct HomeHero {
  @Local shown: number = 0;
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
  }

  aboutToDisappear(): void {
    this.timers.forEach((t: number) => clearTimeout(t));
  }

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
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
  }
}
