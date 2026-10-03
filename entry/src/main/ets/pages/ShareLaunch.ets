import { AbilityConstant, Want } from '@kit.AbilityKit';
import { AppStorageV2 } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { systemShare } from '@kit.ShareKit';

const DOMAIN = 0x0001;
const TAG = 'ShareLaunch';
const SYSTEM_SHARE = 'ReasonMessage_SystemShare';

/** Hands content shared to Harmoniser from the system share sheet over to the Index page. */
@ObservedV2
export class ShareLaunch {
  /** Shared text or link; '' when the share was an image. */
  @Trace text: string = '';
  /** Shared image file uri; '' when the share was text. */
  @Trace imageUri: string = '';
  /** Bumped on every share, so sharing the same thing twice still reaches the page. */
  @Trace seq: number = 0;
}

export function shareLaunch(): ShareLaunch {
  return AppStorageV2.connect(ShareLaunch, 'shareLaunch', () => new ShareLaunch())!;
}

function isType(utd: string, type: string): boolean {
  try {
    return utd === type || uniformTypeDescriptor.getTypeDescriptor(utd).belongsTo(type);
  } catch (e) {
    return false;
  }
}

/** Reads the first text, link or image record if `want` came from the system share sheet. Never throws. */
export function takeShareWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
  if (launchParam.launchReasonMessage !== SYSTEM_SHARE && want.action !== 'ohos.want.action.sendData') {
    return;
  }
  systemShare.getSharedData(want).then((data: systemShare.SharedData) => {
    const records = data.getRecords();
    const image = records.find((r: systemShare.SharedRecord) =>
      isType(r.utd, uniformTypeDescriptor.UniformDataType.IMAGE) && (r.uri ?? '').length > 0);
    const text = records.find((r: systemShare.SharedRecord) =>
      isType(r.utd, uniformTypeDescriptor.UniformDataType.TEXT) && (r.content ?? r.uri ?? '').length > 0);
    const launch = shareLaunch();
    if (text !== undefined) {
      // A link record may carry the url in content or in uri.
      launch.text = (text.content ?? text.uri ?? '').trim();
      launch.imageUri = '';
    } else if (image !== undefined) {
      launch.text = '';
      launch.imageUri = image.uri ?? '';
    } else {
      hilog.warn(DOMAIN, TAG, 'share had no text or image record (%{public}d records)', records.length);
      return;
    }
    hilog.info(DOMAIN, TAG, 'received a shared %{public}s', launch.text.length > 0 ? 'text' : 'image');
    launch.seq++;
  }).catch((e: BusinessError) => {
    hilog.error(DOMAIN, TAG, 'getSharedData failed: %{public}d %{public}s', e.code, e.message);
  });
}
