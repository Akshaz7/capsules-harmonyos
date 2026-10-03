/**
 * Harmoniser widget card (2x2 and 2x4). Runs in the system's form renderer, so it imports
 * nothing and only uses widget-capable components. It draws the WidgetView JSON built by
 * core/WidgetModel.ets (field names must match) and sends taps back with postCardAction.
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
}

interface CardView {
  status: string;
  capsuleId: string;
  title: string;
  message: string;
  rows: CardRow[];
  wide: boolean;
}

const MAX_TEXT_TIMER_MS: number = 86399000;
const ACCENT: string = '#0A59F7';
const TEXT: string = '#E6000000';
const MUTED: string = '#99000000';

function parseView(raw: string): CardView {
  try {
    if (raw.length > 0) {
      return JSON.parse(raw) as CardView;
    }
  } catch (e) {
    // fall through to the placeholder
  }
  const empty: CardView = { status: 'empty', capsuleId: '', title: 'Harmoniser', message: '', rows: [], wide: false };
  return empty;
}

function minutesText(minutes: number): string {
  const total = Math.round(minutes * 60);
  const m = Math.floor(total / 60);
  const s = total % 60;
  return `${m}:${s < 10 ? '0' : ''}${s}`;
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

  private send(op: string, id: string, index: number): void {
    postCardAction(this, { action: 'message', params: { op: op, id: id, index: index } });
  }

  @Builder
  counterRow(r: CardRow) {
    Row({ space: 6 }) {
      Text(r.label).fontSize(12).fontColor(TEXT).layoutWeight(1).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(`${r.value}`).fontSize(16).fontWeight(FontWeight.Bold).fontColor(TEXT)
      if (r.canIncrement) {
        Button('+')
          .fontSize(14)
          .width(28)
          .height(24)
          .backgroundColor(ACCENT)
          .onClick(() => this.send('increment', r.id, -1))
      }
    }
    .width('100%')
    .height(28)
  }

  @Builder
  checklistRow(r: CardRow, wide: boolean) {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(r.items, (item: CardCheckItem) => {
        Row({ space: 2 }) {
          Checkbox({ name: `${r.id}-${item.index}` })
            .select(item.checked)
            .width(14)
            .height(14)
            .selectedColor(ACCENT)
            .onChange((value: boolean) => {
              if (value !== item.checked) {
                this.send('toggle', r.id, item.index);
              }
            })
          Text(item.text)
            .fontSize(11)
            .fontColor(item.checked ? MUTED : TEXT)
            .decoration({ type: item.checked ? TextDecorationType.LineThrough : TextDecorationType.None })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width(wide ? '50%' : '100%')
        .height(20)
      }, (item: CardCheckItem) => `${r.id}-${item.index}-${item.checked}`)
    }
    .width('100%')
  }

  build() {
    Column({ space: 4 }) {
      Row() {
        Text(parseView(this.viewJson).title)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text('Harmoniser').fontSize(9).fontColor(MUTED)
      }
      .width('100%')

      if (parseView(this.viewJson).message.length > 0) {
        Text(parseView(this.viewJson).message).fontSize(10).fontColor(MUTED).width('100%').maxLines(2)
      }

      ForEach(parseView(this.viewJson).rows, (r: CardRow) => {
        if (r.kind === 'text') {
          Text(r.label).fontSize(11).fontColor(TEXT).width('100%').maxLines(2)
        } else if (r.kind === 'timer') {
          TimerRow({ row: r })
        } else if (r.kind === 'counter') {
          this.counterRow(r)
        } else if (r.kind === 'checklist') {
          this.checklistRow(r, parseView(this.viewJson).wide)
        }
      }, (r: CardRow) => r.key)
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor(Color.White)
    .justifyContent(FlexAlign.Start)
    .clip(true)
    .onClick(() => this.openApp(parseView(this.viewJson).capsuleId))
  }
}

/** One timer: a live TextTimer countdown while running, otherwise its length and a start button. */
@Component
struct TimerRow {
  @Prop row: CardRow;
  private controller: TextTimerController = new TextTimerController();
  private finishedSent: boolean = false;

  private remainingMs(): number {
    return this.row.endAt - Date.now();
  }

  build() {
    Row({ space: 6 }) {
      Text(this.row.label).fontSize(12).fontColor(TEXT).layoutWeight(1).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.remainingMs() > 0 && this.remainingMs() <= MAX_TEXT_TIMER_MS) {
        TextTimer({ isCountDown: true, count: this.remainingMs(), controller: this.controller })
          .format(this.remainingMs() >= 3600000 ? 'HH:mm:ss' : 'mm:ss')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(ACCENT)
          .onAppear(() => this.controller.start())
          .onTimer(() => {
            // At zero, ask the provider to redraw this row as "Done".
            if (!this.finishedSent && Date.now() >= this.row.endAt) {
              this.finishedSent = true;
              postCardAction(this, { action: 'message', params: { op: 'refresh', id: this.row.id, index: -1 } });
            }
          })
      } else {
        Text(this.row.endAt > 0 ? 'Done' : minutesText(this.row.minutes))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.row.endAt > 0 ? ACCENT : TEXT)
        if (this.row.canStart) {
          Button('▶')
            .fontSize(11)
            .width(28)
            .height(24)
            .backgroundColor(ACCENT)
            .onClick(() => {
              postCardAction(this, { action: 'message', params: { op: 'start', id: this.row.id, index: -1 } });
            })
        }
      }
    }
    .width('100%')
    .height(28)
  }
}
