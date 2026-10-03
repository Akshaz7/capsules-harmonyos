import { GateLog, LogEntry } from '../gatekeeper/Gatekeeper';

function formatTime(ms: number): string {
  const d = new Date(ms);
  const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
  return `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
}

/** Gatekeeper log, newest first. */
@ComponentV2
export struct LogView {
  @Require @Param log: GateLog;

  build() {
    NavDestination() {
      List({ space: 8 }) {
        ForEach(this.log.entries, (e: LogEntry) => {
          ListItem() {
            Column({ space: 2 }) {
              Text(`${formatTime(e.time)}  ${e.kind.toUpperCase()}  ${e.capsuleId}`)
                .fontSize(12)
                .fontColor(Color.Gray)
              Text(e.detail).fontSize(15)
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
          }
        }, (e: LogEntry, i: number) => `${e.time}-${i}-${e.detail}`)
      }
      .width('100%')
      .height('100%')
      .padding(16)
    }
    .title('Gatekeeper log')
  }
}
