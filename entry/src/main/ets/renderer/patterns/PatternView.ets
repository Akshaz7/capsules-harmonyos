/**
 * The redesigned capsule body (section 6): one pattern block chosen by detectPattern, then every component the
 * pattern did not draw, in its original order, through GenericNode, then the runtime message.
 * View only. Every tap goes through the same runtime calls as before (press, dispatch, setInputValue), so the
 * gatekeeper, the validator and expressions see exactly what they saw before. Local @Local state here only
 * chooses what is shown (which timer the ring shows, converter order), never capsule state.
 */
import {
  ButtonComponent, Capsule, CapsuleComponent, DisplayComponent, InputComponent, TextComponent, TimerComponent, WhenComponent
} from '../../core';
import { CapsuleRuntime, formatClock, TimerState } from '../CapsuleRuntime';
import { Palette, Radius, Space, Type } from '../../theme/Tokens';
import { CheckboxRow, ProgressBar, RingProgress, SegmentedControl, SegmentRing } from '../../components/Controls';
import { Chip, GroupHeader } from '../../components/Surfaces';
import { PrimaryButton } from '../../components/Buttons';
import {
  ChecklistGroup,
  ConverterPair,
  detectPattern,
  GoalPlan,
  PatternKind,
  PatternPlan,
  QuizPlan,
  QuizStep,
  RecordItem,
  SegmentPick,
  VersusSide
} from './Detect';
import { CARD, GenericNode, isSecondaryButton, NUMBER_INPUT, secondaryAction, TEXT_INPUT } from './GenericNode';

/** Drops a literal "[x] " / "[ ] " prefix an author used as a fake checkbox (the real checkbox is drawn). */
function withoutFakeBox(text: string): string {
  return text.replace(/^\s*\[(x|X| )\]\s*/, '');
}

const MAX_SEGMENTS: number = 24;

/** Patterns that are finished and verified. Any other capsule renders through the classic CapsuleView path. */
export const FINISHED_PATTERNS: PatternKind[] = ['record-list', 'versus', 'form', 'converter'];

let lastCapsule: Capsule | undefined = undefined;
let lastPlan: PatternPlan = new PatternPlan();

/** The capsule's plan, detected once per capsule object (a changed capsule is a new object). */
export function planOf(capsule: Capsule): PatternPlan {
  if (lastCapsule !== capsule) {
    lastPlan = detectPattern(capsule);
    lastCapsule = capsule;
  }
  return lastPlan;
}

/** True when the capsule matches a finished pattern and so renders through PatternView. */
export function usesPattern(capsule: Capsule): boolean {
  return FINISHED_PATTERNS.indexOf(planOf(capsule).kind) >= 0;
}

@ComponentV2
export struct PatternView {
  @Require @Param runtime: CapsuleRuntime;
  @Param motionNote: string = '';
  @Event onPickCity: () => void = () => {
  };
  /** Which timer the ring shows (view only). */
  @Local ringIndex: number = 0;
  /** Converter: show the second pair on top (view only). */
  @Local swapped: boolean = false;

  private plan(): PatternPlan {
    return planOf(this.runtime.capsule);
  }

  private value(name: string): string {
    return name.length > 0 ? this.runtime.display(`{${name}}`) : '';
  }

  private num(name: string): number {
    const n = Number(this.value(name));
    return Number.isFinite(n) ? n : 0;
  }

  // ---- shared bits ----

  @Builder
  caption(text: string) {
    Text(text)
      .fontSize(Type.caption.size)
      .fontWeight(Type.caption.weight)
      .fontColor(Palette.text2)
      .width('100%')
  }

  @Builder
  action(b: ButtonComponent, primary: boolean) {
    if (primary && !isSecondaryButton(b)) {
      PrimaryButton({ label: b.label, buttonHeight: 52, enabledState: this.runtime.enabled(b),
        onTap: () => this.runtime.press(b) })
    } else {
      secondaryAction(b.label, this.runtime.enabled(b), 46, () => this.runtime.press(b))
    }
  }

