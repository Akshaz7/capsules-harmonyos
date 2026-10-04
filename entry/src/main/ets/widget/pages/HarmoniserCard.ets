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
  /** s = 1x2, m = 2x2, w = 2x4, l = 4x4 (older views: from `wide`). */
  size?: string;
  summary?: string;
  /** Condensed cards: "Open for more" / "Open to edit values" beside the title (T4-19). */
  hint?: string;
}

function sizeOf(v: CardView): string {
  return v.size ?? (v.wide ? 'w' : 'm');
}

/** How many checklist items a card shows before "+N more": 8 on 4x4, 4 on 2x4, 2 on 2x2. */
function listMax(v: CardView): number {
  return sizeOf(v) === 'l' ? 8 : (v.wide ? 4 : 2);
}

/**
 * Items the checklist card shows. On 2x2 two 48vp rows fill the card, so when "+N more" is needed too it shows
 * one row (the line no longer overlaps the second row's tick, T4-28/29).
 */
function shownCount(v: CardView, open: number): number {
  const max = listMax(v);
  return open > max && sizeOf(v) === 'm' ? max - 1 : max;
}

/** The main value's font size: ~40fp on 2x2, ~56fp on 2x4, ~96fp on 4x4 (T4-24). */
function heroSize(v: CardView): number {
  const size = sizeOf(v);
  return size === 'l' ? 96 : (size === 'w' ? 56 : 40);
}

/** A value inside a ring: smaller than heroSize so it fits the ring. */
function ringValueSize(v: CardView): number {
  const size = sizeOf(v);
  return size === 'l' ? 56 : (size === 'w' ? 28 : 22);
}

/** Buttons in the bottom row: 2 on 2x2, 3 on 2x4 and 4x4. */
function maxButtons(v: CardView): number {
  return sizeOf(v) === 'm' ? 2 : 3;
}

/**
 * Mirrors Flags.NEW_POLISH (theme/Flags.ets): this page runs in the form renderer and imports nothing, so the
 * polish switch is repeated here. false = the pre-polish card.
 */
const NEW_POLISH: boolean = true;

