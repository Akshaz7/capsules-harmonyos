import {
  ButtonComponent,
  CapsuleComponent,
  ChecklistComponent,
  CounterComponent,
  NumberComponent,
  TextComponent,
  TimerComponent
} from '../core';
import { CapsuleRuntime, ChecklistState, CounterState, formatClock, NumberState, TimerState } from './CapsuleRuntime';

/** Rounded section card on the grouped background. */
@Extend(Column)
function sectionCard() {
  .width('100%')
  .padding(16)
  .borderRadius(20)
  .backgroundColor($r('sys.color.comp_background_primary'))
}

/**
 * Draws any schema v0 capsule body (no title; the host page shows it).
 * Holds no logic; all actions go to CapsuleRuntime.dispatch.
 */
@ComponentV2
export struct CapsuleView {
  @Require @Param runtime: CapsuleRuntime;

  @Builder
  blockedItem(c: CapsuleComponent, reason: string) {
    Column() {
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.lock'))
          .fontSize(20)
          .fontColor([$r('sys.color.icon_secondary')])
        Column({ space: 2 }) {
          Text(`Blocked ${c.type}`)
            .fontSize($r('sys.float.Body_L'))
            .fontColor($r('sys.color.font_secondary'))
          Text(reason)
            .fontSize($r('sys.float.Caption_M'))
            .fontColor($r('sys.color.font_tertiary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
    }
    .sectionCard()
    .opacity(0.8)
  }

  @Builder
  textItem(c: TextComponent) {
    Text(c.text)
      .fontSize($r('sys.float.Body_L'))
      .fontColor($r('sys.color.font_secondary'))
      .width('100%')
      .padding({ left: 4, right: 4 })
  }

  @Builder
  timerItem(c: TimerComponent, t: TimerState | undefined) {
    Column({ space: 10 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.timer'))
          .fontSize(20)
          .fontColor([t && t.running ? $r('sys.color.icon_emphasize') : $r('sys.color.icon_secondary')])
          .margin({ right: 10 })
        Text(c.label)
          .fontSize($r('sys.float.Subtitle_M'))
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
        Text(t ? (t.done ? 'Done' : formatClock(t.remainingSec)) : '-')
          .fontSize($r('sys.float.Title_S'))
          .fontWeight(FontWeight.Medium)
          .fontColor(t && t.done ? $r('sys.color.confirm') : $r('sys.color.font_primary'))
          .fontFeature('"tnum" on')
      }
      .width('100%')
      Progress({
        value: t ? Math.round(c.minutes * 60) - t.remainingSec : 0,
        total: Math.max(1, Math.round(c.minutes * 60)),
        type: ProgressType.Linear
      })
        .color($r('sys.color.brand'))
        .width('100%')
    }
    .sectionCard()
  }

  @Builder
  counterItem(c: CounterComponent, s: CounterState | undefined) {
    Column() {
      Row() {
        SymbolGlyph(c.source === 'motion' ? $r('sys.symbol.figure_walk') : $r('sys.symbol.plus_circle'))
          .fontSize(20)
          .fontColor([$r('sys.color.icon_secondary')])
          .margin({ right: 10 })
        Text(c.label)
          .fontSize($r('sys.float.Subtitle_M'))
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
        Text(s ? `${s.value}` : '-')
          .fontSize(40)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
      }
      .width('100%')
    }
    .sectionCard()
  }

  @Builder
  checklistItem(c: ChecklistComponent, s: ChecklistState | undefined) {
    Column() {
      ForEach(c.items, (item: string, i: number) => {
        Row({ space: 12 }) {
          Checkbox({ name: `${c.id}-${i}`, group: c.id })
            .select(s ? s.checked[i] : false)
            .selectedColor($r('sys.color.brand'))
            .onChange((value: boolean) => {
              if (s && s.checked[i] !== value) {
                this.runtime.setChecked(c.id, i, value);
              }
            })
          Text(item)
            .fontSize($r('sys.float.Body_L'))
            .fontColor(s && s.checked[i] ? $r('sys.color.font_tertiary') : $r('sys.color.font_primary'))
            .decoration({ type: s && s.checked[i] ? TextDecorationType.LineThrough : TextDecorationType.None })
            .layoutWeight(1)
        }
        .width('100%')
        .height(48)
      }, (item: string, i: number) => `${c.id}-${i}-${item}`)
    }
    .sectionCard()
    .padding({ left: 12, right: 16, top: 4, bottom: 4 })
  }

  @Builder
  numberItem(c: NumberComponent, s: NumberState | undefined) {
    Column() {
      Row() {
        Text(c.label)
          .fontSize($r('sys.float.Subtitle_M'))
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
        TextInput({ text: s ? s.value : '', placeholder: '0' })
          .type(InputType.Number)
          .width(120)
          .textAlign(TextAlign.End)
          .onChange((value: string) => {
            if (s) {
              s.value = value;
            }
          })
      }
      .width('100%')
    }
    .sectionCard()
  }

  @Builder
  buttonItem(c: ButtonComponent) {
    Button(c.label)
      .width('100%')
      .height(48)
      .fontSize($r('sys.float.Body_L'))
      .fontWeight(FontWeight.Medium)
      // Reset is secondary: tonal instead of filled.
      .backgroundColor(c.action.startsWith('reset:') ? $r('sys.color.comp_background_tertiary') : $r('sys.color.brand'))
      .fontColor(c.action.startsWith('reset:') ? $r('sys.color.font_primary') : $r('sys.color.font_on_primary'))
      .onClick(() => this.runtime.dispatch(c.action))
  }

  build() {
    Column({ space: 12 }) {
      ForEach(this.runtime.capsule.ui, (c: CapsuleComponent, i: number) => {
        if (this.runtime.blockReason(i).length > 0) {
          this.blockedItem(c, this.runtime.blockReason(i))
        } else if (c.type === 'text') {
          this.textItem(c as TextComponent)
        } else if (c.type === 'timer') {
          this.timerItem(c as TimerComponent, this.runtime.timer((c as TimerComponent).id))
        } else if (c.type === 'counter') {
          this.counterItem(c as CounterComponent, this.runtime.counter((c as CounterComponent).id))
        } else if (c.type === 'checklist') {
          this.checklistItem(c as ChecklistComponent, this.runtime.checklist((c as ChecklistComponent).id))
        } else if (c.type === 'number') {
          this.numberItem(c as NumberComponent, this.runtime.numberField((c as NumberComponent).id))
        } else if (c.type === 'button') {
          this.buttonItem(c as ButtonComponent)
        }
      }, (c: CapsuleComponent, i: number) => `${i}-${c.type}`)
    }
    .width('100%')
  }
}
