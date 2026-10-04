/**
 * The redesigned generic renderer (section 6 fallback): cards, stacked rows, and rows of 3+ children that wrap.
 * Draws one component and its children; skips components a pattern already drew (`consumed`).
 * No logic: buttons go to runtime.press, timer controls to runtime.dispatch, ticks to runtime.setChecked.
 * Device readings (weather, battery) keep the existing CapsuleNode so their behaviour stays exactly the same.
 */
import {
  ButtonComponent,
  Capsule,
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
} from '../../core';
import { CapsuleRuntime, ChecklistState, CounterState, formatClock, NumberState, TimerState } from '../CapsuleRuntime';
import { CapsuleNode } from '../CapsuleView';
import { Palette, Radius, Space, Type } from '../../theme/Tokens';
import { widthClass } from '../../theme/Breakpoint';
import { CheckboxRow, ProgressBar } from '../../components/Controls';
import { PrimaryButton } from '../../components/Buttons';
import { countOf, MAX_ROW_ACROSS, templateExprs } from './Detect';

/** Reset, undo, clear, restart, new ...: drawn as secondary buttons. */
export function isSecondaryButton(b: ButtonComponent): boolean {
  return (b.action ?? '').startsWith('reset:') || /^(reset|undo|clear|restart|new\b|start over|-\s*\d|−)/i.test(b.label.trim());
}

/** True when a display is exactly one bool var ("{done}"): drawn as a checkbox. */
export function boolDisplayVar(capsule: Capsule, template: string): string {
  const exprs = templateExprs(template);
  const literal = template.replace(/\{[^{}]*\}/g, '').trim();
  if (exprs.length !== 1 || literal.length > 0 || !/^[A-Za-z_][A-Za-z0-9_]*$/.test(exprs[0])) {
    return '';
  }
  const s = capsule.state;
  return s !== undefined && s[exprs[0]] !== undefined && s[exprs[0]].type === 'bool' ? exprs[0] : '';
}

/** Card fill, radius 18, padding 14: the generic container. */
export class PatternCard implements AttributeModifier<ColumnAttribute> {
  applyNormalAttribute(instance: ColumnAttribute): void {
    instance.width('100%').padding(14).borderRadius(Radius.card).backgroundColor(Palette.card);
  }
}

/** A 44vp input: white, 1vp border, radius 12; numbers right-aligned 18/700. */
export class PatternInput implements AttributeModifier<TextInputAttribute> {
  private alignEnd: boolean;

  constructor(alignEnd: boolean) {
    this.alignEnd = alignEnd;
  }

  applyNormalAttribute(instance: TextInputAttribute): void {
    instance.height(Space.touch)
      .borderRadius(Radius.input)
      .backgroundColor(Palette.surface)
      .border({ width: 1, color: Palette.inputBorder })
      .fontSize(this.alignEnd ? 18 : Type.input.size)
      .fontWeight(this.alignEnd ? 700 : Type.input.weight)
      .fontColor(Palette.text)
      .textAlign(this.alignEnd ? TextAlign.End : TextAlign.Start)
      .placeholderColor(Palette.disabled);
  }
}

export const CARD: PatternCard = new PatternCard();
export const NUMBER_INPUT: PatternInput = new PatternInput(true);
export const TEXT_INPUT: PatternInput = new PatternInput(false);

/** A secondary button (surface, 1vp border) that can be disabled; labels wrap instead of truncating. */
@Builder
export function secondaryAction(label: string, enabledState: boolean, buttonHeight: number, onTap: () => void) {
  Button({ type: ButtonType.Normal, stateEffect: true }) {
    Text(label)
      .fontSize(Type.label.size + 1)
      .fontWeight(700)
      .fontColor(enabledState ? Palette.text : Palette.disabled)
      .textAlign(TextAlign.Center)
      .padding({ left: 14, right: 14 })
  }
  .width('100%')
  .constraintSize({ minHeight: Math.max(buttonHeight, Space.touch) })
  .borderRadius(Radius.button)
  .backgroundColor(Palette.surface)
  .border({ width: 1, color: Palette.inputBorder })
  .enabled(enabledState)
  .onClick(onTap)
}

