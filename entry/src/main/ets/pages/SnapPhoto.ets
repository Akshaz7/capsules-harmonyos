/**
 * Snap (T3-2): a photo from the camera or the gallery, copied into the app cache for core's
 * generateCapsuleFromImage. Both pickers are system UIs, so the app needs no camera or media permission.
 */
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { camera, cameraPicker } from '@kit.CameraKit';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0001;
const TAG = 'SnapPhoto';

/** What the Snap button promises: the phone reads the photo first (on-device OCR, T5-6). */
export const SNAP_HINT = 'Reads the text in the photo on your phone; cloud AI only if needed.';
/** Only when both on-device paths failed and core says the cloud could do it (needsCloud). */
export const SNAP_NEEDS_CLOUD = "Couldn't read this photo on your phone. Cloud AI can try it.";

/** The system camera; '' when the user cancels or there is no camera. */
export async function takePhoto(ctx: common.Context): Promise<string> {
  try {
    const profile: cameraPicker.PickerProfile = { cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK };
    const r = await cameraPicker.pick(ctx, [cameraPicker.PickerMediaType.PHOTO], profile);
    return r.resultCode === 0 && r.resultUri.length > 0 ? r.resultUri : '';
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'camera failed: %{public}s', (e as BusinessError).message);
    return '';
  }
}

/** The system photo picker, one image; '' when the user cancels. */
export async function pickPhoto(): Promise<string> {
  try {
    const options = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 1;
    const r = await new photoAccessHelper.PhotoViewPicker().select(options);
    return r.photoUris.length > 0 ? r.photoUris[0] : '';
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'photo picker failed: %{public}s', (e as BusinessError).message);
    return '';
  }
}

/** Copies a picked or shared image URI into the cache dir (core reads sandbox paths). '' on failure. */
export function copyToCache(ctx: common.Context, uri: string): string {
  let file: fileIo.File | undefined = undefined;
  try {
    file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    const dot = uri.lastIndexOf('.');
    const ext = dot > uri.lastIndexOf('/') ? uri.substring(dot).toLowerCase() : '.jpg';
    const path = `${ctx.cacheDir}/snap-${Date.now()}${ext}`;
    fileIo.copyFileSync(file.fd, path);
    return path;
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'copy failed: %{public}s', (e as BusinessError).message);
    return '';
  } finally {
    if (file !== undefined) {
      fileIo.closeSync(file);
    }
  }
}

/** Removes a cached snap; never throws. */
export function removeSnap(path: string): void {
  try {
    fileIo.unlinkSync(path);
  } catch (e) {
    // already gone
  }
}
