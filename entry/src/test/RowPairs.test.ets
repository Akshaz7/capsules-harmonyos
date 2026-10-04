import { describe, it, expect } from '@ohos/hypium';
import { CapsuleComponent } from '../main/ets/core/CapsuleTypes';
import { rowPairs } from '../main/ets/renderer/RowPairs';

function buttons(n: number): CapsuleComponent[] {
  const out: CapsuleComponent[] = [];
  for (let i = 0; i < n; i++) {
    out.push({ type: 'button', label: `B${i}`, action: 'reset' } as CapsuleComponent);
  }
  return out;
}

export default function rowPairsTest() {
  describe('Row layout: 3+ children go two per line', () => {
    it('splits 3 into 2+1 and 4 into 2+2', 0, () => {
      expect(rowPairs(buttons(3)).map((p: CapsuleComponent[]) => p.length).join('+')).assertEqual('2+1');
      expect(rowPairs(buttons(4)).map((p: CapsuleComponent[]) => p.length).join('+')).assertEqual('2+2');
      expect(rowPairs(buttons(5)).map((p: CapsuleComponent[]) => p.length).join('+')).assertEqual('2+2+1');
      expect(rowPairs([]).length).assertEqual(0);
    });
  });
}
