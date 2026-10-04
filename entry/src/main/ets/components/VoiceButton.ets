import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { Palette, Space } from '../theme/Tokens';
import { MIC_OFF, VoiceInput, voiceErrorMessage } from '../core/providers/SpeechInput';

const MIC: Permissions = 'ohos.permission.MICROPHONE';

/**
 * Dictation mic for the Create prompt: a round button the size of IconButton (44vp). Tap: asks for the microphone
 * (once), then listens with the system speech recognizer, offline (core/providers/SpeechInput.ets). While
 * listening it turns blue with a pulsing ring; the text streams out through onText as the user speaks. Tap again
 * to stop; it also stops on its own after 3 s of silence (or 20 s). Errors go to onError as a user-facing message:
 * VOICE_NOTHING_HEARD, VOICE_UNAVAILABLE or MIC_OFF ("Microphone access is off. Turn it on in Settings.").
 *
 *   VoiceButton({ onText: (t: string) => this.text = t, onError: (m: string) => this.showToast(m) })
 *
 * Optional: onListening(true/false) to show "Listening…" in the prompt, onDone(finalText) to act on the result.
 */
@ComponentV2
export struct VoiceButton {
  @Param diameter: number = 44;
  /** Partial results while speaking, then the final text. Replaces the prompt text each time. */
  @Event onText: (text: string) => void = () => {
  };
  @Event onError: (message: string) => void = () => {
  };
  @Event onListening: (listening: boolean) => void = () => {
  };
  @Event onDone: (text: string) => void = () => {
  };
  @Local listening: boolean = false;
  @Local pulse: boolean = false;
  private voice: VoiceInput = new VoiceInput();
  private starting: boolean = false;
  private gone: boolean = false;

  aboutToDisappear(): void {
    this.gone = true;
    this.voice.cancel();
  }

  private async micAllowed(): Promise<boolean> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const result = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, [MIC]);
      return result.authResults.length > 0 && result.authResults[0] === 0;
    } catch (e) {
      return false;
    }
  }

  private setListening(on: boolean): void {
    this.listening = on;
    if (!on) {
      this.pulse = false;
    }
    this.onListening(on);
  }

  private async toggle(): Promise<void> {
    if (this.listening) {
      this.voice.stop(); // start() below resolves with what was heard
      return;
    }
    if (this.starting) {
      return;
    }
    this.starting = true;
    try {
      if (!(await this.micAllowed())) {
        this.onError(MIC_OFF);
        return;
      }
      this.setListening(true);
      const text = await this.voice.start((partial: string) => {
        if (!this.gone) {
          this.onText(partial);
        }
      });
      if (!this.gone) {
        this.onText(text);
        this.onDone(text);
      }
    } catch (e) {
      if (!this.gone) {
        this.onError(voiceErrorMessage(e as Error));
      }
    } finally {
      this.starting = false;
      if (!this.gone) {
        this.setListening(false);
      }
    }
  }

  build() {
    Stack() {
      if (this.listening) {
        Circle()
          .width(this.diameter)
          .height(this.diameter)
          .fill(Palette.blue)
          .opacity(this.pulse ? 0 : 0.35)
          .scale({ x: this.pulse ? 1.7 : 1, y: this.pulse ? 1.7 : 1 })
          .animation({ duration: 1100, curve: Curve.EaseOut, iterations: -1, playMode: PlayMode.Normal })
          .onAppear(() => {
            this.pulse = true;
          })
      }
      Stack() {
        SymbolGlyph(this.listening ? $r('sys.symbol.mic_fill') : $r('sys.symbol.mic'))
          .fontSize(20)
          .fontColor([this.listening ? Palette.surface : Palette.text])
      }
      .width(this.diameter)
      .height(this.diameter)
      .borderRadius(this.diameter / 2)
      .backgroundColor(this.listening ? Palette.blue : Palette.softButton)
    }
    .width(this.diameter)
    .height(this.diameter)
    .responseRegion({ x: -(Math.max(0, Space.touch - this.diameter) / 2), y: -(Math.max(0, Space.touch - this.diameter) / 2),
      width: Math.max(this.diameter, Space.touch), height: Math.max(this.diameter, Space.touch) })
    .accessibilityText(this.listening ? 'Stop listening' : 'Speak your request')
    .onClick(() => {
      this.toggle();
    })
  }
}
