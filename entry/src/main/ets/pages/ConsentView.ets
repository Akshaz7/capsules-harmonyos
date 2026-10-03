import { Capsule, Permission } from '../core';

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
  @Local choices: PermissionChoice[] = [];

  aboutToAppear(): void {
    this.choices = this.capsule.permissions.map((p: Permission) => new PermissionChoice(p));
  }

  build() {
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
          .onClick(() => {
            const allowed: Permission[] = this.choices
              .filter((c: PermissionChoice) => c.allowed)
              .map((c: PermissionChoice) => c.permission);
            this.onDecide(allowed);
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 24 })
  }
}
