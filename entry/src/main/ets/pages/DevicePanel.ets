import { PairedDevice } from '../adapters/DeviceRelay';
import { deviceName } from '../adapters/DeviceStore';

/** "Show on another device" on a capsule page (timers and counters): pair, send, and the device's live state. */
@ComponentV2
export struct DevicePanel {
  @Param devices: PairedDevice[] = [];
  /** No relay configured: the in-app simulation is used, and the panel says so. */
  @Param simulated: boolean = false;
  /** Live line from the device, e.g. "Wrist: Pull-ups 7"; '' when nothing was sent. */
  @Param status: string = '';
  @Event onPairScan: () => void = () => {
  };
  @Event onPairPhrase: (phrase: string) => void = () => {
  };
  @Event onShow: (deviceId: string) => void = () => {
  };
  @Event onUnpair: (deviceId: string) => void = () => {
  };
  @Local pairing: boolean = false;
  @Local phrase: string = '';

  @Builder
  pairRow() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Button('Scan its QR code', { buttonStyle: ButtonStyleMode.NORMAL, controlSize: ControlSize.SMALL })
          .onClick(() => this.onPairScan())
        Button('Type its 3 words', { buttonStyle: ButtonStyleMode.NORMAL, controlSize: ControlSize.SMALL })
          .onClick(() => {
            this.pairing = true;
          })
      }
      .width('100%')
      if (this.pairing) {
        Row({ space: 8 }) {
          TextInput({ text: this.phrase, placeholder: 'brave-otter-lamp' })
            .layoutWeight(1)
            .onChange((v: string) => {
              this.phrase = v;
            })
          Button('Pair', { controlSize: ControlSize.SMALL })
            .enabled(this.phrase.trim().length > 0)
            .onClick(() => {
              this.onPairPhrase(this.phrase);
              this.phrase = '';
              this.pairing = false;
            })
        }
        .width('100%')
      }
    }
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.watch'))
          .fontSize(20)
          .fontColor([$r('sys.color.icon_emphasize')])
        Text('Show on another device')
          .fontSize($r('sys.float.Subtitle_S'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      Text('Only the type, the label and one number leave your phone. The capsule keeps working here.')
        .fontSize($r('sys.float.Caption_M'))
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      if (this.simulated) {
        Text('Simulated device: no relay is set up yet, nothing leaves the phone.')
          .fontSize($r('sys.float.Caption_M'))
          .fontColor($r('sys.color.warning'))
          .width('100%')
      }
      if (this.devices.length === 0) {
        this.pairRow()
      } else {
        ForEach(this.devices, (d: PairedDevice) => {
          Row({ space: 8 }) {
            Text(deviceName(d))
              .fontSize($r('sys.float.Body_L'))
              .fontColor($r('sys.color.font_primary'))
              .layoutWeight(1)
            Button(`Show on ${deviceName(d)}`, { controlSize: ControlSize.SMALL })
              .onClick(() => this.onShow(d.id))
            Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
              SymbolGlyph($r('sys.symbol.trash'))
                .fontSize(18)
                .fontColor([$r('sys.color.icon_secondary')])
            }
            .width(36)
            .height(36)
            .accessibilityText('Unpair')
            .onClick(() => this.onUnpair(d.id))
          }
          .width('100%')
        }, (d: PairedDevice) => d.id)
        if (!this.pairing) {
          Button('Pair another device', { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
            .onClick(() => {
              this.pairing = true;
            })
        } else {
          this.pairRow()
        }
      }
      if (this.status.length > 0) {
        Text(this.status)
          .fontSize($r('sys.float.Body_M'))
          .fontColor($r('sys.color.font_emphasize'))
          .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(20)
    .backgroundColor($r('sys.color.comp_background_primary'))
  }
}
