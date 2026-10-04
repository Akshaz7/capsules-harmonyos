import { common } from '@kit.AbilityKit';
import { LengthMetrics } from '@kit.ArkUI';
import {
  ButtonComponent,
  ButtonStep,
  CapsuleComponent,
  ChecklistComponent,
  CounterComponent,
  DeviceComponent,
  DisplayComponent,
  InputComponent,
  ListComponent,
  NumberComponent,
  RowComponent,
  TextComponent,
  TimerComponent,
  WhenComponent
} from '../core';
import { allComponents } from '../core/CapsuleProgram';
import { DeviceReadout } from '../capabilities/DeviceReadout';
import { weatherSymbolKey, WEATHER_URL } from '../capabilities/WeatherData';
import { CapsuleRuntime, ChecklistState, CounterState, formatClock, NumberState, TimerState } from './CapsuleRuntime';

/** True if some button in the capsule increments this counter, so the row needn't show a + icon too. */
function hasIncrementButton(components: CapsuleComponent[], counterId: string): boolean {
  const action = `increment:${counterId}`;
  return allComponents(components).some((c: CapsuleComponent) => {
    if (c.type !== 'button') {
      return false;
    }
    const b = c as ButtonComponent;
    return b.action === action || (b.do ?? []).some((step: ButtonStep) => step === action);
  });
}

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
  /** One line under motion counters: how to shake, or why it cannot count here. '' hides it. */
  @Param motionNote: string = '';
  /** Tapping a weather card asks the page to show its city picker. */
  @Event onPickCity: () => void = () => {
  };

  build() {
    Column({ space: 12 }) {
      ForEach(this.runtime.capsule.ui, (c: CapsuleComponent) => {
        CapsuleNode({
          runtime: this.runtime, component: c, motionNote: this.motionNote, onPickCity: this.onPickCity
        })
      }, (c: CapsuleComponent, i: number) => `${this.runtime.serial}-${i}-${c.type}`)
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
  @Param motionNote: string = '';
  @Event onPickCity: () => void = () => {
  };

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
      if (t && (t.running || t.paused)) {
        // Built-in controls for any running timer (T4-7 actions, so they go through the gatekeeper).
        Row({ space: 8 }) {
          this.timerControl(t, false)
          this.timerControl(t, true)
        }
        .width('100%')
      }
    }
    .sectionCard()
  }

  /** Pause/Resume (stop = false) or Stop. Reads `t` here so the label follows t.running. */
  @Builder
  timerControl(t: TimerState, stop: boolean) {
    Button({ type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL }) {
      Row({ space: 6 }) {
        SymbolGlyph(stop ? $r('sys.symbol.stop_circle') : t.running ? $r('sys.symbol.pause') : $r('sys.symbol.play_fill'))
          .fontSize(16)
          .fontColor([$r('sys.color.font_emphasize')])
        Text(stop ? 'Stop' : t.running ? 'Pause' : 'Resume')
          .fontSize($r('sys.float.Body_M'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_emphasize'))
      }
    }
    .layoutWeight(1)
    .height(40)
    .onClick(() => this.runtime.dispatch(
      `${stop ? 'stopTimer' : t.running ? 'pauseTimer' : 'startTimer'}:${t.timerId}`))
  }

  @Builder
  counterItem(c: CounterComponent, s: CounterState | undefined) {
    Column() {
      Row() {
        if (c.source === 'motion') {
          SymbolGlyph($r('sys.symbol.figure_walk'))
            .fontSize(20)
            .fontColor([$r('sys.color.icon_secondary')])
            .margin({ right: 10 })
        } else if (!hasIncrementButton(this.runtime.capsule.ui, c.id)) {
          SymbolGlyph($r('sys.symbol.plus_circle'))
            .fontSize(20)
            .fontColor([$r('sys.color.icon_secondary')])
            .margin({ right: 10 })
        }
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
      if (c.source === 'motion' && this.motionNote.length > 0) {
        Text(this.motionNote)
          .fontSize($r('sys.float.Caption_M'))
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
          .padding({ top: 6 })
      }
    }
    .sectionCard()
  }

  /** A read-only host reading (battery, weather). The capsule can show it but never write it. */
  @Builder
  deviceItem(c: DeviceComponent) {
    Column({ space: 6 }) {
      Row({ space: 10 }) {
        SymbolGlyph(this.deviceSymbol(c))
          .fontSize(20)
          .fontColor([$r('sys.color.icon_secondary')])
        Text(this.deviceTitle(c))
          .fontSize($r('sys.float.Subtitle_M'))
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
        Text(this.deviceValue(c))
          .fontSize($r('sys.float.Title_S'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .fontFeature('"tnum" on')
      }
      .width('100%')
      if (this.deviceDetail(c).length > 0) {
        Text(this.deviceDetail(c))
          .fontSize($r('sys.float.Caption_M'))
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
      }
      if (this.deviceSource(c).length > 0) {
        Text(this.deviceSource(c))
          .fontSize($r('sys.float.Caption_S'))
          .fontColor($r('sys.color.brand'))
          .width('100%')
          .onClick(() => this.openWeatherSource())
      }
    }
    .sectionCard()
    .onClick(() => {
      if (c.bind === 'weather') {
        this.onPickCity(); // choose or change the city
      }
    })
  }

  private deviceTitle(c: DeviceComponent): string {
    const r: DeviceReadout | undefined = this.runtime.deviceReadout(c.bind);
    if (r !== undefined && r.title.length > 0) {
      return r.title;
    }
    const label: string = c.label ?? '';
    if (label.length > 0) {
      return label;
    }
    return c.bind === 'weather' ? 'Weather' : 'Battery';
  }

  private deviceValue(c: DeviceComponent): string {
    const r: DeviceReadout | undefined = this.runtime.deviceReadout(c.bind);
    if (r === undefined || r.state === 'pending') {
      return '…';
    }
    return r.value.length > 0 ? r.value : '—';
  }

  private deviceDetail(c: DeviceComponent): string {
    const r: DeviceReadout | undefined = this.runtime.deviceReadout(c.bind);
    return r === undefined ? '' : r.detail;
  }

  private deviceSource(c: DeviceComponent): string {
    const r: DeviceReadout | undefined = this.runtime.deviceReadout(c.bind);
    return r === undefined ? '' : r.source;
  }

  private openWeatherSource(): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      ctx.openLink(WEATHER_URL).catch(() => {
      });
    } catch (e) {
    }
  }

  private deviceSymbol(c: DeviceComponent): Resource {
    const r: DeviceReadout | undefined = this.runtime.deviceReadout(c.bind);
    if (c.bind === 'weather') {
      const key: string = r === undefined ? 'cloud' : weatherSymbolKey(r.weatherCode);
      if (key === 'sun') {
        return $r('sys.symbol.sun_max');
      }
      if (key === 'partly') {
        return $r('sys.symbol.cloud_and_sun_fill');
      }
      if (key === 'snow') {
        return $r('sys.symbol.cloud_snow');
      }
      if (key === 'storm') {
        return $r('sys.symbol.cloud_heavy_storm');
      }
      if (key === 'rain') {
        return $r('sys.symbol.cloud_fill');
      }
      return $r('sys.symbol.cloud');
    }
    if (r !== undefined && r.charging) {
      return $r('sys.symbol.battery_bolt');
    }
    const p: number = r === undefined ? -1 : r.percent;
    if (p >= 90) {
      return $r('sys.symbol.battery_100percent');
    }
    if (p >= 70) {
      return $r('sys.symbol.battery_80percent');
    }
    if (p >= 50) {
      return $r('sys.symbol.battery_50percent');
    }
    if (p >= 30) {
      return $r('sys.symbol.battery_30percent');
    }
    if (p >= 15) {
      return $r('sys.symbol.battery_15percent');
    }
    return $r('sys.symbol.battery_5percent');
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
    // Label above the field: inside a narrow row a side-by-side label wrapped one letter per line.
    Column({ space: 8 }) {
      Text(c.label)
        .fontSize($r('sys.float.Body_M'))
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      // The current value is the placeholder, so typing replaces it instead of appending ("0" + "100" = "0100").
      TextInput({ text: this.runtime.inputDraft(c.bind), placeholder: this.runtime.inputPlaceholder(c.bind) })
        .type(c.kind === 'number' ? InputType.NUMBER_DECIMAL : InputType.Normal)
        .width('100%')
        .onChange((value: string) => this.runtime.setInputValue(c.bind, value))
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
    } else if (this.component.type === 'device') {
      this.deviceItem(this.component as DeviceComponent)
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
            CapsuleNode({
              runtime: this.runtime, component: child, motionNote: this.motionNote, onPickCity: this.onPickCity
            })
          }, (child: CapsuleComponent, i: number) => `${i}-${child.type}`)
        }
        .width('100%')
      }
    } else if (this.component.type === 'row' && (this.component as RowComponent).items.length >= 3) {
      // 3+ children wrap at a usable minimum width instead of squeezing into equal slivers.
      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(12), cross: LengthMetrics.vp(12) } }) {
        ForEach((this.component as RowComponent).items, (child: CapsuleComponent) => {
          Column() {
            CapsuleNode({
              runtime: this.runtime, component: child, motionNote: this.motionNote, onPickCity: this.onPickCity
            })
          }
          .flexGrow(1)
          .flexBasis(140)
        }, (child: CapsuleComponent, i: number) => `${i}-${child.type}`)
      }
      .width('100%')
    } else if (this.component.type === 'row') {
      Row({ space: 12 }) {
        ForEach((this.component as RowComponent).items, (child: CapsuleComponent) => {
          Column() {
            CapsuleNode({
              runtime: this.runtime, component: child, motionNote: this.motionNote, onPickCity: this.onPickCity
            })
          }
          .layoutWeight(1)
        }, (child: CapsuleComponent, i: number) => `${i}-${child.type}`)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
  }
}