/** Polish: 2x2 cards put the header's trailing text (hint, "6/7 done") under the title, not beside it. */
function subline(v: CardView): boolean {
  return NEW_POLISH && sizeOf(v) === 'm';
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
    } else if (name === 'water') {
      SymbolGlyph($r('sys.symbol.drop')).fontSize(size).fontColor([color])
    } else if (name === 'walk') {
      SymbolGlyph($r('sys.symbol.figure_walk')).fontSize(size).fontColor([color])
    } else if (name === 'trophy') {
      SymbolGlyph($r('sys.symbol.medal')).fontSize(size).fontColor([color])
    } else if (name === 'cooking') {
      SymbolGlyph($r('sys.symbol.cooking')).fontSize(size).fontColor([color])
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
    if (subline(v)) {
      this.stackedHeader(v, trailing.length > 0 ? trailing : (v.hint ?? ''))
    } else {
      this.inlineHeader(v, trailing)
    }
  }

  /** 2x2 (polish): title on one line, the trailing text on its own line under it, so neither cuts the other. */
  @Builder
  stackedHeader(v: CardView, trailing: string) {
    Row({ space: 8 }) {
      Stack() {
        this.icon(v.icon, 16, v.accent)
      }
      .width(28)
      .height(28)
      .borderRadius(14)
      .backgroundColor(tint(v.accent))

      Column() {
        Text(v.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (trailing.length > 0) {
          Text(trailing)
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(v.accent)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      // The widget's own colour (colorTag, T4-12): matches its dot in the app's widget list.
      Circle({ width: 8, height: 8 }).fill(v.accent)
    }
    .width('100%')
    .constraintSize({ minHeight: 28 })
    .responseRegion({ x: 0, y: -10, width: '100%', height: BIG_BUTTON })
    .onClick(() => this.onTap())
  }

  @Builder
  inlineHeader(v: CardView, trailing: string) {
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
      if (trailing.length > 0 || (v.hint ?? '').length > 0) {
        if (NEW_POLISH) {
          // Capped and ellipsized, so it can never push the title out.
          Text(trailing.length > 0 ? trailing : (v.hint ?? ''))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(v.accent)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '45%' })
        } else {
          Text(trailing.length > 0 ? trailing : (v.hint ?? ''))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(v.accent)
            .maxLines(1)
        }
      }
      // The widget's own colour (colorTag, T4-12): matches its dot in the app's widget list.
      Circle({ width: 8, height: 8 }).fill(v.accent)
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

  /** The value (scaled to the card size) centred with its caption under it. */
  @Builder
  hero(v: CardView, value: string, caption: string) {
    if (NEW_POLISH && sizeOf(v) === 'm') {
      this.heroRow(v, value, caption)
    } else {
      this.heroColumn(v, value, caption)
    }
  }

  /**
   * 2x2 (polish): value and caption side by side, so with a 48vp button below the caption is never drawn under
   * the button (the stacked hero was taller than the space left on a 2x2).
   */
  @Builder
  heroRow(v: CardView, value: string, caption: string) {
    Row({ space: 8 }) {
      Text(value)
        .fontSize(34)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .fontFeature('"tnum" on')
        .maxLines(1)
        .minFontSize(18)
        .maxFontSize(34)
        .constraintSize({ maxWidth: caption.length > 0 ? '60%' : '100%' })
      if (caption.length > 0) {
        Text(caption)
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(caption.length > 0 ? FlexAlign.Start : FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .clip(true)
  }

  @Builder
  heroColumn(v: CardView, value: string, caption: string) {
    Column({ space: 2 }) {
      Text(value)
        .fontSize(heroSize(v))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .fontFeature('"tnum" on')
        .maxLines(1)
        .minFontSize(20)
        .maxFontSize(heroSize(v))
        .textAlign(TextAlign.Center)
      if (caption.length > 0) {
        Text(caption)
          .fontSize(sizeOf(v) === 'l' ? 16 : 12)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(sizeOf(v) === 'l' ? 2 : 1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .clip(NEW_POLISH)
  }

  /** The capsule's buttons in one full-width row along the bottom: the first filled, the others tinted. */
  @Builder
  buttonRow(v: CardView) {
    if (v.buttons.length > 0) {
      Row({ space: 8 }) {
        ForEach(v.buttons.slice(0, maxButtons(v)), (b: CardButton, i: number) => {
          Row() {
            this.pill(v, b, i === 0)
          }
          .layoutWeight(1)
        }, (b: CardButton) => `${b.index}:${b.enabled}`)
      }
      .width('100%')
      .height(BIG_BUTTON)
      .flexShrink(0)
    }
  }

  @Builder
  counterLayout(v: CardView, r: CardRow) {
    Column({ space: subline(v) ? 4 : 6 }) {
      this.header(v, '')
      this.hero(v, `${r.value}`, v.caption.length > 0 ? v.caption : r.label)
      if (r.canIncrement) {
        Row() {
          SymbolGlyph($r('sys.symbol.plus')).fontSize(20).fontColor([$r('sys.color.font_on_primary')])
        }
        .width('100%')
        .height(BIG_BUTTON)
        .borderRadius(BIG_BUTTON / 2)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(v.accent)
        .flexShrink(0)
        .onClick(() => this.send('increment', r.id, -1))
      }
      this.note(v)
    }
    .width('100%')
    .height('100%')
  }

  /** A ring that fills the height it is given, with the value and "/ goal" inside. */
  @Builder
  goalRing(v: CardView) {
    Stack() {
      Progress({ value: Math.min(v.value, v.goal), total: v.goal, type: ProgressType.Ring })
        .width('100%')
        .height('100%')
        .color(v.accent)
        .backgroundColor(tint(v.accent))
        .style({ strokeWidth: sizeOf(v) === 'l' ? 14 : 8 })
      Column() {
        Text(numberText(v.value))
          .fontSize(ringValueSize(v))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .fontFeature('"tnum" on')
          .maxLines(1)
          .minFontSize(12)
          .maxFontSize(ringValueSize(v))
        Text(`/ ${numberText(v.goal)}`)
          .fontSize(sizeOf(v) === 'l' ? 18 : 11)
          .fontColor($r('sys.color.font_secondary'))
      }
      .width('70%')
    }
    .height('100%')
    .aspectRatio(1)
  }

  @Builder
  goalLayout(v: CardView) {
    Column({ space: 6 }) {
      this.header(v, v.value >= v.goal ? 'Done' : '')
      if (sizeOf(v) === 'm') {
        // 2x2: the ring fills the height, the main button beside it; the caption under both.
        Row({ space: 12 }) {
          this.goalRing(v)
          Blank()
          if (v.buttons.length > 0) {
            Stack() {
              this.roundButton(v, 'plus', BIG_BUTTON + 8, v.buttons[0].enabled)
            }
            .onClick(() => this.press(v, v.buttons[0]))
          }
        }
        .width('100%')
        .layoutWeight(1)
        if (v.caption.length > 0) {
          Text(v.caption)
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      } else if (sizeOf(v) === 'w') {
        // 2x4: ring left, caption right, buttons along the bottom.
        Row({ space: 16 }) {
          this.goalRing(v)
          Text(v.caption)
            .fontSize(16)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
        .layoutWeight(1)
        this.buttonRow(v)
      } else {
        // 4x4: a big centred ring, the caption under it, buttons along the bottom.
        Column() {
          this.goalRing(v)
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
        if (v.caption.length > 0) {
          Text(v.caption)
            .fontSize(16)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Center)
            .width('100%')
        }
        this.buttonRow(v)
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
      HeroTimer({ row: r, accent: v.accent, wide: v.wide, cardSize: sizeOf(v) })
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
          ForEach(openItems(r).slice(0, shownCount(v, openItems(r).length)), (item: CardCheckItem) => {
            CheckRow({ listId: r.id, item: item, wide: v.wide, accent: v.accent })
          }, (item: CardCheckItem) => `${r.id}-${item.index}-${item.checked}-${item.text}`)
        }
        .width('100%')
        .layoutWeight(1)
        .clip(true)
        if (openItems(r).length > shownCount(v, openItems(r).length)) {
          Text(`+${openItems(r).length - shownCount(v, openItems(r).length)} more`)
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
          .fontSize(big ? (sizeOf(v) === 'l' ? 72 : (sizeOf(v) === 'w' ? 44 : 34)) : 24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text('–').fontSize(big ? (sizeOf(v) === 'l' ? 40 : 22) : 16).fontColor($r('sys.color.font_tertiary'))
        Text(d.right)
          .fontSize(big ? (sizeOf(v) === 'l' ? 72 : (sizeOf(v) === 'w' ? 44 : 34)) : 24)
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
      .fontColor(!b.enabled && NEW_POLISH ? $r('sys.color.font_secondary') :
        (fill ? $r('sys.color.font_on_primary') : v.accent))
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .textAlign(TextAlign.Center)
      .padding({ left: 12, right: 12 })
      .height(BIG_BUTTON)
      .width('100%')
      .constraintSize({ minWidth: 64 })
      .borderRadius(BIG_BUTTON / 2)
      .backgroundColor(fill && (b.enabled || !NEW_POLISH) ? v.accent : tint(v.accent))
      .opacity(b.enabled || NEW_POLISH ? 1 : 0.4)
      .onClick(() => this.press(v, b))
  }

  /** The first display line, as large as the card allows: a number, a score or a short line. */
  @Builder
  leadLine(v: CardView, d: CardDisplay) {
    if (d.kind === 'number') {
      this.hero(v, d.left, d.label)
    } else if (d.kind === 'score') {
      Column() {
        this.scoreLine(v, d, true)
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      Column() {
        Text(d.text)
          .fontSize(sizeOf(v) === 'l' ? 36 : (sizeOf(v) === 'w' ? 28 : 22))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(2)
          .minFontSize(14)
          .maxFontSize(sizeOf(v) === 'l' ? 36 : (sizeOf(v) === 'w' ? 28 : 22))
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .clip(NEW_POLISH)
    }
  }

  /**
   * v1 cards: the first display line big and centred (it fills the space between header and buttons), then
   * the other lines and any timers, then the buttons in one row along the bottom.
   */
  @Builder
  logicLayout(v: CardView) {
    Column({ space: subline(v) ? 4 : 6 }) {
      this.header(v, '')
      if (v.displays.length > 0) {
        this.leadLine(v, v.displays[0])
      } else {
        Blank().layoutWeight(1)
      }
      ForEach(v.displays.slice(1, sizeOf(v) === 'l' ? 3 : (v.rows.length > 0 ? 1 : 2)), (d: CardDisplay) => {
        this.textLine(d, false)
      }, (d: CardDisplay) => d.key)
      ForEach(v.rows.slice(0, sizeOf(v) === 'm' ? 1 : 2), (r: CardRow) => {
        CompactRow({ row: r, accent: v.accent })
      }, (r: CardRow) => r.key)
      this.buttonRow(v)
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
              ForEach(openItems(r).slice(0, listMax(v) / 2),
                (item: CardCheckItem) => {
                  CheckRow({ listId: r.id, item: item, wide: v.wide, accent: v.accent })
                }, (item: CardCheckItem) => `${r.id}-${item.index}-${item.checked}`)
            }
            .width('100%')
            Text(`${r.items.filter((i: CardCheckItem) => i.checked).length}/${r.items.length} done` +
              (openItems(r).length > listMax(v) / 2 ? ` · +${openItems(r).length - listMax(v) / 2} more` : ''))
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

  /** 1x2: icon, title and one summary line; the whole card opens the app (or the picker when blank). */
  @Builder
  compactLayout(v: CardView) {
    Row({ space: 10 }) {
      Stack() {
        this.icon(v.icon, 18, v.accent)
      }
      .width(36)
      .height(36)
      .borderRadius(18)
      .backgroundColor(tint(v.accent))

      Column({ space: 2 }) {
        Text(v.capsuleId.length > 0 ? v.title : (v.message.length > 0 ? v.message : v.title))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (v.capsuleId.length > 0) {
          Text(v.summary ?? v.caption)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(v.accent)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .onClick(() => this.onTap())
  }

  /** The layout for one view. */
  @Builder
  content(v: CardView) {
    if (sizeOf(v) === 's') {
      this.compactLayout(v)
    } else if (v.layout === 'counter' && v.rows.some((r: CardRow) => r.kind === 'counter')) {
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
    .padding(sizeOf(parseView(this.viewJson)) === 's' ? 12 : PAD)
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
  /** m = 2x2, w = 2x4, l = 4x4. */
  @Prop cardSize: string = 'm';
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

  /** The time inside the ring: ~22fp on 2x2, 28 on 2x4, 56 on 4x4. */
  private timeSize(): number {
    return this.cardSize === 'l' ? 56 : (this.cardSize === 'w' ? 28 : 22);
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

  /** The ring fills the height it is given; the time sits inside it. */
  @Builder
  ring() {
    Stack() {
      Progress({ value: this.fill(), total: this.totalMs(), type: ProgressType.Ring })
        .width('100%')
        .height('100%')
        .color(this.accent)
        .backgroundColor(tint(this.accent))
        .style({ strokeWidth: this.cardSize === 'l' ? 14 : 8 })
      this.time(this.timeSize())
    }
    .height('100%')
    .aspectRatio(1)
  }

  @Builder
  startButton(full: boolean) {
    if (this.row.canStart && !this.running()) {
      Row() {
        SymbolGlyph($r('sys.symbol.play_fill')).fontSize(20).fontColor([$r('sys.color.font_on_primary')])
      }
      .width(full ? '100%' : BIG_BUTTON)
      .height(BIG_BUTTON)
      .borderRadius(BIG_BUTTON / 2)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.accent)
      .onClick(() => {
        postCardAction(this, { action: 'message', params: { op: 'start', id: this.row.id, index: -1 } });
      })
    }
  }

  build() {
    if (this.cardSize === 'l') {
      // 4x4: a big centred ring, the label under it, a full-width start button along the bottom.
      Column({ space: 8 }) {
        Column() {
          this.ring()
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
        Text(this.row.label)
          .fontSize(16)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        this.startButton(true)
      }
      .width('100%')
    } else {
      // 2x2 / 2x4: the ring fills the height on the left; label and start button on the right.
      Row({ space: 12 }) {
        this.ring()
        Column({ space: 6 }) {
          if (this.wide) {
            Text(this.row.label)
              .fontSize(16)
              .fontColor($r('sys.color.font_secondary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          this.startButton(this.wide)
        }
        .layoutWeight(1)
        .alignItems(this.wide ? HorizontalAlign.Start : HorizontalAlign.End)
        .justifyContent(this.wide ? FlexAlign.Center : FlexAlign.End)
        .height('100%')
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
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
        .maxLines(NEW_POLISH ? 2 : 1)
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
