/**
 * Build progress (redesign, NEW_PROGRESS). The core reports no live stages, only the origin once done, so
 * this card shows the request, a busy bar, and the order the app really tries (core/CapsuleGenerator.ets):
 * your phone's rules and templates, then on-device AI, then the cloud when it may be used. No step is
 * marked as "current": that would be invented.
 */
import { Palette, Radius } from '../theme/Tokens';

export interface BuildStep {
  label: string;
  detail: string;
}

@ComponentV2
export struct BuildCard {
  @Require @Param request: string;
  @Param steps: BuildStep[] = [];

  build() {
    Column({ space: 12 }) {
      Text(this.request)
        .fontSize(17)
        .fontWeight(700)
        .fontColor(Palette.text)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Progress({ value: 0, total: 100, type: ProgressType.Linear })
        .width('100%')
        .height(4)
        .color(Palette.blue)
        .backgroundColor(Palette.track)
        .style({ strokeWidth: 4, strokeRadius: 2, enableScanEffect: true })
      Text('Tries these in order:')
        .fontSize(13)
        .fontWeight(500)
        .fontColor(Palette.text2)
        .width('100%')
      ForEach(this.steps, (step: BuildStep, i: number) => {
        Row({ space: 12 }) {
          Stack() {
            Text(`${i + 1}`)
              .fontSize(13)
              .fontWeight(700)
              .fontColor(Palette.chipText)
          }
          .width(28)
          .height(28)
          .borderRadius(14)
          .backgroundColor(Palette.tint)
          Column({ space: 2 }) {
            Text(step.label)
              .fontSize(16)
              .fontWeight(600)
              .fontColor(Palette.text)
            if (step.detail.length > 0) {
              Text(step.detail)
                .fontSize(13)
                .fontColor(Palette.text2)
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .constraintSize({ minHeight: 52 })
      }, (step: BuildStep) => step.label)
    }
    .width('100%')
    .padding(16)
    .borderRadius(Radius.cardLarge)
    .backgroundColor(Palette.frameBg)
    .border({ width: 1, color: Palette.frameBorder })
  }
}
