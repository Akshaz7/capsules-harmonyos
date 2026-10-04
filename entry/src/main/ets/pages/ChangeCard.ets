import { LANGUAGE_MESSAGE, LIMITS_TEXT } from './CreateText';

/** The example the English-only note offers on a capsule page; tapping it fills the input. */
export const CHANGE_EXAMPLE = 'make the timer 1 minute';
export const CHANGE_FAILED = "Couldn't make that change.";

/**
 * "Change it…" on a capsule page (T3-16): type a change, see what it would do, then Apply or Cancel.
 * Nothing changes until Apply. "Undo last change" brings back the version before the last Apply.
 */
const CHANGE_INPUT_ID: string = 'change-it-input';

@ComponentV2
export struct ChangeCard {
  @Param busy: boolean = false;
  /** What the pending change would do, one line each; empty when nothing is pending. */
  @Param summary: string[] = [];
  /** '' | 'language' (not English) | 'failed'. */
  @Param issue: string = '';
  /** With issue 'failed': the reason, e.g. the model's refusal; '' for the plain failure text. */
  @Param issueText: string = '';
  @Param canUndo: boolean = false;
  @Event onSubmit: (text: string) => void = () => {
  };
  @Event onApply: () => void = () => {
  };
  @Event onCancel: () => void = () => {
  };
  @Event onUndo: () => void = () => {
  };
  @Event onLimits: () => void = () => {
  };
  @Local text: string = '';
  /** T3-31: focus the field when the user opened the card from "Change it…" (not when it shows a result). */
  @Param autoFocus: boolean = false;

  aboutToAppear(): void {
    if (this.autoFocus) {
      this.focusField();
    }
  }

  @Monitor('autoFocus')
  onAutoFocus(): void {
    if (this.autoFocus) {
      this.focusField();
    }
  }

  private focusField(): void {
    // After the card is on screen (and the body has scrolled to it).
    setTimeout(() => {
      try {
        this.getUIContext().getFocusController().requestFocus(CHANGE_INPUT_ID);
      } catch (e) {
        // not focusable yet (busy) or already gone: the user can tap the field
      }
    }, 250);
  }

  private submit(): void {
    const t = this.text.trim();
    if (t.length > 0 && !this.busy) {
      this.onSubmit(t);
    }
  }

  @Builder
  pending() {
    Column({ space: 8 }) {
      Text('This will change:')
        .fontSize($r('sys.float.Body_M'))
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      ForEach(this.summary, (line: string) => {
        Text(`• ${line}`)
          .fontSize($r('sys.float.Body_L'))
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
      }, (line: string) => line)
      Row({ space: 8 }) {
        Button('Apply', { controlSize: ControlSize.SMALL })
          .onClick(() => {
            this.onApply();
            this.text = '';
          })
        Button('Cancel', { buttonStyle: ButtonStyleMode.NORMAL, controlSize: ControlSize.SMALL })
          .onClick(() => this.onCancel())
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  language() {
    Text() {
      Span(LANGUAGE_MESSAGE)
      Span(`'${CHANGE_EXAMPLE}'`)
        .fontColor($r('sys.color.font_emphasize'))
        .fontWeight(FontWeight.Medium)
        .onClick(() => {
          this.text = CHANGE_EXAMPLE;
        })
      Span('.')
    }
    .fontSize($r('sys.float.Body_M'))
    .fontColor($r('sys.color.font_primary'))
    .width('100%')
  }

  @Builder
  failed() {
    Column({ space: 6 }) {
      Text(this.issueText.length > 0 ? this.issueText : CHANGE_FAILED)
        .fontSize($r('sys.float.Body_M'))
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
      Text(LIMITS_TEXT)
        .fontSize($r('sys.float.Body_S'))
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
        .onClick(() => this.onLimits())
    }
    .width('100%')
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        TextInput({ text: this.text, placeholder: 'Change it…' })
          .id(CHANGE_INPUT_ID)
          .layoutWeight(1)
          .enterKeyType(EnterKeyType.Done)
          .enabled(!this.busy)
          .onChange((v: string) => {
            this.text = v;
          })
          .onSubmit(() => this.submit())
        if (this.busy) {
          Row({ space: 6 }) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color($r('sys.color.brand'))
            Text('Building…')
              .fontSize($r('sys.float.Body_M'))
              .fontColor($r('sys.color.font_secondary'))
          }
        } else {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.arrow_up'))
              .fontSize(18)
              .fontColor([$r('sys.color.font_on_primary')])
          }
          .width(36)
          .height(36)
          .enabled(this.text.trim().length > 0)
          .accessibilityText('Change')
          .onClick(() => this.submit())
        }
      }
      .width('100%')
      if (this.summary.length > 0) {
        this.pending()
      } else if (this.issue === 'language') {
        this.language()
      } else if (this.issue === 'failed') {
        this.failed()
      }
      if (this.canUndo && this.summary.length === 0 && !this.busy) {
        Button('Undo last change', { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
          .onClick(() => this.onUndo())
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(20)
    .backgroundColor($r('sys.color.comp_background_primary'))
  }
}
