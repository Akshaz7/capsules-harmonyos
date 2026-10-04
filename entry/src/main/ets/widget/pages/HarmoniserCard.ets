/**
 * Harmoniser widget card (2x2 and 2x4). Runs in the system's form renderer, so it imports
 * nothing and only uses widget-capable components. It draws the WidgetView JSON built by
 * core/WidgetModel.ets (field names must match) and sends taps back with postCardAction.
 *
 * Design: one main element fills the card (big number, progress ring, tick list or score), a capsule icon
 * and the widget's accent colour (colorTag) up top, 16vp padding, tap targets of 48vp where the card has room,
 * and system colour resources (comp_background_primary, font_primary, ...) so it follows light and dark mode.
 * The system already shows the app name under the widget, so the card does not repeat it.
 */

interface CardCheckItem {
  index: number;
  text: string;
  checked: boolean;
}

interface CardRow {
  key: string;
  kind: string;
  id: string;
  label: string;
  minutes: number;
  endAt: number;
  canStart: boolean;
  value: number;
  canIncrement: boolean;
  items: CardCheckItem[];
  open?: CardCheckItem[];
}

/** A checklist's unticked items (views from older builds have no "open" field). */
function openItems(r: CardRow): CardCheckItem[] {
  return r.open ?? r.items.filter((i: CardCheckItem) => !i.checked);
}

interface CardDisplay {
  key: string;
  kind: string;
  text: string;
  label: string;
  left: string;
  right: string;
}

interface CardButton {
  index: number;
  label: string;
  enabled: boolean;
}

interface CardView {
  status: string;
  capsuleId: string;
  title: string;
  message: string;
  rows: CardRow[];
  wide: boolean;
  formId?: string;
  layout: string;
  icon: string;
  colorTag: number;
  accent: string;
  caption: string;
  value: number;
  goal: number;
  displays: CardDisplay[];
  buttons: CardButton[];
}

const MAX_TEXT_TIMER_MS: number = 86399000;
const PAD: number = 16;
const BIG_BUTTON: number = 48;

function parseView(raw: string): CardView {
  try {
    if (raw.length > 0) {
      const v = JSON.parse(raw) as CardView;
      // Views pushed by an older build lack the new fields.
      if (v.layout === undefined) {
        v.layout = v.status === 'ok' ? 'rows' : 'message';
      }
      return v;
    }
  } catch (e) {
    // fall through to the placeholder
  }
  const empty: CardView = {
    status: 'empty', capsuleId: '', title: 'Harmoniser', message: '', rows: [], wide: false, layout: 'message',
    icon: 'blank', colorTag: 0, accent: '#0A59F7', caption: '', value: 0, goal: 0, displays: [], buttons: []
  };
  return empty;
}

/** "#0A59F7" -> "#260A59F7" (the accent at ~15% opacity, for chips and tracks). */
function tint(accent: string): string {
  return accent.length === 7 ? `#26${accent.substring(1)}` : accent;
}

function minutesText(minutes: number): string {
  const total = Math.round(minutes * 60);
  const m = Math.floor(total / 60);
  const s = total % 60;
  return `${m}:${s < 10 ? '0' : ''}${s}`;
}

function numberText(n: number): string {
  return Number.isInteger(n) ? `${n}` : `${Math.round(n * 10) / 10}`;
}

let storage = new LocalStorage();

@Entry(storage)
@Component
struct HarmoniserCard {
  @LocalStorageProp('view') viewJson: string = '';

  private openApp(capsuleId: string): void {
    postCardAction(this, {
      action: 'router',
      abilityName: 'EntryAbility',
      params: { capsuleId: capsuleId, source: 'harmoniser' }
    });
  }

  /** A blank widget opens the app's capsule picker for this widget. */
  private chooseCapsule(formId: string): void {
    postCardAction(this, {
      action: 'router',
      abilityName: 'EntryAbility',
      params: { source: 'harmoniser', action: 'chooseCapsule', formId: formId }
    });
  }

  private onTap(): void {
    const v = parseView(this.viewJson);
    if (v.capsuleId.length === 0) {
      this.chooseCapsule(v.formId ?? '');
    } else {
      this.openApp(v.capsuleId);
    }
  }

