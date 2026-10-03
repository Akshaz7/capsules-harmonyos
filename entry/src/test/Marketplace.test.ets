import { describe, it, expect } from '@ohos/hypium';
import {
  libraryItems, MarketItem, marketErrorMessage, matchesSearch, parseMarketList
} from '../main/ets/adapters/MarketplaceClient';

const LIBRARY = '{"version":1,"templates":[' +
  '{"id":"tea","name":"Tea timer","description":"Steep tea","category":"timers","tags":["tea","steep"],' +
  '"capsule":{"schemaVersion":0,"id":"tea","name":"Tea","permissions":["reminders"],' +
  '"ui":[{"type":"timer","id":"t","label":"Tea","minutes":3}]}},' +
  '{"id":"bad","name":"Broken","description":"x","category":"games","tags":[],"capsule":{"schemaVersion":0}}]}';

export default function marketplaceTest() {
  describe('MarketplaceClient (T3-10/T3-11)', () => {
    it('parses the list and drops entries without an id', 0, () => {
      const page = parseMarketList('{"capsules":[{"id":"abc","name":"Squats","description":"Count squats",' +
        '"tags":["fitness"],"installs":4,"widget":true},{"name":"no id"}],"nextCursor":"c2"}');
      expect(page !== null).assertTrue();
      expect(page?.items.length ?? 0).assertEqual(1);
      expect(page?.items[0].widget ?? false).assertTrue();
      expect(page?.items[0].installs ?? 0).assertEqual(4);
      expect(page?.nextCursor ?? '').assertEqual('c2');
      expect(page?.offline ?? true).assertFalse();
      expect(parseMarketList('{"error":{"code":"unavailable","message":"x"}}') === null).assertTrue();
      expect(parseMarketList('<html>') === null).assertTrue();
    });

    it('reads the error shape', 0, () => {
      expect(marketErrorMessage(503, '{"error":{"code":"unavailable","message":"The marketplace is not configured yet."}}'))
        .assertEqual('The marketplace is not configured yet.');
      expect(marketErrorMessage(0, '')).assertEqual("The marketplace didn't answer");
      expect(marketErrorMessage(500, 'oops')).assertEqual('The marketplace answered 500');
    });

    it('offline examples: only valid capsules, category first, searchable', 0, () => {
      const items = libraryItems(LIBRARY);
      expect(items.length).assertEqual(1);
      const tea: MarketItem = items[0];
      expect(tea.id).assertEqual('example:tea');
      expect(tea.tags[0]).assertEqual('timers');
      expect((tea.capsuleJson ?? '').length > 0).assertTrue();
      expect(matchesSearch(tea, 'STEEP', '')).assertTrue();
      expect(matchesSearch(tea, '', 'timers')).assertTrue();
      expect(matchesSearch(tea, '', 'games')).assertFalse();
      expect(matchesSearch(tea, 'pasta', '')).assertFalse();
      expect(libraryItems('not json').length).assertEqual(0);
    });
  });
}
