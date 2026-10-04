import { GateLog, LogEntry, LogKind } from '../gatekeeper/Gatekeeper';
import { Chip, IconTile } from '../components';
import { Flags } from '../theme/Flags';
import { Palette } from '../theme/Tokens';

function formatTime(ms: number): string {
  const d = new Date(ms);
  const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
  return `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
}

function kindColor(kind: LogKind): ResourceColor {
  switch (kind) {
    case 'allow':
      return $r('sys.color.confirm');
    case 'blocked':
      return $r('sys.color.warning');
    case 'deny':
      return $r('sys.color.alert');
    default:
      return $r('sys.color.font_secondary');
  }
}

function kindIcon(kind: LogKind): Resource {
  switch (kind) {
    case 'allow':
      return $r('sys.symbol.checkmark_circle');
    case 'blocked':
      return $r('sys.symbol.lock');
    case 'deny':
      return $r('sys.symbol.xmark');
    default:
      return $r('sys.symbol.trash');
  }
}

/** Redesign (NEW_LOG): allow blue, deny/blocked orange, undo grey. */
function kindFill(kind: LogKind): ResourceColor {
  if (kind === 'allow') {
    return Palette.tint;
  }
  return kind === 'undo' ? Palette.softButton : Palette.orangeTint;
}

function kindInk(kind: LogKind): ResourceColor {
  if (kind === 'allow') {
    return Palette.chipText;
  }
  return kind === 'undo' ? Palette.text3 : Palette.orangeText;
}

function kindLabel(kind: LogKind): string {
  switch (kind) {
    case 'allow':
      return 'Allowed';
    case 'blocked':
      return 'Blocked';
    case 'deny':
      return 'Denied';
    default:
      return 'Undone';
  }
}

/** Gatekeeper log, newest first. */
@ComponentV2
export struct LogView {
  /** Shown as a home tab (UI-2) instead of a pushed page. */
  @Param embedded: boolean = false;
  @Require @Param log: GateLog;

  @Builder
  content() {
    if (this.log.entries.length === 0) {
      Text('Nothing logged yet.')
        .fontSize(Flags.NEW_LOG ? 15 : $r('sys.float.Body_M'))
        .fontColor(Flags.NEW_LOG ? Palette.text2 : $r('sys.color.font_tertiary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 48 })
    } else {
      List({ space: 8 }) {
        ForEach(this.log.entries, (e: LogEntry) => {
          ListItem() {
            if (Flags.NEW_LOG) {
              this.newRow(e)
            } else {
              this.oldRow(e)
            }
          }
        }, (e: LogEntry, i: number) => `${e.time}-${i}-${e.detail}`)
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16, bottom: 16 })
      .scrollBar(BarState.Off)
      .contentEndOffset(this.embedded ? 120 : 0)
    }
  }

  /** Same entry, canvas look: tinted icon tile, kind chip, full detail (wraps), time and capsule. */
  @Builder
  newRow(e: LogEntry) {
    Row({ space: 12 }) {
      IconTile({ icon: kindIcon(e.kind), tileSize: 40, iconSize: 20, fill: kindFill(e.kind), color: kindInk(e.kind) })
      Column({ space: 6 }) {
        Chip({ text: kindLabel(e.kind), fill: kindFill(e.kind), color: kindInk(e.kind) })
        Text(e.detail)
          .fontSize(15)
          .fontWeight(500)
          .fontColor(Palette.text)
        Text(`${formatTime(e.time)} · ${e.capsuleId}`)
          .fontSize(13)
          .fontColor(Palette.text2)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .alignItems(VerticalAlign.Top)
    .width('100%')
    .padding(14)
    .borderRadius(18)
    .backgroundColor(Palette.surface)
  }

  @Builder
  oldRow(e: LogEntry) {
    Row({ space: 12 }) {
      SymbolGlyph(kindIcon(e.kind))
        .fontSize(20)
        .fontColor([kindColor(e.kind)])
      Column({ space: 2 }) {
        Text(e.detail)
          .fontSize($r('sys.float.Body_M'))
          .fontColor($r('sys.color.font_primary'))
        Text(`${formatTime(e.time)} · ${e.capsuleId}`)
          .fontSize($r('sys.float.Caption_M'))
          .fontColor($r('sys.color.font_tertiary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(14)
    .borderRadius(16)
    .backgroundColor($r('sys.color.comp_background_primary'))
  }

  build() {
    if (this.embedded) {
      // A tab of the home screen (UI-2): no title bar, a large title, room for the floating tab bar.
      Column({ space: 8 }) {
        Text('Activity')
          .fontSize(Flags.NEW_LOG ? 28 : 30)
          .fontWeight(Flags.NEW_LOG ? 800 : FontWeight.Bold)
          .fontColor(Flags.NEW_LOG ? Palette.text : $r('sys.color.font_primary'))
          .width('100%')
          .padding({ left: 16, right: 16, top: 12 })
        Column() {
          this.content()
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('100%')
    } else {
      NavDestination() {
        this.content()
      }
      .title('Gatekeeper log')
      .backgroundColor(Flags.NEW_LOG ? Palette.bg : $r('sys.color.background_secondary'))
    }
  }
}
