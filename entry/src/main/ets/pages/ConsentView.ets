import { Capsule, Permission } from '../core';
import { Flags } from '../theme/Flags';
import { Palette, Radius } from '../theme/Tokens';
import { GhostButton, IconTile, OriginChip, OriginKind, PrimaryButton, SecondaryButton, SegmentedControl
} from '../components';
import { capsuleIcon } from './CapsuleEntry';

@ObservedV2
class PermissionChoice {
  permission: Permission;
  @Trace allowed: boolean = false;

  constructor(permission: Permission) {
    this.permission = permission;
  }
}

function permissionTitle(p: Permission): string {
  switch (p) {
    case 'reminders':
      return 'Reminders';
    case 'notifications':
      return 'Notifications';
    case 'vibration':
      return 'Vibration';
    case 'motion':
      return 'Motion sensor';
    case 'location':
      return 'Location';
    case 'battery':
      return 'Battery';
    case 'weather':
      return 'Weather';
    case 'widget':
      return 'Home screen widget';
    default:
      return p;
  }
}

function permissionReason(p: Permission): string {
  switch (p) {
    case 'reminders':
      return 'Save timers to your calendar and alert you when they finish';
    case 'notifications':
      return 'Show notifications from this capsule';
    case 'vibration':
      return 'Vibrate the phone for alerts';
    case 'motion':
      return 'React to shaking the phone while the capsule is open. It does not count steps or reps';
    case 'location':
      return 'Use where you are';
    case 'battery':
      return 'Read the battery level and charging state while the capsule is open';
    case 'weather':
      return 'Send the chosen city\'s coordinates to Open-Meteo (open-meteo.com) to show its weather';
    case 'widget':
      return 'Show this capsule on your home screen';
    default:
      return '';
  }
}

function permissionIcon(p: Permission): Resource {
  switch (p) {
    case 'reminders':
      return $r('sys.symbol.alarm');
    case 'notifications':
      return $r('sys.symbol.bell');
    case 'vibration':
      return $r('sys.symbol.a_4d_vibration');
    case 'motion':
      return $r('sys.symbol.figure_walk');
    case 'location':
      return $r('sys.symbol.pin');
    case 'battery':
      return $r('sys.symbol.battery_100percent');
    case 'weather':
      return $r('sys.symbol.cloud');
    default:
      return $r('sys.symbol.square_grid_2x2');
  }
}

/** Gatekeeper sheet body: one allow/deny toggle per declared permission. Everything starts denied. */
@ComponentV2
export struct ConsentView {
  @Require @Param capsule: Capsule;
  @Param origin: string = '';
  /** T3-17: "Built from a template" / "Built from a community capsule"; '' when not from one. */
  @Param builtFrom: string = '';
  /** Show "Not quite right? Build fresh" (only when fresh generation is possible). */
  @Param canBuildFresh: boolean = false;
  @Event onBuildFresh: () => void = () => {};
  @Event onDecide: (allowed: Permission[]) => void = () => {};
  @Event onCancel: () => void = () => {};
  /** Redesign: which origin chip icon to show next to `origin`. */
  @Param originKind: OriginKind = 'phone';
  @Local choices: PermissionChoice[] = [];

  /** Run capsule: the permissions switched to Allow. Same for both looks. */
  private decide(): void {
    const allowed: Permission[] = this.choices
      .filter((c: PermissionChoice) => c.allowed)
      .map((c: PermissionChoice) => c.permission);
    this.onDecide(allowed);
  }

  aboutToAppear(): void {
    this.choices = this.capsule.permissions.map((p: Permission) => new PermissionChoice(p));
  }