@ComponentV2
export struct GenericNode {
  @Require @Param runtime: CapsuleRuntime;
  @Require @Param component: CapsuleComponent;
  @Param consumed: CapsuleComponent[] = [];
  @Param motionNote: string = '';
  /** Draw every button as secondary (versus and goal patterns: their main actions live in the pattern). */
  @Param quietButtons: boolean = false;
  @Event onPickCity: () => void = () => {
  };

  private visible(c: CapsuleComponent): boolean {
    return this.consumed.indexOf(c) < 0;
  }

  @Builder
  blockedItem(c: CapsuleComponent, reason: string) {
    Row({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.lock'))
        .fontSize(20)
        .fontColor([Palette.text2])
      Column({ space: 2 }) {
        Text(`Blocked ${c.type}`)
          .fontSize(Type.label.size)
          .fontWeight(Type.label.weight)
          .fontColor(Palette.text2)
        Text(reason)
          .fontSize(Type.caption.size)
          .fontColor(Palette.text2)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(14)
    .borderRadius(Radius.card)
    .backgroundColor(Palette.card)
    .opacity(0.85)
  }

  @Builder
  textItem(c: TextComponent) {
    Text(c.text)
      .fontSize(Type.secondary.size)
      .fontWeight(500)
      .fontColor(Palette.text2)
      .width('100%')
      .padding({ left: 4, right: 4 })
  }

  @Builder
  timerControl(t: TimerState, stop: boolean) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row({ space: 6 }) {
        SymbolGlyph(stop ? $r('sys.symbol.stop_circle') : t.running ? $r('sys.symbol.pause') : $r('sys.symbol.play_fill'))
          .fontSize(16)
          .fontColor([Palette.orangeText])
        Text(stop ? 'Stop' : t.running ? 'Pause' : 'Resume')
          .fontSize(Type.label.size)
          .fontWeight(700)
          .fontColor(Palette.orangeText)
      }
    }
    .layoutWeight(1)
    .height(Space.touch)
    .borderRadius(Radius.button)
    .backgroundColor(Palette.orangeTint)
    .onClick(() => this.runtime.dispatch(
      `${stop ? 'stopTimer' : t.running ? 'pauseTimer' : 'startTimer'}:${t.timerId}`))
  }

  @Builder
  timerItem(c: TimerComponent, t: TimerState | undefined) {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.timer'))
          .fontSize(20)
          .fontColor([t && t.running ? Palette.blue : Palette.text2])
        Text(c.label)
          .fontSize(Type.input.size)
          .fontWeight(Type.input.weight)
          .fontColor(Palette.text)
          .layoutWeight(1)
        Text(t ? (t.done ? 'Done' : formatClock(t.remainingSec)) : '-')
          .fontSize(28)
          .fontWeight(800)
          .fontColor(t && t.done ? Palette.blue : Palette.text)
          .fontFeature(Type.TABULAR)
      }
      .width('100%')
      ProgressBar({
        value: t ? Math.round(c.minutes * 60) - t.remainingSec : 0,
        total: Math.max(1, Math.round(c.minutes * 60))
      })
      if (t && (t.running || t.paused)) {
        Row({ space: 8 }) {
          this.timerControl(t, false)
          this.timerControl(t, true)
        }
        .width('100%')
      }
    }
    .attributeModifier(CARD)
  }

  @Builder
  counterItem(c: CounterComponent, s: CounterState | undefined) {
    Column({ space: 6 }) {
      Row({ space: 10 }) {
        if (c.source === 'motion') {
          SymbolGlyph($r('sys.symbol.figure_walk'))
            .fontSize(20)
            .fontColor([Palette.text2])
        }
        Text(c.label)
          .fontSize(Type.input.size)
          .fontWeight(Type.input.weight)
          .fontColor(Palette.text)
          .layoutWeight(1)
        Text(s ? `${s.value}` : '-')
          .fontSize(40)
          .fontWeight(800)
          .fontColor(Palette.text)
          .fontFeature(Type.TABULAR)
      }
      .width('100%')
      if (c.source === 'motion' && this.motionNote.length > 0) {
        Text(this.motionNote)
          .fontSize(Type.caption.size)
          .fontColor(Palette.text2)
          .width('100%')
      }
    }
    .attributeModifier(CARD)
  }

  @Builder
  checklistItem(c: ChecklistComponent, s: ChecklistState | undefined) {
    Column({ space: 4 }) {
      if (c.items.length > 1) {
        Row() {
          Text(`${s ? s.checked.filter((v: boolean) => v).length : 0} of ${c.items.length} done`)
            .fontSize(Type.caption.size)
            .fontWeight(600)
            .fontColor(Palette.text2)
            .layoutWeight(1)
        }
        .width('100%')
        ProgressBar({ value: s ? s.checked.filter((v: boolean) => v).length : 0, total: c.items.length, barHeight: 4 })
          .margin({ bottom: 4 })
      }
      ForEach(c.items, (item: string, i: number) => {
        CheckboxRow({
          checked: s ? s.checked[i] : false, label: item, onToggle: () => {
            if (s) {
              this.runtime.setChecked(c.id, i, !s.checked[i]);
            }
          }
        })
          .width('100%')
      }, (item: string, i: number) => `${c.id}-${i}-${item}`)
    }
    .attributeModifier(CARD)
  }

  @Builder
  numberItem(c: NumberComponent, s: NumberState | undefined) {
    Row({ space: 12 }) {
      Text(c.label)
        .fontSize(Type.input.size)
        .fontWeight(Type.input.weight)
        .fontColor(Palette.text)
        .layoutWeight(1)
      TextInput({ text: s ? s.value : '', placeholder: '0' })
        .type(InputType.Number)
        .width(132)
        .attributeModifier(NUMBER_INPUT)
        .onChange((value: string) => {
          if (s) {
            s.value = value;
          }
        })
    }
    .width('100%')
    .padding(14)
    .borderRadius(Radius.card)
    .backgroundColor(Palette.card)
  }

  @Builder
  buttonItem(c: ButtonComponent) {
    if (this.quietButtons || isSecondaryButton(c)) {
      secondaryAction(c.label, this.runtime.enabled(c), 46, () => this.runtime.press(c))
    } else {
      PrimaryButton({
        label: c.label, buttonHeight: 52, enabledState: this.runtime.enabled(c), onTap: () => this.runtime.press(c)
      })
    }
  }

  @Builder
  displayItem(c: DisplayComponent) {
    Column({ space: 8 }) {
      if (boolDisplayVar(this.runtime.capsule, c.text).length > 0) {
        CheckboxRow({ checked: this.runtime.values[boolDisplayVar(this.runtime.capsule, c.text)] === true, label: '' })
          .enabled(false)
      } else {
        Text(this.runtime.display(c.text))
          .fontSize(Type.title.size)
          .fontWeight(Type.title.weight)
          .fontColor(Palette.text)
          .fontFeature(Type.TABULAR)
          .width('100%')
        if (countOf(this.runtime.display(c.text)) !== null) {
          ProgressBar({
            value: (countOf(this.runtime.display(c.text)) as number[])[0],
            total: (countOf(this.runtime.display(c.text)) as number[])[1]
          })
        }
      }
    }
    .attributeModifier(CARD)
  }

  @Builder
  inputItem(c: InputComponent) {
    Column({ space: 6 }) {
      if (c.kind === 'number') {
        Row({ space: 12 }) {
          Text(c.label)
            .fontSize(Type.input.size)
            .fontWeight(Type.input.weight)
            .fontColor(Palette.text)
            .layoutWeight(1)
          TextInput({ text: this.runtime.inputDraft(c.bind), placeholder: this.runtime.inputPlaceholder(c.bind) })
            .type(InputType.NUMBER_DECIMAL)
            .width(132)
            .attributeModifier(NUMBER_INPUT)
            .onChange((value: string) => this.runtime.setInputValue(c.bind, value))
        }
        .width('100%')
      } else {
        Text(c.label)
          .fontSize(Type.secondary.size)
          .fontWeight(Type.secondary.weight)
          .fontColor(Palette.text2)
          .width('100%')
        TextInput({ text: this.runtime.inputDraft(c.bind), placeholder: this.runtime.inputPlaceholder(c.bind) })
          .width('100%')
          .attributeModifier(TEXT_INPUT)
          .onChange((value: string) => this.runtime.setInputValue(c.bind, value))
      }
      if (this.runtime.inputError(c.bind).length > 0) {
        Text(this.runtime.inputError(c.bind))
          .fontSize(Type.caption.size)
          .fontColor(Palette.orangeText)
          .width('100%')
      }
    }
    .attributeModifier(CARD)
  }

  @Builder
  listItem(c: ListComponent) {
    Column() {
      if (this.runtime.items(c.source).length === 0) {
        Text('Nothing yet')
          .fontSize(Type.label.size)
          .fontWeight(500)
          .fontColor(Palette.text2)
          .width('100%')
          .constraintSize({ minHeight: Space.touch })
      } else {
        ForEach(this.runtime.items(c.source), (item: string, i: number) => {
          Column() {
            if (i > 0) {
              Divider().color(Palette.line2).strokeWidth(1)
            }
            Text(item)
              .fontSize(Type.label.size)
              .fontWeight(500)
              .fontColor(Palette.text)
              .width('100%')
              .constraintSize({ minHeight: Space.touch })
          }
        }, (item: string, i: number) => `${i}-${item}`)
      }
    }
    .attributeModifier(CARD)
    .padding({ left: 14, right: 14, top: 2, bottom: 2 })
  }

  @Builder
  child(c: CapsuleComponent) {
    GenericNode({
      runtime: this.runtime, component: c, consumed: this.consumed, motionNote: this.motionNote,
      quietButtons: this.quietButtons, onPickCity: this.onPickCity
    })
  }

  /** Rows: up to MAX_ROW_ACROSS side by side (4 on wide screens); wider rows stack their non-buttons and wrap
   * their buttons two per line. */
  @Builder
  rowItem(r: RowComponent) {
    if (r.items.filter((x: CapsuleComponent) => this.visible(x)).length <= (widthClass() === 'wide' ? 4 : MAX_ROW_ACROSS)) {
      Row({ space: Space.cards }) {
        ForEach(r.items.filter((x: CapsuleComponent) => this.visible(x)), (x: CapsuleComponent) => {
          Column() {
            this.child(x)
          }
          .layoutWeight(1)
        }, (x: CapsuleComponent, i: number) => `${i}-${x.type}`)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    } else {
      Column({ space: Space.cards }) {
        ForEach(r.items.filter((x: CapsuleComponent) => this.visible(x) && x.type !== 'button'), (x: CapsuleComponent) => {
          this.child(x)
        }, (x: CapsuleComponent, i: number) => `s${i}-${x.type}`)
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          ForEach(r.items.filter((x: CapsuleComponent) => this.visible(x) && x.type === 'button'), (x: CapsuleComponent) => {
            Column() {
              this.child(x)
            }
            .width('48.5%')
            .margin({ bottom: Space.cards })
          }, (x: CapsuleComponent, i: number) => `b${i}-${x.type}`)
        }
        .width('100%')
      }
      .width('100%')
    }
  }

  build() {
    if (!this.visible(this.component)) {
      // drawn by the pattern
    } else if (this.runtime.blockReason(this.component).length > 0) {
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
        Column({ space: Space.cards }) {
          ForEach((this.component as WhenComponent).show.filter((x: CapsuleComponent) => this.visible(x)),
            (x: CapsuleComponent) => {
              this.child(x)
            }, (x: CapsuleComponent, i: number) => `${i}-${x.type}`)
        }
        .width('100%')
      }
    } else if (this.component.type === 'row') {
      this.rowItem(this.component as RowComponent)
    } else {
      // device readings and anything newer: the existing node, unchanged
      CapsuleNode({
        runtime: this.runtime, component: this.component, motionNote: this.motionNote, onPickCity: this.onPickCity
      })
    }
  }
}
