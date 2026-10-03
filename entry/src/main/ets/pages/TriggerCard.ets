import { Trigger } from '../core';
import { triggerNext, triggerTitle, triggerWhen } from './TriggerText';

/** The capsule's triggers (schema v1.1) on its page: when each runs, and Run now / change time / remove. */
@ComponentV2
export struct TriggerCard {
  @Param triggers: Trigger[] = [];
  /** Per trigger: is its permission granted? A blocked trigger never runs. */
  @Param allowed: boolean[] = [];
  /** Re-read "Next: ..." when this changes (the page bumps it on each check). */
  @Param now: number = Date.now();
  @Event onRunNow: (index: number) => void = () => {
  };
  @Event onEditTime: (index: number) => void = () => {
  };
  @Event onRemove: (index: number) => void = () => {
  };

  @Builder
  row(t: Trigger, i: number) {
    Column({ space: 8 }) {
      Row({ space: 12 }) {
        Stack() {
          SymbolGlyph(t.on === 'time' ? $r('sys.symbol.alarm') : $r('sys.symbol.figure_walk'))
            .fontSize(20)
            .fontColor([$r('sys.color.icon_emphasize')])
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        Column({ space: 2 }) {
          Text(triggerTitle(t))
            .fontSize($r('sys.float.Body_L'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.allowed[i] === false ? `${triggerWhen(t)} · Blocked: permission not allowed` :
            t.on === 'motion' ? `${triggerWhen(t)} · Shakes count while this capsule is open` :
            [triggerWhen(t), triggerNext(t, this.now)].filter((s: string) => s.length > 0).join(' · '))
            .fontSize($r('sys.float.Caption_M'))
            .fontColor(this.allowed[i] === false ? $r('sys.color.warning') : $r('sys.color.font_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      Row({ space: 8 }) {
        Button('Run now', { buttonStyle: ButtonStyleMode.NORMAL, controlSize: ControlSize.SMALL })
          .enabled(this.allowed[i] !== false)
          .onClick(() => this.onRunNow(i))
        if (t.on === 'time') {
          Button('Change time', { buttonStyle: ButtonStyleMode.NORMAL, controlSize: ControlSize.SMALL })
            .onClick(() => this.onEditTime(i))
        }
        Blank()
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(18)
            .fontColor([$r('sys.color.icon_secondary')])
        }
        .width(36)
        .height(36)
        .accessibilityText('Remove trigger')
        .onClick(() => this.onRemove(i))
      }
      .width('100%')
      .padding({ left: 52 })
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
  }

  build() {
    Column() {
      Text('Runs by itself')
        .fontSize($r('sys.float.Subtitle_S'))
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      ForEach(this.triggers, (t: Trigger, i: number) => {
        if (i > 0) {
          Divider()
            .color($r('sys.color.comp_divider'))
            .margin({ left: 52 })
        }
        this.row(t, i)
      }, (t: Trigger, i: number) => `${i}-${t.on}-${t.at ?? ''}-${t.label ?? ''}`)
      Text('While Harmoniser is open; a time missed while it was closed runs once when you come back.')
        .fontSize($r('sys.float.Caption_S'))
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
    }
    .width('100%')
    .padding(16)
    .borderRadius(20)
    .backgroundColor($r('sys.color.comp_background_primary'))
  }
}
