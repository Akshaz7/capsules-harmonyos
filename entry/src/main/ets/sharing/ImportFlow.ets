/**
 * The two import paths: the system file picker and the default Scan Kit UI for a
 * static QR code. Both hand their text to prepareImport, which validates the
 * capsule and gives it a fresh id. Nothing here saves anything.
 *
 * API evidence (DevEco Studio 6.1.1 SDK declarations):
 *   @kit.CoreFileKit -> picker.DocumentViewPicker(context).select(options)
 *   @kit.ScanKit     -> scanBarcode.startScanForResult(context, options)
 *                       (default UI; Scan Kit pre-authorises the system camera,
 *                        so the app needs no CAMERA permission)
 */
import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { fileIo } from '@kit.CoreFileKit';
import { scanBarcode } from '@kit.ScanKit';
import { scanCore } from '@kit.ScanKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ImportResult, MAX_SHARE_BYTES, prepareImport } from './CapsuleShare';
import { pairCodeFromQr } from '../adapters/DeviceRelay';

const DOMAIN: number = 0x0001;
const TAG: string = 'ImportFlow';
const SCAN_CANCELLED: number = 1000500002;

/** What an import attempt produced: nothing (cancelled) or a result to show. */
export interface ImportOutcome {
  cancelled: boolean;
  result?: ImportResult;
  /** The scan was a device's pairing QR (https://<host>/pair?code=...): pair it instead of importing. */
  pairCode?: string;
}

/**
 * Reads the picked .json file, refusing anything over the cap before reading it.
 * Reads through the open fd: openSync accepts the picker's URI, but readTextSync
 * only accepts a sandbox path.
 */
function readPickedFile(uri: string): ImportResult {
  const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
  try {
    const size: number = fileIo.statSync(file.fd).size;
    if (size > MAX_SHARE_BYTES) {
      return { ok: false, error: 'File too large (max 8 KB)' };
    }
    const buffer: ArrayBuffer = new ArrayBuffer(size);
    const read: number = fileIo.readSync(file.fd, buffer);
    const text: string = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buffer, 0, read));
    return prepareImport(text);
  } finally {
    fileIo.closeSync(file);
  }
}

/** Picks one .json file through the system picker and prepares it. */
export async function pickAndPrepare(context: common.UIAbilityContext): Promise<ImportOutcome> {
  const options: picker.DocumentSelectOptions = {
    maxSelectNumber: 1,
    fileSuffixFilters: ['JSON (.json)|.json']
  };
  try {
    const uris: string[] = await new picker.DocumentViewPicker(context).select(options);
    if (uris.length === 0) {
      return { cancelled: true };
    }
    try {
      return { cancelled: false, result: readPickedFile(uris[0]) };
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'read failed: %{public}s', err.message);
      return { cancelled: false, result: { ok: false, error: `Could not read the file: ${err.message}` } };
    }
  } catch (e) {
    const err = e as BusinessError;
    hilog.error(DOMAIN, TAG, 'picker failed: %{public}s', err.message);
    return { cancelled: false, result: { ok: false, error: `Could not open the file picker: ${err.message}` } };
  }
}

/** Scans one static QR code with the default Scan Kit UI and prepares its text. */
export async function scanAndPrepare(context: common.UIAbilityContext): Promise<ImportOutcome> {
  const options: scanBarcode.ScanOptions = {
    scanTypes: [scanCore.ScanType.QR_CODE],
    enableMultiMode: false,
    enableAlbum: false
  };
  try {
    const scanned: scanBarcode.ScanResult = await scanBarcode.startScanForResult(context, options);
    const code: string = pairCodeFromQr(scanned.originalValue);
    if (code.length > 0) {
      return { cancelled: false, pairCode: code };
    }
    return { cancelled: false, result: prepareImport(scanned.originalValue) };
  } catch (e) {
    const err = e as BusinessError;
    if (err.code === SCAN_CANCELLED) {
      return { cancelled: true };
    }
    hilog.error(DOMAIN, TAG, 'scan failed: %{public}s', err.message);
    return { cancelled: false, result: { ok: false, error: `Could not scan a QR code: ${err.message}` } };
  }
}
