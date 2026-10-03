import {
  ButtonComponent,
  CapsuleComponent,
  ChecklistComponent,
  CounterComponent,
  NumberComponent,
  TextComponent,
  TimerComponent
} from '../core/CapsuleTypes';
import { CapsuleRuntime, ChecklistState, CounterState, NumberState, TimerState } from './CapsuleRuntime';

function formatSeconds(total: number): string {
  const m = Math.floor(total / 60);
  const s = total % 60;
  return `${m}:${s < 10 ? '0' : ''}${s}`;
}

/** Draws any schema v0 capsule. Holds no logic; all actions go to CapsuleRuntime.dispatch. */
@ComponentV2
export struct CapsuleView {
  @Require @Param runtime: CapsuleRuntime;

  @Builder
  textItem(c: TextComponent) {
    Text(c.text).fontSize(16).width('100%')
  }

  @Builder
  timerItem(c: TimerComponent, t: TimerState | undefined) {
    Row() {
      Text(c.label).fontSize(18).layoutWeight(1)
      Text(t ? (t.done ? 'Done' : formatSeconds(t.remainingSec)) : '-')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }

  @Builder
  counterItem(c: CounterComponent, s: CounterState | undefined) {
    Row() {
      Text(c.label).fontSize(18).layoutWeight(1)
      Text(s ? `${s.value}` : '-').fontSize(18)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }

  @Builder
  checklistItem(c: ChecklistComponent, s: ChecklistState | undefined) {
    Column() {
      ForEach(c.items, (item: string, i: number) => {
        Row() {
          Checkbox({ name: `${c.id}-${i}`, group: c.id })
            .select(s ? s.checked[i] : false)
            .onChange((value: boolean) => {
              if (s) {
                const next = s.checked.slice();
                next[i] = value;
                s.checked = next;
              }
            })
          Text(item).fontSize(16)
        }
        .width('100%')
      }, (item: string, i: number) => `${c.id}-${i}-${item}`)
    }
    .width('100%')
  }

  @Builder
  numberItem(c: NumberComponent, s: NumberState | undefined) {
    Row() {
      Text(c.label).fontSize(18).layoutWeight(1)
      TextInput({ text: s ? s.value : '' })
        .type(InputType.Number)
        .width(120)
        .onChange((value: string) => {
          if (s) {
            s.value = value;
          }
        })
    }
    .width('100%')
  }

  @Builder
  buttonItem(c: ButtonComponent) {
    Button(c.label)
      .width('100%')
      .margin({ top: 8 })
      .onClick(() => this.runtime.dispatch(c.action))
  }

  build() {
    Column({ space: 4 }) {
      Text(this.runtime.capsule.name)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .margin({ bottom: 8 })
      ForEach(this.runtime.capsule.ui, (c: CapsuleComponent) => {
        if (c.type === 'text') {
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
    .padding(16)
  }
}
