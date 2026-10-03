/**
 * Minimal sharing controls: "Share" exports the capsule on screen, "Import" takes
 * one from a .json file or a static QR code. Imported capsules go to the consent
 * screen first; nothing is saved until the app runs them.
 */
import { common } from '@kit.AbilityKit';
import { Capsule } from '../core/CapsuleTypes';
import { ImportResult, onImported as deliverPreparedImport, PreparedImport } from './CapsuleShare';
import { ImportOutcome, pickAndPrepare, scanAndPrepare } from './ImportFlow';
import { capsuleQrText, saveCapsuleToFiles, shareCapsule } from './ShareExport';

@ComponentV2
export struct SharingBar {
  @Param capsule: Capsule | undefined = undefined;
  @Param showShare: boolean = true;
  @Param showImport: boolean = true;
  /** Import only, as a small round icon button (e.g. in a header). Errors show as a toast. */
  @Param compact: boolean = false;
  @Event onImported: (payload: PreparedImport) => void = () => {
  };
  @Local message: string = '';
  @Local busy: boolean = false;
  /** The capsule JSON shown as a QR code; '' when the QR sheet is closed. */
  @Local qrText: string = '';

  private host(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async share(): Promise<void> {
    if (this.capsule === undefined || this.busy) {
      return;
    }
    this.busy = true;
    this.message = '';
    try {
      await shareCapsule(this.host(), this.capsule);
    } catch (e) {
      // Logged in ShareExport. Offer the other ways out instead of a dead button.
      this.offerFallback();
    }
    this.busy = false;
  }

  /** When the Share panel can't open: save to Files, or show a QR code another phone can scan. */
  private offerFallback(): void {
    try {
      this.getUIContext().showActionSheet({
        title: "Couldn't open the share panel",
        message: 'Share it another way:',
        sheets: [
          { title: 'Save to Files', action: () => this.saveToFiles() },
          { title: 'Show QR code', action: () => this.showQr() }
        ]
      });
    } catch (e) {
      this.report("Couldn't open the share panel.");
    }
  }

  private async saveToFiles(): Promise<void> {
    if (this.capsule === undefined) {
      return;
    }
    try {
      if (await saveCapsuleToFiles(this.host(), this.capsule)) {
        this.report('Saved to Files');
      }
    } catch (e) {
      this.report((e as Error).message);
    }
  }

  private showQr(): void {
    if (this.capsule === undefined) {
      return;
    }
    const text = capsuleQrText(this.capsule);
    if (text.length === 0) {
      this.report('This capsule is too big for a QR code. Use Save to Files.');
      return;
    }
    this.qrText = text;
  }

  private handle(outcome: ImportOutcome): void {
    if (outcome.cancelled || outcome.result === undefined) {
      return;
    }
    const result: ImportResult = outcome.result;
    const handed: boolean = deliverPreparedImport(result, (payload: PreparedImport) => {
      this.message = '';
      this.onImported(payload);
    });
    if (!handed) {
      this.report(result.error ?? 'Could not import this file.');
    }
  }

  private async importFromFile(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.message = '';
    const outcome: ImportOutcome = await pickAndPrepare(this.host());
    this.busy = false;
    this.handle(outcome);
  }

  private async importFromQr(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.message = '';
    const outcome: ImportOutcome = await scanAndPrepare(this.host());
    this.busy = false;
    this.handle(outcome);
  }

  private report(text: string): void {
    if (this.compact) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: text });
      } catch (e) {
        this.message = text;
      }
    } else {
      this.message = text;
    }
  }

  private chooseImportSource(): void {
    const dialog: AlertDialogParamWithButtons = {
      title: 'Import a capsule',
      message: 'Where is the capsule?',
      primaryButton: {
        value: 'From file',
        action: () => {
          this.importFromFile();
        }
      },
      secondaryButton: {
        value: 'Scan QR code',
        action: () => {
          this.importFromQr();
        }
      }
    };
    this.getUIContext().showAlertDialog(dialog);
  }

  build() {
    if (this.compact) {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.square_and_arrow_down'))
          .fontSize(22)
          .fontColor([$r('sys.color.icon_primary')])
      }
      .width(40)
      .height(40)
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      .enabled(!this.busy)
      .accessibilityText('Import a capsule')
      .onClick(() => {
        this.chooseImportSource();
      })
    } else {
      this.bar()
    }
  }

  @Builder
  bar() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        if (this.showShare) {
          Button('Share')
            .layoutWeight(1)
            .enabled(this.capsule !== undefined && !this.busy)
            .onClick(() => {
              this.share();
            })
        }
        if (this.showImport) {
          Button('Import')
            .layoutWeight(1)
            .enabled(!this.busy)
            .onClick(() => {
              this.chooseImportSource();
            })
        }
      }
      .width('100%')
      if (this.showShare) {
        Button('Show as QR code', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .enabled(this.capsule !== undefined && !this.busy)
          .onClick(() => this.showQr())
      }
      if (this.message.length > 0) {
        Text(this.message)
          .fontSize(13)
          .fontColor(Color.Red)
          .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8 })
    .bindSheet(this.qrText.length > 0, this.qrSheet(), {
      height: SheetSize.MEDIUM,
      title: { title: 'Scan to import' },
      onDisappear: () => {
        this.qrText = '';
      }
    })
  }

  @Builder
  qrSheet() {
    Column({ space: 12 }) {
      QRCode(this.qrText)
        .width(260)
        .height(260)
        .color(Color.Black)
        .backgroundColor(Color.White)
        .padding(12)
        .borderRadius(12)
      Text('On the other phone: Harmoniser > Import > Scan QR code.')
        .fontSize($r('sys.float.Body_M'))
        .fontColor($r('sys.color.font_secondary'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding(16)
  }
}
