import {
  ButtonComponent,
  CapsuleComponent,
  ChecklistComponent,
  CounterComponent,
  DisplayComponent,
  InputComponent,
  ListComponent,
  NumberComponent,
  RowComponent,
  TextComponent,
  TimerComponent,
  WhenComponent
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
 * Draws any schema v0 or v1 capsule body (no title; the host page shows it).
 * Holds no logic: buttons go to CapsuleRuntime.press, which runs core's interpreter.
 */
@ComponentV2
export struct CapsuleView {
  @Require @Param runtime: CapsuleRuntime;

  build() {
    Column({ space: 12 }) {
      ForEach(this.runtime.capsule.ui, (c: CapsuleComponent) => {
        CapsuleNode({ runtime: this.runtime, component: c })
      }, (c: CapsuleComponent, i: number) => `${i}-${c.type}`)
      if (this.runtime.message.length > 0) {
        Text(this.runtime.message)
          .fontSize($r('sys.float.Body_M'))
          .fontColor($r('sys.color.warning'))
          .width('100%')
          .padding({ left: 4, right: 4 })
      }
    }
    .width('100%')
  }
}

/** One component. when/row hold more CapsuleNodes, so nesting works at any depth. */
@ComponentV2
struct CapsuleNode {
  @Require @Param runtime: CapsuleRuntime;
  @Require @Param component: CapsuleComponent;

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
      .enabled(this.runtime.enabled(c))
      .opacity(this.runtime.enabled(c) ? 1 : 0.4)
      .onClick(() => this.runtime.press(c))
  }

  @Builder
  displayItem(c: DisplayComponent) {
    Column() {
      Text(this.runtime.display(c.text))
        .fontSize($r('sys.float.Title_S'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .fontFeature('"tnum" on')
        .width('100%')
    }
    .sectionCard()
  }

  @Builder
  inputItem(c: InputComponent) {
    Column({ space: 4 }) {
      Row() {
        Text(c.label)
          .fontSize($r('sys.float.Subtitle_M'))
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
        TextInput({ text: this.runtime.inputValue(c.bind), placeholder: c.kind === 'number' ? '0' : '' })
          .type(c.kind === 'number' ? InputType.NUMBER_DECIMAL : InputType.Normal)
          .width(c.kind === 'number' ? 120 : 180)
          .textAlign(c.kind === 'number' ? TextAlign.End : TextAlign.Start)
          .onChange((value: string) => this.runtime.setInputValue(c.bind, value))
      }
      .width('100%')
      if (this.runtime.inputError(c.bind).length > 0) {
        Text(this.runtime.inputError(c.bind))
          .fontSize($r('sys.float.Caption_M'))
          .fontColor($r('sys.color.warning'))
          .width('100%')
      }
    }
    .sectionCard()
  }

  @Builder
  listItem(c: ListComponent) {
    Column() {
      if (this.runtime.items(c.source).length === 0) {
        Text('Nothing yet')
          .fontSize($r('sys.float.Body_L'))
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
          .height(48)
      } else {
        ForEach(this.runtime.items(c.source), (item: string) => {
          Text(item)
            .fontSize($r('sys.float.Body_L'))
            .fontColor($r('sys.color.font_primary'))
            .width('100%')
            .height(48)
        }, (item: string, i: number) => `${i}-${item}`)
      }
    }
    .sectionCard()
    .padding({ left: 16, right: 16, top: 4, bottom: 4 })
  }

  build() {
    if (this.runtime.blockReason(this.component).length > 0) {
      this.blockedItem(this.component, this.runtime.blockReason(this.component))
    } else if (this.component.type === 'text') {
      this.textItem(this.component as TextComponent)
    } else if (this.component.type === 'timer') {
      this.timerItem(this.component as TimerComponent, this.runtime.timer((this.component as TimerComponent).id))
    } else if (this.component.type === 'counter') {
      this.counterItem(this.component as CounterComponent,
        this.runtime.counter((this.component as CounterComponent).id))
    } else if (this.component.type === 'checklist') {
      this.checklistItem(this.component as ChecklistComponent,
        this.runtime.checklist((this.component as ChecklistComponent).id))
    } else if (this.component.type === 'number') {
      this.numberItem(this.component as NumberComponent,
        this.runtime.numberField((this.component as NumberComponent).id))
    } else if (this.component.type === 'button') {
      this.buttonItem(this.component as ButtonComponent)
    } else if (this.component.type === 'display') {
      this.displayItem(this.component as DisplayComponent)
    } else if (this.component.type === 'input') {
      this.inputItem(this.component as InputComponent)
    } else if (this.component.type === 'list') {
      this.listItem(this.component as ListComponent)
    } else if (this.component.type === 'when') {
      if (this.runtime.shown(this.component as WhenComponent)) {
        Column({ space: 12 }) {
          ForEach((this.component as WhenComponent).show, (child: CapsuleComponent) => {
            CapsuleNode({ runtime: this.runtime, component: child })
          }, (child: CapsuleComponent, i: number) => `${i}-${child.type}`)
        }
        .width('100%')
      }
    } else if (this.component.type === 'row') {
      Row({ space: 12 }) {
        ForEach((this.component as RowComponent).items, (child: CapsuleComponent) => {
          Column() {
            CapsuleNode({ runtime: this.runtime, component: child })
          }
          .layoutWeight(1)
        }, (child: CapsuleComponent, i: number) => `${i}-${child.type}`)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
  }
}
