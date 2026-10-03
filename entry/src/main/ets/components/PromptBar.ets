import { Palette, Space } from '../theme/Tokens';
import { IconButton } from './Buttons';

/**
 * The Create prompt bar, docked above the tab bar: Snap (camera) on the left, the request text in the middle
 * (the app's existing rotating placeholder), and a 44vp send circle on the right (blue, grey when empty,
 * a spinner while building). White, radius 28, soft shadow, at least 56 tall.
 */
@ComponentV2
export struct PromptBar {
  @Param text: string = '';
  @Param placeholder: string = '';
  @Param busy: boolean = false;
  @Event onTextChange: (value: string) => void = () => {
  };
  @Event onSend: () => void = () => {
  };
  @Event onSnap: () => void = () => {
  };
  @Event onFocusChange: (focused: boolean) => void = () => {
  };

  private canSend(): boolean {
    return !this.busy && this.text.trim().length > 0;
  }

  build() {
    Row({ space: 8 }) {
      IconButton({ icon: $r('sys.symbol.camera'), label: 'Snap', soft: true, onTap: () => this.onSnap() })
        .enabled(!this.busy)
      TextArea({ text: this.text, placeholder: this.placeholder })
        .layoutWeight(1)
        .constraintSize({ minHeight: Space.touch, maxHeight: 120 })
        .fontSize(17)
        .fontColor(Palette.text)
        .placeholderColor(Palette.disabled)
        .placeholderFont({ size: 17 })
        .backgroundColor(Color.Transparent)
        .padding({ left: 4, right: 4, top: 10, bottom: 10 })
        .borderRadius(0)
        .enterKeyType(EnterKeyType.Send)
        .onChange((v: string) => this.onTextChange(v))
        .onSubmit(() => {
          if (this.canSend()) {
            this.onSend();
          }
        })
        .onFocus(() => this.onFocusChange(true))
        .onBlur(() => this.onFocusChange(false))
      Stack() {
        if (this.busy) {
          LoadingProgress()
            .width(24)
            .height(24)
            .color(Palette.surface)
        } else {
          SymbolGlyph($r('sys.symbol.arrow_up'))
            .fontSize(20)
            .fontColor([Palette.surface])
        }
      }
      .width(Space.touch)
      .height(Space.touch)
      .borderRadius(Space.touch / 2)
      .backgroundColor(this.busy || this.canSend() ? Palette.blue : Palette.sendDisabled)
      .accessibilityText(this.busy ? 'Creating' : 'Create')
      .onClick(() => {
        if (this.canSend()) {
          this.onSend();
        }
      })
    }
    .alignItems(VerticalAlign.Bottom)
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .padding(6)
    .borderRadius(28)
    .backgroundColor(Palette.surface)
    .shadow({ radius: 24, offsetY: 8, color: Palette.shadow })
  }
}
