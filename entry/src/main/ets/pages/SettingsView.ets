import { AiMode, AppSettings } from './AppSettings';
import { LIMITS_TEXT } from './CreateText';
import { IconTile } from '../components';
import { Flags } from '../theme/Flags';
import { Palette } from '../theme/Tokens';

// Redesign (NEW_SETTINGS): canvas tokens when on, the old system styling when off. Same rows, same handlers.
const NEW_LOOK: boolean = Flags.NEW_SETTINGS;
const TITLE_SIZE: number | Resource = NEW_LOOK ? 16 : $r('sys.float.Body_L');
const TITLE_COLOR: ResourceColor = NEW_LOOK ? Palette.text : $r('sys.color.font_primary');
const CAPTION_SIZE: number | Resource = NEW_LOOK ? 13 : $r('sys.float.Caption_M');
const CAPTION_COLOR: ResourceColor = NEW_LOOK ? Palette.text2 : $r('sys.color.font_secondary');
const NOTE_COLOR: ResourceColor = NEW_LOOK ? Palette.text2 : $r('sys.color.font_tertiary');
const HEADER_SIZE: number | Resource = NEW_LOOK ? 15 : $r('sys.float.Subtitle_S');
const HEADER_COLOR: ResourceColor = NEW_LOOK ? Palette.text : $r('sys.color.font_secondary');
const HEADER_WEIGHT: number = NEW_LOOK ? 700 : 400;
const CARD_COLOR: ResourceColor = NEW_LOOK ? Palette.surface : $r('sys.color.comp_background_primary');
const CARD_RADIUS: number = NEW_LOOK ? 22 : 20;
const DIVIDER_COLOR: ResourceColor = NEW_LOOK ? Palette.line2 : $r('sys.color.comp_divider');
const ACCENT: ResourceColor = NEW_LOOK ? Palette.blue : $r('sys.color.brand');

/** Settings page (NavDestination). */
@ComponentV2
export struct SettingsView {
  /** Shown as a home tab (UI-2) instead of a pushed page. */
  @Param embedded: boolean = false;
  @Require @Param settings: AppSettings;
  @Param cloudStatus: string = '';
  /** Second line of the Smart option: which cloud provider Smart mode would use. */
  @Param smartDetail: string = 'On-device + Mistral EU when needed';
  /** Bumped when the user changes the motion scope, so the page can start or stop the sensor. */
  @Event onMotionScopeChange: () => void = () => {
  };

