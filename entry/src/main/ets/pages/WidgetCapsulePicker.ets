import { CapsuleEntry, capsuleIcon } from './CapsuleEntry';

/** Opened from a blank home-screen widget: pick which capsule it shows. Only widget-suitable capsules are listed. */
@ComponentV2
export struct WidgetCapsulePicker {
  @Param entries: CapsuleEntry[] = [];
  @Event onPick: (capsuleId: string) => void = () => {
  };

  private suitable(): CapsuleEntry[] {
    return this.entries.filter((e: CapsuleEntry) => e.route.widget);
  }

  build() {
    NavDestination() {
      Column({ space: 12 }) {
        Text('Pick what this home screen widget shows.')
          .fontSize($r('sys.float.Body_M'))
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .padding({ left: 4, right: 4 })
        if (this.suitable().length === 0) {
          Text('None of your capsules fits a widget yet. Timers, counters and short checklists do.')
            .fontSize($r('sys.float.Body_L'))
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
            .padding(16)
            .borderRadius(20)
            .backgroundColor($r('sys.color.comp_background_primary'))
        } else {
          List({ space: 8 }) {
            ForEach(this.suitable(), (e: CapsuleEntry) => {
              ListItem() {
                Row({ space: 12 }) {
                  Stack() {
                    SymbolGlyph(capsuleIcon(e.capsule))
                      .fontSize(20)
                      .fontColor([$r('sys.color.icon_emphasize')])
                  }
                  .width(40)
                  .height(40)
                  .borderRadius(20)
                  .backgroundColor($r('sys.color.comp_background_tertiary'))
                  Column({ space: 2 }) {
                    Text(e.capsule.name)
                      .fontSize($r('sys.float.Body_L'))
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('sys.color.font_primary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(e.runtime.summary())
                      .fontSize($r('sys.float.Caption_M'))
                      .fontColor($r('sys.color.font_secondary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                }
                .width('100%')
                .padding(16)
                .borderRadius(20)
                .backgroundColor($r('sys.color.comp_background_primary'))
                .onClick(() => this.onPick(e.capsule.id))
              }
            }, (e: CapsuleEntry) => e.capsule.id)
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16, top: 8 })
    }
    .title('Choose a capsule')
    .backgroundColor($r('sys.color.background_secondary'))
  }
}