  /** Redesign (NEW_CONSENT): same choices and buttons, restyled. */
  @Builder
  newLook() {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        IconTile({ icon: capsuleIcon(this.capsule), tileSize: 42, iconSize: 22 })
        Column({ space: 4 }) {
          Text(this.capsule.name)
            .fontSize(20)
            .fontWeight(800)
            .fontColor(Palette.text)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          OriginChip({ text: this.origin, kind: this.originKind })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      Text(this.capsule.permissions.length > 0 ? 'Choose what this capsule may use' :
        'This capsule needs no permissions')
        .fontSize(14)
        .fontWeight(600)
        .fontColor(Palette.text2)
        .width('100%')
      ForEach(this.choices, (choice: PermissionChoice) => {
        Column({ space: 10 }) {
          Row({ space: 12 }) {
            IconTile({ icon: permissionIcon(choice.permission), tileSize: 36, iconSize: 20 })
            Column({ space: 2 }) {
              Text(permissionTitle(choice.permission))
                .fontSize(16)
                .fontWeight(700)
                .fontColor(Palette.text)
              Text(permissionReason(choice.permission))
                .fontSize(13)
                .fontColor(Palette.text2)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
          SegmentedControl({
            items: ['Allow', 'Deny'],
            selected: choice.allowed ? 0 : 1,
            strong: choice.allowed,
            onSelect: (i: number) => {
              choice.allowed = i === 0;
            }
          })
        }
        .width('100%')
        .padding(14)
        .borderRadius(Radius.card)
        .backgroundColor(Palette.card)
      }, (choice: PermissionChoice) => choice.permission)
      if (this.choices.length > 0) {
        Text('Anything you deny is blocked and recorded in the log.')
          .fontSize(13)
          .fontColor(Palette.text2)
          .width('100%')
      }
      if (this.builtFrom.length > 0) {
        Text(this.builtFrom)
          .fontSize(13)
          .fontWeight(500)
          .fontColor(Palette.text2)
          .width('100%')
          .textAlign(TextAlign.Center)
      }
      PrimaryButton({ label: 'Run capsule', onTap: () => this.decide() })
      SecondaryButton({ label: 'Cancel', onTap: () => this.onCancel() })
      if (this.builtFrom.length > 0 && this.canBuildFresh) {
        GhostButton({ label: 'Not quite right? Build fresh', onTap: () => this.onBuildFresh() })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 24 })
  }

  build() {
    if (Flags.NEW_CONSENT) {
      this.newLook()
    } else {
      this.oldLook()
    }
  }

  @Builder
  oldLook() {
    Column({ space: 16 }) {
      Column({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.lock'))
          .fontSize(32)
          .fontColor([$r('sys.color.icon_emphasize')])
          .margin({ bottom: 4 })
        Text(this.capsule.name)
          .fontSize($r('sys.float.Title_M'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
        Text(this.capsule.permissions.length > 0 ? 'Choose what this capsule may use' :
          'This capsule needs no permissions')
          .fontSize($r('sys.float.Body_M'))
          .fontColor($r('sys.color.font_secondary'))
        if (this.origin.length > 0) {
          Text(this.origin)
            .fontSize($r('sys.float.Caption_M'))
            .fontColor($r('sys.color.font_tertiary'))
        }
        if (this.builtFrom.length > 0) {
          Row({ space: 4 }) {
            Text(this.builtFrom)
              .fontSize($r('sys.float.Caption_M'))
              .fontColor($r('sys.color.font_secondary'))
            if (this.canBuildFresh) {
              Text('· Not quite right? Build fresh')
                .fontSize($r('sys.float.Caption_M'))
                .fontColor($r('sys.color.brand'))
                .fontWeight(FontWeight.Medium)
                .onClick(() => this.onBuildFresh())
            }
          }
        }
      }
      .width('100%')

      if (this.choices.length > 0) {
        Column() {
          ForEach(this.choices, (choice: PermissionChoice, i: number) => {
            Row({ space: 12 }) {
              Stack() {
                SymbolGlyph(permissionIcon(choice.permission))
                  .fontSize(20)
                  .fontColor([$r('sys.color.icon_emphasize')])
              }
              .width(40)
              .height(40)
              .borderRadius(20)
              .backgroundColor($r('sys.color.comp_background_tertiary'))
              Column({ space: 2 }) {
                Text(permissionTitle(choice.permission))
                  .fontSize($r('sys.float.Body_L'))
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('sys.color.font_primary'))
                Text(permissionReason(choice.permission))
                  .fontSize($r('sys.float.Caption_M'))
                  .fontColor($r('sys.color.font_secondary'))
                  .maxLines(2)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Column({ space: 2 }) {
                Toggle({ type: ToggleType.Switch, isOn: choice.allowed })
                  .selectedColor($r('sys.color.brand'))
                  .onChange((isOn: boolean) => {
                    choice.allowed = isOn;
                  })
                Text(choice.allowed ? 'Allow' : 'Deny')
                  .fontSize($r('sys.float.Caption_S'))
                  .fontColor(choice.allowed ? $r('sys.color.brand') : $r('sys.color.font_tertiary'))
              }
            }
            .width('100%')
            .padding({ top: 12, bottom: 12 })
            .border(i < this.choices.length - 1 ?
              { width: { bottom: 0.5 }, color: $r('sys.color.comp_divider') } : { width: 0 })
          }, (choice: PermissionChoice) => choice.permission)
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .borderRadius(20)
        .backgroundColor($r('sys.color.comp_background_primary'))
      }

      if (this.choices.length > 0) {
        Text('Anything you deny is blocked and recorded in the log.')
          .fontSize($r('sys.float.Caption_M'))
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
      }

      Row({ space: 12 }) {
        Button('Cancel')
          .layoutWeight(1)
          .height(44)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .fontColor($r('sys.color.font_primary'))
          .onClick(() => this.onCancel())
        Button('Run capsule')
          .layoutWeight(1)
          .height(44)
          .backgroundColor($r('sys.color.brand'))
          .fontColor($r('sys.color.font_on_primary'))
          .onClick(() => this.decide())
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 24 })
  }
}