  @Builder
  rowIcon(icon: Resource) {
    if (NEW_LOOK) {
      IconTile({ icon: icon, tileSize: 42, iconSize: 22 })
    } else {
      Stack() {
        SymbolGlyph(icon)
          .fontSize(20)
          .fontColor([$r('sys.color.icon_emphasize')])
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor($r('sys.color.comp_background_tertiary'))
    }
  }

  @Builder
  motionRow(scope: string, title: string, detail: string) {
    Row({ space: 12 }) {
      this.rowIcon($r('sys.symbol.figure_walk'))
      Column({ space: 2 }) {
        Text(title)
          .fontSize(TITLE_SIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor(TITLE_COLOR)
        Text(detail)
          .fontSize(CAPTION_SIZE)
          .fontColor(CAPTION_COLOR)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Radio({ value: scope, group: 'motionScope' })
        .checked(this.settings.motionScope === scope)
        .radioStyle({ checkedBackgroundColor: ACCENT })
        .onChange((isChecked: boolean) => {
          if (isChecked) {
            this.settings.setMotionScope(scope === 'app' ? 'app' : 'capsule');
            this.onMotionScopeChange();
          }
        })
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .onClick(() => {
      this.settings.setMotionScope(scope === 'app' ? 'app' : 'capsule');
      this.onMotionScopeChange();
    })
  }

  @Builder
  modeRow(mode: AiMode, icon: Resource, title: string, detail: string) {
    Row({ space: 12 }) {
      this.rowIcon(icon)
      Column({ space: 2 }) {
        Text(title)
          .fontSize(TITLE_SIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor(TITLE_COLOR)
        Text(detail)
          .fontSize(CAPTION_SIZE)
          .fontColor(CAPTION_COLOR)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Radio({ value: mode, group: 'aiMode' })
        .checked(this.settings.aiMode === mode)
        .radioStyle({ checkedBackgroundColor: ACCENT })
        .onChange((isChecked: boolean) => {
          if (isChecked) {
            this.settings.setAiMode(mode);
          }
        })
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .onClick(() => this.settings.setAiMode(mode))
  }

  @Builder
  content() {
    Column({ space: 8 }) {
      Text('AI mode')
        .fontSize(HEADER_SIZE)
        .fontWeight(HEADER_WEIGHT)
        .fontColor(HEADER_COLOR)
        .width('100%')
        .padding({ left: 4, right: 4, top: 4 })
      Column() {
        this.modeRow('smart', $r('sys.symbol.wand_and_stars'), 'Smart', this.smartDetail)
        Divider()
          .color(DIVIDER_COLOR)
          .margin({ left: NEW_LOOK ? 54 : 52 })
        this.modeRow('on-device', $r('sys.symbol.lock'), 'On-device only',
          'Requests never leave the device')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 4 })
      .borderRadius(CARD_RADIUS)
      .backgroundColor(CARD_COLOR)

      Text(this.settings.aiMode === 'smart' ?
        `Only your request text is sent, and only when the device can't build it. ${this.cloudStatus}` :
        'Capsules are made by rules and the on-device model only.')
        .fontSize(CAPTION_SIZE)
        .fontColor(NOTE_COLOR)
        .width('100%')
        .padding({ left: 4, right: 4 })
      Text(LIMITS_TEXT)
        .fontSize(CAPTION_SIZE)
        .fontColor(CAPTION_COLOR)
        .width('100%')
        .padding({ left: 4, right: 4 })

      Text('Motion')
        .fontSize(HEADER_SIZE)
        .fontWeight(HEADER_WEIGHT)
        .fontColor(HEADER_COLOR)
        .width('100%')
        .padding({ left: 4, right: 4, top: 16 })
      Column() {
        this.motionRow('capsule', 'While a capsule is open',
          'Only the capsule on screen reacts to shakes')
        Divider()
          .color(DIVIDER_COLOR)
          .margin({ left: NEW_LOOK ? 54 : 52 })
        this.motionRow('app', 'Anywhere in Harmoniser',
          'Every capsule you allowed reacts while the app is in front')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 4 })
      .borderRadius(CARD_RADIUS)
      .backgroundColor(CARD_COLOR)
      Text('Harmoniser never records motion, and only listens while the app is in front.')
        .fontSize(CAPTION_SIZE)
        .fontColor(NOTE_COLOR)
        .width('100%')
        .padding({ left: 4, right: 4 })

      Text('Advanced')
        .fontSize(HEADER_SIZE)
        .fontWeight(HEADER_WEIGHT)
        .fontColor(HEADER_COLOR)
        .width('100%')
        .padding({ left: 4, right: 4, top: 16 })
      Row({ space: 12 }) {
        Column({ space: 2 }) {
          Text('Allow non-EU providers')
            .fontSize(TITLE_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(TITLE_COLOR)
          Text('Let Smart mode use cloud AI providers outside the EU')
            .fontSize(CAPTION_SIZE)
            .fontColor(CAPTION_COLOR)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.settings.allowNonEu })
          .selectedColor(ACCENT)
          .enabled(this.settings.aiMode === 'smart')
          .onChange((isOn: boolean) => {
            this.settings.setAllowNonEu(isOn);
          })
      }
      .width('100%')
      .padding(16)
      .borderRadius(CARD_RADIUS)
      .backgroundColor(CARD_COLOR)
      .opacity(this.settings.aiMode === 'smart' ? 1 : 0.5)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8 })
  }

  build() {
    if (this.embedded) {
      // A tab of the home screen (UI-2): no title bar, a large title, room for the floating tab bar.
      Column({ space: 8 }) {
        Text('Settings')
          .fontSize(NEW_LOOK ? 28 : 30)
          .fontWeight(NEW_LOOK ? 800 : FontWeight.Bold)
          .fontColor(TITLE_COLOR)
          .width('100%')
          .padding({ left: 16, right: 16, top: 12 })
        if (NEW_LOOK) {
          // Scrolls so the last card clears the floating tab bar at large font sizes.
          Scroll() {
            Column() {
              this.content()
            }
            .padding({ bottom: 120 })
          }
          .layoutWeight(1)
          .width('100%')
          .align(Alignment.Top)
          .scrollBar(BarState.Off)
        } else {
          Column() {
            this.content()
          }
          .layoutWeight(1)
          .width('100%')
        }
      }
      .width('100%')
      .height('100%')
    } else {
      NavDestination() {
        this.content()
      }
      .title('Settings')
      .backgroundColor(NEW_LOOK ? Palette.bg : $r('sys.color.background_secondary'))
    }
  }
}
