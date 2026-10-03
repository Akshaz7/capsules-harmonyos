import { GateLog, LogEntry, LogKind } from '../gatekeeper/Gatekeeper';

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
        .fontSize($r('sys.float.Body_M'))
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 48 })
    } else {
      List({ space: 8 }) {
        ForEach(this.log.entries, (e: LogEntry) => {
          ListItem() {
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
        }, (e: LogEntry, i: number) => `${e.time}-${i}-${e.detail}`)
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16, bottom: 16 })
      .scrollBar(BarState.Off)
    }
  }

  build() {
    if (this.embedded) {
      // A tab of the home screen (UI-2): no title bar, a large title, room for the floating tab bar.
      Column({ space: 8 }) {
        Text('Activity')
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
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
      .padding({ bottom: 96 })
      .backgroundColor($r('sys.color.background_secondary'))
    } else {
      NavDestination() {
        this.content()
      }
      .title('Gatekeeper log')
      .backgroundColor($r('sys.color.background_secondary'))
    }
  }
}