  private send(op: string, id: string, index: number): void {
    postCardAction(this, { action: 'message', params: { op: op, id: id, index: index } });
  }

  /** A v1 button: the form extension runs its "do" steps (disabled buttons do nothing). */
  private press(v: CardView, b: CardButton): void {
    if (b.enabled) {
      this.send('press', '', b.index);
    }
  }

  // ---- Pieces ----

  @Builder
  icon(name: string, size: number, color: string) {
    if (name === 'timer') {
      SymbolGlyph($r('sys.symbol.timer')).fontSize(size).fontColor([color])
    } else if (name === 'counter') {
      SymbolGlyph($r('sys.symbol.plus_circle')).fontSize(size).fontColor([color])
    } else if (name === 'checklist') {
      SymbolGlyph($r('sys.symbol.list_checkmask')).fontSize(size).fontColor([color])
    } else if (name === 'goal') {
      SymbolGlyph($r('sys.symbol.flag')).fontSize(size).fontColor([color])
    } else if (name === 'logic') {
      SymbolGlyph($r('sys.symbol.flag_checkered')).fontSize(size).fontColor([color])
    } else if (name === 'text') {
      SymbolGlyph($r('sys.symbol.list_bullet')).fontSize(size).fontColor([color])
    } else {
      SymbolGlyph($r('sys.symbol.plus')).fontSize(size).fontColor([color])
    }
  }

