import { CapsuleRuntime, ChecklistState, formatClock, TimerState } from '../renderer/CapsuleRuntime';
import { capsuleIcon } from './CapsuleEntry';

/**
 * A live mini widget for the home "Recent" grid: a timer ring, a big count, or a checklist ring, read from
 * the capsule's running state (the same numbers its home-screen widget shows).
 */
@ComponentV2
export struct MiniPreview {
  @Require @Param runtime: CapsuleRuntime;

  @Builder
  ring(value: number, total: number, big: string, small: string) {
    Stack() {
      Progress({ value: value, total: total > 0 ? total : 1, type: ProgressType.Ring })
        .width(84)
        .height(84)
        .color($r('sys.color.brand'))
        .style({ strokeWidth: 8 })
      Column() {
        Text(big)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
        if (small.length > 0) {
          Text(small)
            .fontSize(11)
            .fontColor($r('sys.color.font_secondary'))
        }
      }
    }
  }

  build() {
    Column() {
      if (this.runtime.timers.length > 0) {
        this.ring(this.timerDone(this.runtime.timers[0]), this.runtime.timers[0].minutes * 60,
          formatClock(this.runtime.timers[0].remainingSec), this.runtime.timers[0].label)
      } else if (this.runtime.counters.length > 0) {
        Text(`${this.runtime.counters[0].value}`)
          .fontSize(44)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
        Text(this.runtime.counters[0].label)
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
      } else if (this.runtime.checklists.length > 0) {
        this.ring(this.ticked(this.runtime.checklists[0]), this.runtime.checklists[0].checked.length,
          `${this.ticked(this.runtime.checklists[0])}/${this.runtime.checklists[0].checked.length}`, 'done')
      } else {
        SymbolGlyph(capsuleIcon(this.runtime.capsule))
          .fontSize(40)
          .fontColor([$r('sys.color.icon_emphasize')])
      }
    }
    .width('100%')
    .aspectRatio(1)
    .justifyContent(FlexAlign.Center)
    .borderRadius(24)
    .backgroundColor($r('sys.color.comp_background_primary'))
  }

  private timerDone(t: TimerState): number {
    return Math.max(0, t.minutes * 60 - t.remainingSec);
  }

  private ticked(l: ChecklistState): number {
    return l.checked.filter((c: boolean) => c).length;
  }
}
