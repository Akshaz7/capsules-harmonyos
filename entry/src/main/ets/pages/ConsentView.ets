import { Capsule, Permission } from '../core';

@ObservedV2
class PermissionChoice {
  permission: Permission;
  @Trace allowed: boolean = false;

  constructor(permission: Permission) {
    this.permission = permission;
  }
}

/** Shown before a capsule first runs: one allow/deny switch per declared permission. */
@ComponentV2
export struct ConsentView {
  @Require @Param capsule: Capsule;
  @Event onDecide: (allowed: Permission[]) => void = () => {};
  @Local choices: PermissionChoice[] = [];

  aboutToAppear(): void {
    this.choices = this.capsule.permissions.map((p: Permission) => new PermissionChoice(p));
  }

  build() {
    Column({ space: 12 }) {
      Text(this.capsule.name)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .width('100%')
      Text(this.capsule.permissions.length > 0 ? 'This capsule asks for:' : 'This capsule needs no permissions.')
        .fontSize(16)
        .width('100%')
      ForEach(this.choices, (choice: PermissionChoice) => {
        Row() {
          Text(choice.permission).fontSize(18).layoutWeight(1)
          Text(choice.allowed ? 'Allow' : 'Deny')
            .fontSize(16)
            .fontColor(choice.allowed ? Color.Black : Color.Gray)
            .margin({ right: 8 })
          Toggle({ type: ToggleType.Switch, isOn: choice.allowed })
            .onChange((isOn: boolean) => {
              choice.allowed = isOn;
            })
        }
        .width('100%')
      }, (choice: PermissionChoice) => choice.permission)
      Button('Run capsule')
        .width('100%')
        .margin({ top: 12 })
        .onClick(() => {
          const allowed: Permission[] = this.choices
            .filter((c: PermissionChoice) => c.allowed)
            .map((c: PermissionChoice) => c.permission);
          this.onDecide(allowed);
        })
    }
    .width('100%')
    .padding(16)
  }
}