  @Builder
  rest(plan: PatternPlan, quiet: boolean) {
    ForEach(this.runtime.capsule.ui, (c: CapsuleComponent) => {
      GenericNode({
        runtime: this.runtime, component: c, consumed: plan.consumed, motionNote: this.motionNote,
        quietButtons: quiet, onPickCity: this.onPickCity
      })
    }, (c: CapsuleComponent, i: number) => `${this.runtime.serial}-${i}-${c.type}`)
  }

  // ---- 1. record list ----

  @Builder
  recordCard(r: RecordItem) {
    Column({ space: 8 }) {
      CheckboxRow({
        checked: this.value(r.boolVar) === 'true',
        label: r.parts.filter((c: CapsuleComponent) => c.type === 'display').length > 0 ?
          withoutFakeBox(this.runtime.display((r.parts.filter((c: CapsuleComponent) => c.type === 'display')[0] as
            DisplayComponent).text)) : r.toggle.label,
        doneDims: true,
        onToggle: () => this.runtime.press(r.toggle)
      })
        .width('100%')
        .enabled(this.runtime.enabled(r.toggle))
      ForEach(r.parts.filter((c: CapsuleComponent) => c.type === 'input'), (c: CapsuleComponent) => {
        TextInput({
          text: this.runtime.inputDraft((c as InputComponent).bind),
          placeholder: (c as InputComponent).label
        })
          .width('100%')
          .attributeModifier(TEXT_INPUT)
          .onChange((v: string) => this.runtime.setInputValue((c as InputComponent).bind, v))
      }, (c: CapsuleComponent, i: number) => `in-${i}`)
      ForEach(r.parts.filter((c: CapsuleComponent) => c.type === 'display').slice(1), (c: CapsuleComponent) => {
        this.caption(withoutFakeBox(this.runtime.display((c as DisplayComponent).text)))
      }, (c: CapsuleComponent, i: number) => `d-${i}`)
      ForEach(r.parts.filter((c: CapsuleComponent) => c.type !== 'display' && c.type !== 'input'),
        (c: CapsuleComponent) => {
          GenericNode({ runtime: this.runtime, component: c, motionNote: this.motionNote,
            onPickCity: this.onPickCity })
        }, (c: CapsuleComponent, i: number) => `o-${i}`)
    }
    .attributeModifier(CARD)
  }

