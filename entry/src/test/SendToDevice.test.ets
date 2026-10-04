import { describe, it, expect } from '@ohos/hypium';
import { ButtonComponent, Capsule, CounterComponent } from '../main/ets/core/CapsuleTypes';
import { CapsuleRuntime } from '../main/ets/renderer/CapsuleRuntime';

function capsule(): Capsule {
  const counter: CounterComponent = { type: 'counter', id: 'c', label: 'Reps' } as CounterComponent;
  const send: ButtonComponent = { type: 'button', label: 'Show on my watch', action: 'sendToDevice' };
  const c: Capsule = { schemaVersion: 0, id: 'reps', name: 'Reps', permissions: ['devices'], ui: [counter, send] };
  return c;
}

export default function sendToDeviceTest() {
  describe('T3-15 a sendToDevice button uses the page send path', () => {
    it('calls onSendToDevice when the button is pressed', 0, () => {
      const rt = new CapsuleRuntime(capsule());
      let sent = 0;
      rt.onSendToDevice = () => {
        sent++;
      };
      rt.press(capsule().ui[1] as ButtonComponent);
      expect(sent).assertEqual(1);
    });
  });
}