  @Builder
  header(v: CardView, trailing: string) {
    Row({ space: 8 }) {
      Stack() {
        this.icon(v.icon, 16, v.accent)
      }
      .width(28)
      .height(28)
      .borderRadius(14)
      .backgroundColor(tint(v.accent))

      Text(v.title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (trailing.length > 0) {
        Text(trailing)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(v.accent)
          .maxLines(1)
      }
    }
    .width('100%')
    .height(28)
    .responseRegion({ x: 0, y: -10, width: '100%', height: BIG_BUTTON }) // 48vp tap area
    .onClick(() => this.onTap()) // the title opens the app; the rest of the card is left to its buttons
  }

  /** A large round accent button with a system symbol. */
  @Builder
  roundButton(v: CardView, symbol: string, size: number, enabled: boolean) {
    Stack() {
      if (symbol === 'play') {
        SymbolGlyph($r('sys.symbol.play_fill')).fontSize(size * 0.42).fontColor([$r('sys.color.font_on_primary')])
      } else {
        SymbolGlyph($r('sys.symbol.plus')).fontSize(size * 0.46).fontColor([$r('sys.color.font_on_primary')])
      }
    }
    .width(size)
    .height(size)
    .borderRadius(size / 2)
    .backgroundColor(v.accent)
    .opacity(enabled ? 1 : 0.4)
  }

  @Builder
  note(v: CardView) {
    if (v.message.length > 0) {
      Text(v.message)
        .fontSize(11)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
  }

  // ---- Layouts ----

  @Builder
  counterLayout(v: CardView, r: CardRow) {
    Column() {
      this.header(v, '')
      Row() {
        Column({ space: 2 }) {
          Text(`${r.value}`)
            .fontSize(v.wide ? 56 : 48)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .minFontSize(28)
            .maxFontSize(v.wide ? 56 : 48)
          Text(v.caption.length > 0 ? v.caption : r.label)
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (r.canIncrement) {
          Stack() {
            this.roundButton(v, 'plus', v.wide ? 56 : 52, true)
          }
          .onClick(() => this.send('increment', r.id, -1))
        }
      }
      .width('100%')
      .layoutWeight(1)
      .alignItems(VerticalAlign.Bottom)
      this.note(v)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  goalLayout(v: CardView) {
    Column() {
      this.header(v, v.value >= v.goal ? 'Done' : '')
      Row({ space: 12 }) {
        Stack() {
          Progress({ value: Math.min(v.value, v.goal), total: v.goal, type: ProgressType.Ring })
            .width(v.wide ? 92 : 80)
            .height(v.wide ? 92 : 80)
            .color(v.accent)
            .backgroundColor(tint(v.accent))
            .style({ strokeWidth: 8 })
          Column() {
            Text(numberText(v.value))
              .fontSize(v.wide ? 30 : 26)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('sys.color.font_primary'))
              .maxLines(1)
              .minFontSize(14)
              .maxFontSize(v.wide ? 30 : 26)
            Text(`/ ${numberText(v.goal)}`).fontSize(11).fontColor($r('sys.color.font_secondary'))
          }
          .width(v.wide ? 72 : 60)
        }

        Column({ space: 8 }) {
          if (v.wide) {
            Text(v.caption)
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          Row({ space: 8 }) {
            if (v.buttons.length > 0) {
              Stack() {
                this.roundButton(v, 'plus', BIG_BUTTON, v.buttons[0].enabled)
              }
              .onClick(() => this.press(v, v.buttons[0]))
            }
            if (v.wide && v.buttons.length > 1) {
              this.pill(v, v.buttons[1], false)
            }
          }
          .justifyContent(v.wide ? FlexAlign.Start : FlexAlign.End)
          .width('100%')
        }
        .layoutWeight(1)
        .alignItems(v.wide ? HorizontalAlign.Start : HorizontalAlign.End)
      }
      .width('100%')
      .layoutWeight(1)
      if (!v.wide && v.caption.length > 0) {
        Text(v.caption)
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      this.note(v)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  timerLayout(v: CardView, r: CardRow) {
    Column() {
      this.header(v, '')
      HeroTimer({ row: r, accent: v.accent, wide: v.wide })
        .layoutWeight(1)
      this.note(v)
    }
    .width('100%')
    .height('100%')
  }

  /** Only unticked items, in order; "+N more" counts the remaining unticked ones; "All done" at the end. */
  @Builder
  checklistLayout(v: CardView, r: CardRow) {
    Column({ space: 4 }) {
      this.header(v, v.caption)
      if (openItems(r).length === 0) {
        Column({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.checkmark_circle')).fontSize(32).fontColor([v.accent])
          Text('All done').fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
          Text('Tap to open').fontSize(11).fontColor($r('sys.color.font_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .onClick(() => this.onTap())
      } else {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(openItems(r).slice(0, v.wide ? 4 : 2), (item: CardCheckItem) => {
            CheckRow({ listId: r.id, item: item, wide: v.wide, accent: v.accent })
          }, (item: CardCheckItem) => `${r.id}-${item.index}-${item.checked}`)
        }
        .width('100%')
        .layoutWeight(1)
        if (openItems(r).length > (v.wide ? 4 : 2)) {
          Text(`+${openItems(r).length - (v.wide ? 4 : 2)} more`)
            .fontSize(11)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
        }
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  scoreLine(v: CardView, d: CardDisplay, big: boolean) {
    Column() {
      if (d.label.length > 0) {
        Text(d.label).fontSize(11).fontColor($r('sys.color.font_secondary')).maxLines(1)
      }
      Row() {
        Text(d.left)
          .fontSize(big ? 34 : 24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text('–').fontSize(big ? 22 : 16).fontColor($r('sys.color.font_tertiary'))
        Text(d.right)
          .fontSize(big ? 34 : 24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  textLine(d: CardDisplay, big: boolean) {
    Text(d.text)
      .fontSize(big ? 22 : 14)
      .fontWeight(big ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(big ? $r('sys.color.font_primary') : $r('sys.color.font_secondary'))
      .maxLines(1)
      .minFontSize(12)
      .maxFontSize(big ? 22 : 14)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .textAlign(TextAlign.Center)
      .width('100%')
  }

  @Builder
  pill(v: CardView, b: CardButton, fill: boolean) {
    Text(b.label)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(fill ? $r('sys.color.font_on_primary') : v.accent)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .textAlign(TextAlign.Center)
      .padding({ left: 12, right: 12 })
      .height(BIG_BUTTON)
      .width('100%')
      .constraintSize({ minWidth: 64 })
      .borderRadius(BIG_BUTTON / 2)
      .backgroundColor(fill ? v.accent : tint(v.accent))
      .opacity(b.enabled ? 1 : 0.4)
      .onClick(() => this.press(v, b))
  }

  @Builder
  logicLayout(v: CardView) {
    Column({ space: 6 }) {
      this.header(v, '')
      if (v.wide) {
        Row({ space: 12 }) {
          Column({ space: 4 }) {
            ForEach(v.displays.slice(0, 3), (d: CardDisplay, i: number) => {
              if (d.kind === 'score') {
                this.scoreLine(v, d, i === 0)
              } else {
                this.textLine(d, i === 0 || v.displays[0].kind === 'score')
              }
            }, (d: CardDisplay) => d.key)
            ForEach(v.rows.slice(0, 2), (r: CardRow) => {
              CompactRow({ row: r, accent: v.accent })
            }, (r: CardRow) => r.key)
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .height('100%')

          Column({ space: 8 }) {
            ForEach(v.buttons.slice(0, 3), (b: CardButton, i: number) => {
              this.pill(v, b, i === 0)
            }, (b: CardButton) => `${b.index}:${b.enabled}`)
          }
          .width('38%')
          .justifyContent(FlexAlign.Center)
          .height('100%')
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        Column({ space: 2 }) {
          ForEach(v.displays.slice(0, v.rows.length > 0 ? 1 : 2), (d: CardDisplay, i: number) => {
            if (d.kind === 'score') {
              this.scoreLine(v, d, i === 0)
            } else {
              this.textLine(d, i === 0 || v.displays[0].kind === 'score')
            }
          }, (d: CardDisplay) => d.key)
          ForEach(v.rows.slice(0, 2), (r: CardRow) => {
            CompactRow({ row: r, accent: v.accent })
          }, (r: CardRow) => r.key)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        Row({ space: 8 }) {
          ForEach(v.buttons.slice(0, 2), (b: CardButton, i: number) => {
            Row() {
              this.pill(v, b, i === 0)
            }
            .layoutWeight(1) // two buttons share the 2x2 width instead of pushing the second off the card
          }, (b: CardButton) => `${b.index}:${b.enabled}`)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  rowsLayout(v: CardView) {
    Column({ space: 4 }) {
      this.header(v, v.caption)
      Column({ space: 2 }) {
        ForEach(v.rows, (r: CardRow) => {
          if (r.kind === 'text') {
            Text(r.label)
              .fontSize(13)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
              .maxLines(2)
          } else if (r.kind === 'checklist') {
            // Several parts share the card: the first unticked items, then "+N more" (open the app for all).
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(openItems(r).slice(0, v.wide ? 2 : 1),
                (item: CardCheckItem) => {
                  CheckRow({ listId: r.id, item: item, wide: v.wide, accent: v.accent })
                }, (item: CardCheckItem) => `${r.id}-${item.index}-${item.checked}`)
            }
            .width('100%')
            Text(`${r.items.filter((i: CardCheckItem) => i.checked).length}/${r.items.length} done` +
              (openItems(r).length > (v.wide ? 2 : 1) ? ` · +${openItems(r).length - (v.wide ? 2 : 1)} more` : ''))
              .fontSize(11)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
          } else {
            CompactRow({ row: r, accent: v.accent })
          }
        }, (r: CardRow) => r.key)
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      this.note(v)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  messageLayout(v: CardView) {
    Column({ space: 8 }) {
      Stack() {
        this.icon(v.icon, 24, v.accent)
      }
      .width(BIG_BUTTON)
      .height(BIG_BUTTON)
      .borderRadius(BIG_BUTTON / 2)
      .backgroundColor(tint(v.accent))

      if (v.capsuleId.length > 0) {
        Text(v.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      Text(v.message)
        .fontSize(v.capsuleId.length > 0 ? 12 : 14)
        .fontColor($r('sys.color.font_secondary'))
        .textAlign(TextAlign.Center)
        .maxLines(v.capsuleId.length > 0 ? 2 : 3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => this.onTap()) // blank: choose a capsule; removed/app-only: open the app
  }

  /** The layout for one view. */
  @Builder
  content(v: CardView) {
    if (v.layout === 'counter' && v.rows.some((r: CardRow) => r.kind === 'counter')) {
      this.counterLayout(v, v.rows.filter((r: CardRow) => r.kind === 'counter')[0])
    } else if (v.layout === 'goal') {
      this.goalLayout(v)
    } else if (v.layout === 'timer' && v.rows.some((r: CardRow) => r.kind === 'timer')) {
      this.timerLayout(v, v.rows.filter((r: CardRow) => r.kind === 'timer')[0])
    } else if (v.layout === 'checklist' && v.rows.some((r: CardRow) => r.kind === 'checklist')) {
      this.checklistLayout(v, v.rows.filter((r: CardRow) => r.kind === 'checklist')[0])
    } else if (v.layout === 'logic') {
      this.logicLayout(v)
    } else if (v.layout === 'rows') {
      this.rowsLayout(v)
    } else {
      this.messageLayout(v)
    }
  }

  build() {
    Column() {
      // Builders get the view by value, and ArkUI does not redraw a builder when such a value changes
      // (BUG-13: taps were saved but the card kept showing the old count). Keying the content on the
      // view JSON rebuilds it from the new view on every update.
      ForEach([this.viewJson], (json: string) => {
        this.content(parseView(json))
      }, (json: string) => json)
    }
    .width('100%')
    .height('100%')
    .padding(PAD)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius($r('sys.float.ohos_id_corner_radius_card'))
    .clip(true)
  }
}

/**
 * The single-timer card: an emptying ring around the countdown (a TextTimer ticks it, so no
 * updateForm is needed every second), and a large start button when the capsule allows it.
 */
@Component
struct HeroTimer {
  @Prop row: CardRow;
  @Prop accent: string;
  @Prop wide: boolean;
  @State leftMs: number = 0;
  private controller: TextTimerController = new TextTimerController();
  private finishedSent: boolean = false;

  aboutToAppear(): void {
    this.leftMs = Math.max(this.row.endAt - Date.now(), 0);
  }

  private totalMs(): number {
    return Math.max(Math.round(this.row.minutes * 60) * 1000, 1);
  }

  private running(): boolean {
    return this.row.endAt > Date.now() && this.row.endAt - Date.now() <= MAX_TEXT_TIMER_MS;
  }

  /** Ring fill: full when idle, emptying while running, empty when done. */
  private fill(): number {
    if (this.row.endAt === 0) {
      return this.totalMs();
    }
    return Math.min(this.leftMs, this.totalMs());
  }

  @Builder
  time(size: number) {
    if (this.running()) {
      TextTimer({ isCountDown: true, count: this.row.endAt - Date.now(), controller: this.controller })
        .format(this.row.endAt - Date.now() >= 3600000 ? 'HH:mm:ss' : 'mm:ss')
        .fontSize(size)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .onAppear(() => this.controller.start())
        .onTimer(() => {
          this.leftMs = Math.max(this.row.endAt - Date.now(), 0);
          // At zero, ask the provider to redraw this timer as "Done".
          if (!this.finishedSent && Date.now() >= this.row.endAt) {
            this.finishedSent = true;
            postCardAction(this, { action: 'message', params: { op: 'refresh', id: this.row.id, index: -1 } });
          }
        })
    } else {
      Text(this.row.endAt > 0 ? 'Done' : minutesText(this.row.minutes))
        .fontSize(size)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.row.endAt > 0 ? this.accent : $r('sys.color.font_primary'))
        .maxLines(1)
    }
  }

  build() {
    Row({ space: 12 }) {
      Stack() {
        Progress({ value: this.fill(), total: this.totalMs(), type: ProgressType.Ring })
          .width(this.wide ? 96 : 84)
          .height(this.wide ? 96 : 84)
          .color(this.accent)
          .backgroundColor(tint(this.accent))
          .style({ strokeWidth: 8 })
        if (!this.wide) {
          this.time(18)
        } else {
          SymbolGlyph($r('sys.symbol.timer')).fontSize(28).fontColor([this.accent])
        }
      }

      Column({ space: 6 }) {
        if (this.wide) {
          Text(this.row.label)
            .fontSize(14)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          this.time(40)
        }
        if (this.row.canStart && !this.running()) {
          Stack() {
            SymbolGlyph($r('sys.symbol.play_fill')).fontSize(20).fontColor([$r('sys.color.font_on_primary')])
          }
          .width(BIG_BUTTON)
          .height(BIG_BUTTON)
          .borderRadius(BIG_BUTTON / 2)
          .backgroundColor(this.accent)
          .onClick(() => {
            postCardAction(this, { action: 'message', params: { op: 'start', id: this.row.id, index: -1 } });
          })
        }
      }
      .layoutWeight(1)
      .alignItems(this.wide ? HorizontalAlign.Start : HorizontalAlign.End)
      .justifyContent(FlexAlign.End)
      .height('100%')
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}

/** One timer or counter in a list: label, value and a 40vp control. */
@Component
struct CompactRow {
  @Prop row: CardRow;
  @Prop accent: string;
  private controller: TextTimerController = new TextTimerController();
  private finishedSent: boolean = false;

  private remainingMs(): number {
    return this.row.endAt - Date.now();
  }

  @Builder
  control(symbol: string, op: string) {
    Stack() {
      if (symbol === 'play') {
        SymbolGlyph($r('sys.symbol.play_fill')).fontSize(16).fontColor([$r('sys.color.font_on_primary')])
      } else {
        SymbolGlyph($r('sys.symbol.plus')).fontSize(18).fontColor([$r('sys.color.font_on_primary')])
      }
    }
    .width(BIG_BUTTON)
    .height(BIG_BUTTON)
    .borderRadius(BIG_BUTTON / 2)
    .backgroundColor(this.accent)
    .onClick(() => {
      postCardAction(this, { action: 'message', params: { op: op, id: this.row.id, index: -1 } });
    })
  }

  build() {
    Row({ space: 8 }) {
      Text(this.row.label)
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.row.kind === 'timer') {
        if (this.remainingMs() > 0 && this.remainingMs() <= MAX_TEXT_TIMER_MS) {
          TextTimer({ isCountDown: true, count: this.remainingMs(), controller: this.controller })
            .format(this.remainingMs() >= 3600000 ? 'HH:mm:ss' : 'mm:ss')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.accent)
            .onAppear(() => this.controller.start())
            .onTimer(() => {
              if (!this.finishedSent && Date.now() >= this.row.endAt) {
                this.finishedSent = true;
                postCardAction(this, { action: 'message', params: { op: 'refresh', id: this.row.id, index: -1 } });
              }
            })
        } else {
          Text(this.row.endAt > 0 ? 'Done' : minutesText(this.row.minutes))
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.row.endAt > 0 ? this.accent : $r('sys.color.font_primary'))
          if (this.row.canStart) {
            this.control('play', 'start')
          }
        }
      } else if (this.row.kind === 'checklist') {
        Text(`${this.row.items.filter((i: CardCheckItem) => i.checked).length}/${this.row.items.length}`)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
      } else {
        Text(`${this.row.value}`)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
        if (this.row.canIncrement) {
          this.control('plus', 'increment')
        }
      }
    }
    .width('100%')
    .height(BIG_BUTTON)
  }
}

/**
 * One checklist item with a tick circle. Its own component, so the tap handler reads this item's
 * own index (a closure inside the builder's ForEach picked up another item's index on the device).
 */
@Component
struct CheckRow {
  @Prop listId: string;
  @Prop item: CardCheckItem;
  @Prop wide: boolean;
  @Prop accent: string;

  build() {
    Row({ space: 8 }) {
      Stack() {
        if (this.item.checked) {
          SymbolGlyph($r('sys.symbol.checkmark')).fontSize(13).fontColor([$r('sys.color.font_on_primary')])
        }
      }
      .width(22)
      .height(22)
      .borderRadius(11)
      .border({ width: this.item.checked ? 0 : 2, color: $r('sys.color.font_tertiary') })
      .backgroundColor(this.item.checked ? this.accent : Color.Transparent)

      Text(this.item.text)
        .fontSize(14)
        .fontColor(this.item.checked ? $r('sys.color.font_tertiary') : $r('sys.color.font_primary'))
        .decoration({ type: this.item.checked ? TextDecorationType.LineThrough : TextDecorationType.None })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width(this.wide ? '50%' : '100%')
    .height(BIG_BUTTON)
    .onClick(() => {
      postCardAction(this, {
        action: 'message',
        params: { op: 'toggle', id: this.listId, index: this.item.index }
      });
    })
  }
}