  @Builder
  recordList(plan: PatternPlan) {
    Column({ space: Space.cards }) {
      Row() {
        Text(`${plan.records.filter((r: RecordItem) => this.value(r.boolVar) === 'true').length} of ${plan.records.length} done`)
          .fontSize(Type.caption.size)
          .fontWeight(600)
          .fontColor(Palette.text2)
      }
      .width('100%')
      ProgressBar({
        value: plan.records.filter((r: RecordItem) => this.value(r.boolVar) === 'true').length,
        total: Math.max(1, plan.records.length), barHeight: 6
      })
      ForEach(plan.records, (r: RecordItem) => {
        this.recordCard(r)
      }, (r: RecordItem, i: number) => `${this.runtime.serial}-rec-${i}`)
      if (plan.addButton !== undefined) {
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(18)
              .fontColor([Palette.blue])
            Text((plan.addButton as ButtonComponent).label)
              .fontSize(Type.label.size + 1)
              .fontWeight(700)
              .fontColor(Palette.blue)
          }
        }
        .width('100%')
        .constraintSize({ minHeight: 52 })
        .borderRadius(Radius.button)
        .backgroundColor(Palette.surface)
        .border({ width: 1.5, color: Palette.dashed, style: BorderStyle.Dashed })
        .enabled(this.runtime.enabled(plan.addButton as ButtonComponent))
        .onClick(() => this.runtime.press(plan.addButton as ButtonComponent))
      }
    }
    .width('100%')
  }

  // ---- 2. versus ----

  @Builder
  versusSide(s: VersusSide) {
    Column({ space: 10 }) {
      Text(s.name)
        .fontSize(Type.input.size)
        .fontWeight(700)
        .fontColor(Palette.text)
        .maxLines(2)
        .textAlign(TextAlign.Center)
      Text(s.pointsText.length > 0 ? this.value(s.pointsText) : this.value(s.pointsVar))
        .fontSize(Type.heroMin + 8)
        .fontWeight(Type.heroWeight)
        .fontColor(Palette.text)
        .fontFeature(Type.TABULAR)
        .maxLines(1)
        .minFontSize(28)
        .maxFontSize(Type.heroMin + 8)
      if (s.gamesVar.length > 0) {
        Text(`Games ${this.value(s.gamesVar)}`)
          .fontSize(Type.caption.size)
          .fontWeight(600)
          .fontColor(Palette.text2)
          .fontFeature(Type.TABULAR)
      }
      PrimaryButton({ label: s.button.label, buttonHeight: 52, enabledState: this.runtime.enabled(s.button),
        onTap: () => this.runtime.press(s.button) })
    }
    .layoutWeight(1)
    .padding(14)
    .borderRadius(Radius.card)
    .backgroundColor(Palette.card)
  }

  @Builder
  versus(plan: PatternPlan) {
    Column({ space: Space.cards }) {
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
        ForEach(plan.chips, (c: CapsuleComponent) => {
          if (c.type === 'display') {
            Chip({ text: this.runtime.display((c as DisplayComponent).text) })
              .margin(4)
          } else if (c.type === 'when' && this.runtime.shown(c as WhenComponent)) {
            ForEach((c as WhenComponent).show, (d: CapsuleComponent) => {
              Chip({ text: this.runtime.display((d as DisplayComponent).text), fill: Palette.orangeTint,
                color: Palette.orangeText })
                .margin(4)
            }, (d: CapsuleComponent, j: number) => `w-${j}`)
          }
        }, (c: CapsuleComponent, i: number) => `chip-${i}`)
      }
      .width('100%')
      Row({ space: Space.cards }) {
        ForEach(plan.sides, (s: VersusSide) => {
          this.versusSide(s)
        }, (s: VersusSide, i: number) => `side-${i}`)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
  }

  // ---- 3. form + live result ----

  @Builder
  hero(d: DisplayComponent, lines: DisplayComponent[]) {
    Column({ space: 6 }) {
      Text(this.runtime.display(d.text))
        .fontSize(Type.pageTitle.size)
        .fontWeight(800)
        .fontColor(Palette.surface)
        .fontFeature(Type.TABULAR)
        .width('100%')
      ForEach(lines, (l: DisplayComponent) => {
        Text(this.runtime.display(l.text))
          .fontSize(Type.secondary.size)
          .fontWeight(600)
          .fontColor(Palette.white90)
          .fontFeature(Type.TABULAR)
          .width('100%')
      }, (l: DisplayComponent, i: number) => `line-${i}`)
    }
    .width('100%')
    .padding(18)
    .borderRadius(Radius.heroCard)
    .backgroundColor(Palette.blue)
  }

  @Builder
  inputRow(c: InputComponent, last: boolean) {
    Column() {
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
            .onChange((v: string) => this.runtime.setInputValue(c.bind, v))
        }
        .width('100%')
        .constraintSize({ minHeight: 56 })
      } else {
        Column({ space: 6 }) {
          this.caption(c.label)
          TextInput({ text: this.runtime.inputDraft(c.bind), placeholder: this.runtime.inputPlaceholder(c.bind) })
            .width('100%')
            .attributeModifier(TEXT_INPUT)
            .onChange((v: string) => this.runtime.setInputValue(c.bind, v))
        }
        .padding({ top: 8, bottom: 8 })
      }
      if (this.runtime.inputError(c.bind).length > 0) {
        Text(this.runtime.inputError(c.bind))
          .fontSize(Type.caption.size)
          .fontColor(Palette.orangeText)
          .width('100%')
          .padding({ bottom: 6 })
      }
      if (!last) {
        Divider().color(Palette.line2).strokeWidth(1)
      }
    }
    .width('100%')
  }

  @Builder
  segment(s: SegmentPick) {
    Column({ space: 8 }) {
      this.caption(s.label)
      SegmentedControl({
        items: s.buttons.map((b: ButtonComponent) => b.label),
        selected: Math.max(0, s.literals.indexOf(this.num(s.varName))),
        onSelect: (i: number) => this.runtime.press(s.buttons[i])
      })
    }
    .attributeModifier(CARD)
  }

  @Builder
  form(plan: PatternPlan) {
    Column({ space: Space.cards }) {
      if (plan.hero !== undefined) {
        this.hero(plan.hero as DisplayComponent, plan.subLines)
      }
      Column() {
        ForEach(plan.inputs, (c: InputComponent, i: number) => {
          this.inputRow(c, i === plan.inputs.length - 1)
        }, (c: InputComponent, i: number) => `${this.runtime.serial}-in-${i}`)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 4, bottom: 4 })
      .borderRadius(Radius.card)
      .backgroundColor(Palette.card)
      ForEach(plan.segments, (s: SegmentPick) => {
        this.segment(s)
      }, (s: SegmentPick, i: number) => `seg-${i}`)
    }
    .width('100%')
  }

  // ---- 4. converter ----

  @Builder
  converterSide(p: ConverterPair, top: boolean) {
    Column({ space: 8 }) {
      this.caption(p.input.label)
      TextInput({ text: this.runtime.inputDraft(p.input.bind), placeholder: this.runtime.inputPlaceholder(p.input.bind) })
        .type(InputType.NUMBER_DECIMAL)
        .width('100%')
        .height(56)
        .borderRadius(Radius.input)
        .backgroundColor(Palette.surface)
        .border({ width: 1, color: Palette.inputBorder })
        .fontSize(Type.pageTitle.size)
        .fontWeight(800)
        .fontColor(Palette.text)
        .onChange((v: string) => this.runtime.setInputValue(p.input.bind, v))
      if (this.runtime.inputError(p.input.bind).length > 0) {
        Text(this.runtime.inputError(p.input.bind))
          .fontSize(Type.caption.size)
          .fontColor(Palette.orangeText)
          .width('100%')
      }
      Text(this.runtime.display(p.result.text))
        .fontSize(top ? Type.pageTitle.size : Type.title.size)
        .fontWeight(top ? 800 : 700)
        .fontColor(top ? Palette.blue : Palette.text)
        .fontFeature(Type.TABULAR)
        .width('100%')
    }
    .attributeModifier(CARD)
  }

  @Builder
  converter(plan: PatternPlan) {
    Column({ space: Space.cards }) {
      this.converterSide(plan.pairs[this.swapped ? 1 : 0], true)
      if (plan.pairs.length > 1) {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.arrow_up'))
            .fontSize(20)
            .fontColor([Palette.blue])
            .rotate({ angle: this.swapped ? 180 : 0 })
        }
        .width(Space.touch)
        .height(Space.touch)
        .backgroundColor(Palette.tint)
        .accessibilityText('Swap')
        .onClick(() => {
          this.swapped = !this.swapped;
        })
        this.converterSide(plan.pairs[this.swapped ? 0 : 1], false)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  // ---- 5. timer ring ----

  @Builder
  ringCentre(t: TimerState | undefined, c: TimerComponent) {
    Column({ space: 4 }) {
      Text(t ? (t.done ? 'Done' : formatClock(t.remainingSec)) : formatClock(Math.round(c.minutes * 60)))
        .fontSize(Type.heroMax - 18)
        .fontWeight(Type.heroWeight)
        .fontColor(Palette.text)
        .fontFeature(Type.TABULAR)
      Text(t && t.running ? c.label : t && t.paused ? `${c.label} · paused` : c.label)
        .fontSize(Type.caption.size)
        .fontWeight(600)
        .fontColor(Palette.text2)
        .maxLines(2)
        .textAlign(TextAlign.Center)
    }
    .width('70%')
  }

  @Builder
  timerRing(plan: PatternPlan) {
    Column({ space: 14 }) {
      if (plan.timers.length > 1) {
        SegmentedControl({
          items: plan.timers.map((t: TimerComponent) => t.label),
          selected: Math.min(this.ringIndex, plan.timers.length - 1),
          onSelect: (i: number) => {
            this.ringIndex = i;
          }
        })
      }
      RingProgress({
        value: this.ringValue(plan.timers[Math.min(this.ringIndex, plan.timers.length - 1)]),
        total: Math.max(1, Math.round(plan.timers[Math.min(this.ringIndex, plan.timers.length - 1)].minutes * 60)),
        ringSize: 240,
        warm: /break|rest/i.test(plan.timers[Math.min(this.ringIndex, plan.timers.length - 1)].label)
      }) {
        this.ringCentre(this.runtime.timer(plan.timers[Math.min(this.ringIndex, plan.timers.length - 1)].id),
          plan.timers[Math.min(this.ringIndex, plan.timers.length - 1)])
      }
      this.ringControls(this.runtime.timer(plan.timers[Math.min(this.ringIndex, plan.timers.length - 1)].id))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  private ringValue(c: TimerComponent): number {
    const t = this.runtime.timer(c.id);
    return t ? Math.round(c.minutes * 60) - t.remainingSec : 0;
  }

  /** Only while a timer runs or is paused: the capsule's own buttons start timers, so Start is not added. */
  @Builder
  ringControls(t: TimerState | undefined) {
    if (t && (t.running || t.paused)) {
      Row({ space: Space.cards }) {
        Column() {
          PrimaryButton({ label: t.running ? 'Pause' : 'Resume', buttonHeight: 52,
            onTap: () => this.runtime.dispatch(`${t.running ? 'pauseTimer' : 'startTimer'}:${t.timerId}`) })
        }
        .layoutWeight(1)
        Column() {
          secondaryAction('Stop', true, 52, () => this.runtime.dispatch(`stopTimer:${t.timerId}`))
        }
        .layoutWeight(1)
      }
      .width('100%')
    }
  }

  // ---- 6. goal ring ----

  private goalCount(plan: PatternPlan): number {
    return plan.goal ? this.num(plan.goal.countVar) : 0;
  }

  private goalTotal(plan: PatternPlan): number {
    if (!plan.goal) {
      return 1;
    }
    return plan.goal.totalVar.length > 0 ? Math.max(1, this.num(plan.goal.totalVar)) :
      Math.max(1, plan.goal.totalLiteral);
  }

  @Builder
  goalCentre(plan: PatternPlan) {
    Column({ space: 2 }) {
      Text(`${this.goalCount(plan)}`)
        .fontSize(Type.heroMax - 12)
        .fontWeight(Type.heroWeight)
        .fontColor(Palette.text)
        .fontFeature(Type.TABULAR)
      Text(`of ${this.goalTotal(plan)}${plan.goal && plan.goal.unit.length > 0 ? ' ' + plan.goal.unit : ''}`)
        .fontSize(Type.caption.size)
        .fontWeight(600)
        .fontColor(Palette.text2)
        .maxLines(2)
        .textAlign(TextAlign.Center)
    }
    .width('70%')
  }

  @Builder
  goalRing(plan: PatternPlan) {
    Column({ space: 14 }) {
      if (this.goalTotal(plan) <= MAX_SEGMENTS) {
        SegmentRing({ segments: this.goalTotal(plan), filled: this.goalCount(plan), ringSize: 232 }) {
          this.goalCentre(plan)
        }
      } else {
        RingProgress({ value: Math.min(this.goalCount(plan), this.goalTotal(plan)), total: this.goalTotal(plan),
          ringSize: 232, stroke: 18 }) {
          this.goalCentre(plan)
        }
      }
      if (plan.goal && plan.goal.add !== undefined) {
        Row({ space: Space.cards }) {
          Column() {
            PrimaryButton({ label: (plan.goal.add as ButtonComponent).label, buttonHeight: 54,
              enabledState: this.runtime.enabled(plan.goal.add as ButtonComponent),
              onTap: () => this.runtime.press((plan.goal as GoalPlan).add as ButtonComponent) })
          }
          .layoutWeight(2)
          if (plan.goal.undo !== undefined) {
            Column() {
              secondaryAction((plan.goal.undo as ButtonComponent).label,
                this.runtime.enabled(plan.goal.undo as ButtonComponent), 54,
                () => this.runtime.press((plan.goal as GoalPlan).undo as ButtonComponent))
            }
            .layoutWeight(1)
          }
        }
        .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  // ---- 7. quiz ----

  private quizShown(plan: PatternPlan): number {
    if (!plan.quiz) {
      return 0;
    }
    return plan.quiz.steps.findIndex((s: QuizStep) => this.runtime.shown(s.when));
  }

  @Builder
  quiz(plan: PatternPlan) {
    if (plan.quiz !== undefined) {
      Column({ space: Space.cards }) {
        Row() {
          Text(this.quizShown(plan) >= 0 ?
            `Question ${this.quizShown(plan) + 1} of ${(plan.quiz as QuizPlan).steps.length}` : 'Finished')
            .fontSize(Type.caption.size)
            .fontWeight(600)
            .fontColor(Palette.text2)
            .layoutWeight(1)
          if ((plan.quiz as QuizPlan).score !== undefined) {
            Chip({ text: this.runtime.display(((plan.quiz as QuizPlan).score as DisplayComponent).text) })
          }
        }
        .width('100%')
        ProgressBar({
          value: this.quizShown(plan) >= 0 ? this.quizShown(plan) : (plan.quiz as QuizPlan).steps.length,
          total: Math.max(1, (plan.quiz as QuizPlan).steps.length), barHeight: 6
        })
        if ((plan.quiz as QuizPlan).question !== undefined) {
          Text(this.runtime.display(((plan.quiz as QuizPlan).question as DisplayComponent).text))
            .fontSize(Type.question.size)
            .fontWeight(Type.question.weight)
            .fontColor(Palette.text)
            .width('100%')
            .padding(18)
            .borderRadius(Radius.cardLarge)
            .backgroundColor(Palette.card)
        }
        ForEach((plan.quiz as QuizPlan).steps, (s: QuizStep) => {
          if (this.runtime.shown(s.when)) {
            Column({ space: Space.cards }) {
              ForEach(s.when.show, (c: CapsuleComponent) => {
                if (c.type === 'button') {
                  secondaryAction((c as ButtonComponent).label, this.runtime.enabled(c as ButtonComponent), 52,
                    () => this.runtime.press(c as ButtonComponent))
                } else if (c.type === 'display' || c.type === 'text') {
                  Text(c.type === 'display' ? this.runtime.display((c as DisplayComponent).text) :
                    (c as TextComponent).text)
                    .fontSize(Type.question.size)
                    .fontWeight(Type.question.weight)
                    .fontColor(Palette.text)
                    .width('100%')
                    .padding(18)
                    .borderRadius(Radius.cardLarge)
                    .backgroundColor(Palette.card)
                } else {
                  GenericNode({ runtime: this.runtime, component: c, motionNote: this.motionNote,
                    onPickCity: this.onPickCity })
                }
              }, (c: CapsuleComponent, j: number) => `q-${j}-${c.type}`)
            }
            .width('100%')
          }
        }, (s: QuizStep, i: number) => `${this.runtime.serial}-step-${i}`)
        if (!(plan.quiz as QuizPlan).buttonsInSteps) {
          ForEach((plan.quiz as QuizPlan).answers, (b: ButtonComponent) => {
            secondaryAction(b.label, this.runtime.enabled(b), 52, () => this.runtime.press(b))
          }, (b: ButtonComponent, i: number) => `ans-${i}`)
        }
        if ((plan.quiz as QuizPlan).next !== undefined) {
          PrimaryButton({ label: ((plan.quiz as QuizPlan).next as ButtonComponent).label, buttonHeight: 52,
            enabledState: this.runtime.enabled((plan.quiz as QuizPlan).next as ButtonComponent),
            onTap: () => this.runtime.press((plan.quiz as QuizPlan).next as ButtonComponent) })
        }
      }
      .width('100%')
    }
  }

  // ---- 8. grouped checklist ----

  private groupDone(g: ChecklistGroup): number {
    const s = this.runtime.checklist(g.list.id);
    return s ? s.checked.filter((v: boolean) => v).length : 0;
  }

  @Builder
  groups(plan: PatternPlan) {
    Column({ space: Space.cards }) {
      Column({ space: 8 }) {
        Text(`${plan.groups.reduce((n: number, g: ChecklistGroup) => n + this.groupDone(g), 0)} of ${plan.groups.reduce(
          (n: number, g: ChecklistGroup) => n + g.list.items.length, 0)} done`)
          .fontSize(Type.title.size)
          .fontWeight(Type.title.weight)
          .fontColor(Palette.text)
          .fontFeature(Type.TABULAR)
          .width('100%')
        ProgressBar({
          value: plan.groups.reduce((n: number, g: ChecklistGroup) => n + this.groupDone(g), 0),
          total: Math.max(1, plan.groups.reduce((n: number, g: ChecklistGroup) => n + g.list.items.length, 0))
        })
      }
      .attributeModifier(CARD)
      ForEach(plan.groups, (g: ChecklistGroup) => {
        Column() {
          GroupHeader({ name: g.title.text, count: `${this.groupDone(g)}/${g.list.items.length}` })
          ForEach(g.list.items, (item: string, i: number) => {
            CheckboxRow({
              checked: this.runtime.checklist(g.list.id)?.checked[i] ?? false, label: item, onToggle: () => {
                const s = this.runtime.checklist(g.list.id);
                if (s) {
                  this.runtime.setChecked(g.list.id, i, !s.checked[i]);
                }
              }
            })
              .width('100%')
          }, (item: string, i: number) => `${g.list.id}-${i}-${item}`)
        }
        .attributeModifier(CARD)
        .padding({ left: 14, right: 14, top: 2, bottom: 8 })
      }, (g: ChecklistGroup, i: number) => `${this.runtime.serial}-grp-${i}`)
    }
    .width('100%')
  }

  // ---- dispatch ----

  @Builder
  block(plan: PatternPlan) {
    if (plan.kind === 'record-list') {
      this.recordList(plan)
    } else if (plan.kind === 'versus') {
      this.versus(plan)
    } else if (plan.kind === 'form') {
      this.form(plan)
    } else if (plan.kind === 'converter') {
      this.converter(plan)
    } else if (plan.kind === 'timer-ring') {
      this.timerRing(plan)
    } else if (plan.kind === 'goal-ring') {
      this.goalRing(plan)
    } else if (plan.kind === 'quiz') {
      this.quiz(plan)
    } else if (plan.kind === 'grouped-checklist') {
      this.groups(plan)
    }
  }

  build() {
    Column({ space: Space.cards }) {
      this.block(this.plan())
      this.rest(this.plan(), this.plan().kind === 'versus' || this.plan().kind === 'goal-ring')
      if (this.runtime.message.length > 0) {
        Text(this.runtime.message)
          .fontSize(Type.secondary.size)
          .fontWeight(600)
          .fontColor(Palette.orangeText)
          .width('100%')
          .padding({ left: 4, right: 4 })
      }
    }
    .width('100%')
  }
}
