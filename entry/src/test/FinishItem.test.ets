import { describe, it, expect } from '@ohos/hypium';
import { parseRequest } from '../main/ets/core/RuleParser';
import { Capsule } from '../main/ets/core/CapsuleTypes';
import { StateValues } from '../main/ets/core/CapsuleProgram';
import { CapsuleRuntime } from '../main/ets/renderer/CapsuleRuntime';

function tasks(items: string[]): StateValues {
  const v: StateValues = {};
  v['tasks'] = items;
  v['newTask'] = '';
  return v;
}

export default function finishItemTest() {
  describe('T3-30 ticking a list item finishes it', () => {
    it('removes the ticked task from the rules "Tasks and weather" list', 0, () => {
      const c = parseRequest('a task list and the weather') as Capsule;
      expect(c !== null).assertTrue();
      const rt = new CapsuleRuntime(c);
      rt.restoreValues(tasks(['Buy milk', 'Call Sam', 'Pack']));
      expect(rt.items('tasks').length).assertEqual(3);
      expect(rt.finishItem('tasks', 1)).assertTrue();
      expect(rt.items('tasks').join('|')).assertEqual('Buy milk|Pack');
      expect(rt.display('Tasks to do: {len(tasks)}')).assertEqual('Tasks to do: 2');
    });

    it('refuses a bad index or an unknown list and changes nothing', 0, () => {
      const rt = new CapsuleRuntime(parseRequest('a task list and the weather') as Capsule);
      rt.restoreValues(tasks(['One']));
      expect(rt.finishItem('tasks', 5)).assertFalse();
      expect(rt.finishItem('nope', 0)).assertFalse();
      expect(rt.items('tasks').join('|')).assertEqual('One');
    });
  });
}
