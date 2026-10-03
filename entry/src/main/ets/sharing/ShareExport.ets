/**
 * Exports a capsule to a small .json file in the app cache and opens the system
 * Share panel.
 *
 * API evidence (DevEco Studio 6.1.1 SDK declarations):
 *   @kit.ShareKit  -> systemShare.SharedData / ShareController.show(context, options)
 *   @kit.ArkData   -> uniformTypeDescriptor.UniformDataType.FILE ('general.file')
 *   @kit.CoreFileKit -> fileIo
 */
import { common } from '@kit.AbilityKit';
import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { systemShare } from '@kit.ShareKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Capsule } from '../core/CapsuleTypes';
import { exportCapsuleJson, utf8ByteLength } from './CapsuleShare';

const DOMAIN: number = 0x0001;
const TAG: string = 'ShareExport';

/** Keeps the id usable as a file name. */
function safeFileName(id: string): string {
  return id.replace(/[^A-Za-z0-9_-]/g, '_');
}

/** Writes the capsule JSON into the cache dir and returns the file path. */
function writeShareFile(context: common.UIAbilityContext, capsule: Capsule): string {
  const path: string = `${context.cacheDir}/capsule-${safeFileName(capsule.id)}.json`;
  const file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
  try {
    fileIo.writeSync(file.fd, exportCapsuleJson(capsule));
  } finally {
    fileIo.closeSync(file);
  }
  return path;
}

/**
 * Writes the capsule to a .json file and opens the system Share panel.
 * Throws a clear Error when the file cannot be written or the panel fails;
 * the caller shows the message.
 */
export async function shareCapsule(context: common.UIAbilityContext, capsule: Capsule): Promise<void> {
  let path: string = '';
  try {
    path = writeShareFile(context, capsule);
  } catch (e) {
    const err = e as BusinessError;
    hilog.error(DOMAIN, TAG, 'write failed: %{public}s', err.message);
    throw new Error(`Could not write the capsule file: ${err.message}`);
  }
  const record: systemShare.SharedRecord = {
    utd: utd.UniformDataType.FILE,
    // A sandbox path needs the app-qualified uri (file://<bundle>/data/storage/...); a bare
    // `file://` + path makes the share panel close at once on real phones.
    uri: fileUri.getUriFromPath(path),
    title: capsule.name
  };
  const options: systemShare.ShareControllerOptions = {
    selectionMode: systemShare.SelectionMode.SINGLE,
    previewMode: systemShare.SharePreviewMode.DETAIL
  };
  try {
    await new systemShare.ShareController(new systemShare.SharedData(record)).show(context, options);
  } catch (e) {
    const err = e as BusinessError;
    hilog.error(DOMAIN, TAG, 'share panel failed: %{public}s', err.message);
    throw new Error(`Could not open the share panel: ${err.message}`);
  }
}

/** Largest capsule JSON we put in a QR code; bigger codes are too dense to scan from a phone screen. */
export const MAX_QR_BYTES: number = 1500;

/** The capsule as QR text (the same JSON as the file), or '' when it is too big to scan reliably. */
export function capsuleQrText(capsule: Capsule): string {
  const json: string = exportCapsuleJson(capsule);
  return utf8ByteLength(json) <= MAX_QR_BYTES ? json : '';
}

/**
 * Fallback when the Share panel can't open: lets the user save the capsule as a .json file in Files.
 * Returns false when the user cancelled. Throws a clear Error when writing fails.
 */
export async function saveCapsuleToFiles(context: common.UIAbilityContext, capsule: Capsule): Promise<boolean> {
  const options = new picker.DocumentSaveOptions();
  options.newFileNames = [`${capsule.name.replace(/[\\/:*?"<>|]/g, ' ').trim() || 'capsule'}.json`];
  let uris: string[] = [];
  try {
    uris = await new picker.DocumentViewPicker(context).save(options);
  } catch (e) {
    const err = e as BusinessError;
    hilog.error(DOMAIN, TAG, 'save picker failed: %{public}s', err.message);
    throw new Error(`Could not open Files: ${err.message}`);
  }
  if (uris.length === 0) {
    return false;
  }
  try {
    const file = fileIo.openSync(uris[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, exportCapsuleJson(capsule));
    } finally {
      fileIo.closeSync(file);
    }
  } catch (e) {
    const err = e as BusinessError;
    hilog.error(DOMAIN, TAG, 'save to files failed: %{public}s', err.message);
    throw new Error(`Could not save the file: ${err.message}`);
  }
  return true;
}
