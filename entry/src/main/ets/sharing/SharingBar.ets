/**
 * Minimal sharing controls: "Share" exports the capsule on screen, "Import" takes
 * one from a .json file or a static QR code. Imported capsules go to the consent
 * screen first; nothing is saved until the app runs them.
 */
import { common } from '@kit.AbilityKit';
import { Capsule } from '../core/CapsuleTypes';
import { ImportResult, onImported as deliverPreparedImport, PreparedImport } from './CapsuleShare';
import { ImportOutcome, pickAndPrepare, scanAndPrepare } from './ImportFlow';
import { shareCapsule } from './ShareExport';

@ComponentV2
export struct SharingBar {
  @Param capsule: Capsule | undefined = undefined;
  @Param showShare: boolean = true;
  @Event onImported: (payload: PreparedImport) => void = () => {
  };
  @Local message: string = '';
  @Local busy: boolean = false;

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
      this.message = (e as Error).message;
    }
    this.busy = false;
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
      this.message = result.error ?? 'Could not import this file.';
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
        Button('Import')
          .layoutWeight(1)
          .enabled(!this.busy)
          .onClick(() => {
            this.chooseImportSource();
          })
      }
      .width('100%')
      if (this.message.length > 0) {
        Text(this.message)
          .fontSize(13)
          .fontColor(Color.Red)
          .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8 })
  }
}
