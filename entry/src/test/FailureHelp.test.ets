import { describe, it, expect } from '@ohos/hypium';
import { Alternative, allAlternatives, cantBuild, CLOUD_EXPLAINER, failureHelp } from '../main/ets/core/FailureHelp';
import { GenerateOptions, generateCapsuleWith, routesLive } from '../main/ets/core/CapsuleGenerator';
import { validateCapsule } from '../main/ets/core/CapsuleValidator';
import { Capsule } from '../main/ets/core/CapsuleTypes';
import { matchTemplate } from '../main/ets/core/templates/index';

export default function failureHelpTest() {
  describe('Failure card help (T4-30)', () => {
    it('says why in one line for news, payments, other apps and live prices', 0, () => {
      expect(failureHelp('Build a news widget that gives me latest info in the mornings').reason)
        .assertEqual("Capsules can't fetch live news yet.");
      expect(failureHelp('pay my rent every month').reason).assertEqual("Capsules can't make payments.");
      expect(failureHelp('open spotify when I start running').reason).assertEqual("Capsules can't control other apps.");
      expect(failureHelp('bitcoin price tracker').reason).assertEqual("Capsules can't fetch live prices yet.");
    });

    it('offers one related alternative; nothing for an ordinary failed request', 0, () => {
      const news = failureHelp('Build a news widget that gives me latest info in the mornings').alternative as Alternative;
      expect(news.label).assertEqual('Task list with the weather for Kraków');
      const plain = failureHelp('a quiz about dinosaurs with confetti');
      expect(`${plain.reason}|${plain.alternative === null}`).assertEqual('|true');
    });

    it('every alternative builds on the phone (no cloud) and validates', 0, async (done: Function) => {
      for (const a of allAlternatives()) {
        // The app tries a strong template match first (Index), then the generator without the cloud.
        const m = matchTemplate(a.request);
        const r = await generateCapsuleWith(a.request, [], '', null);
        const c: Capsule | undefined = m !== null ? m.capsule : r.capsule;
        expect(`${a.request}: ${c !== undefined}`).assertEqual(`${a.request}: true`);
        expect(validateCapsule(JSON.stringify(c as Capsule)).errors.join(' | ')).assertEqual('');
      }
      done();
    });

    it('live news is refused before any model, and never routed live', 0, async (done: Function) => {
      const news = 'Build a news widget that gives me latest info in the mornings';
      expect(cantBuild(news)).assertTrue();
      expect(cantBuild('pay my rent')).assertFalse(); // only shown on failure, not refused up front
      expect(cantBuild('a task list and the weather for Krakow')).assertFalse();
      const smart: GenerateOptions = { mode: 'smart', allowNonEu: true };
      expect(routesLive(news, smart)).assertFalse();
      expect(routesLive('a task list and the weather for Krakow', smart)).assertTrue();
      const r = await generateCapsuleWith(news, [], '', null);
      expect(`${r.ok} ${r.failure}`).assertEqual('false cant-build');
      done();
    });

    it('uses the agreed wording, never "off by default" or "EU cloud"', 0, () => {
      expect(CLOUD_EXPLAINER).assertEqual('Most requests are built on the phone. When one needs a cloud model, ' +
        'the app names the provider first, which may be outside the EU.');
      expect(CLOUD_EXPLAINER.includes('off by default') || CLOUD_EXPLAINER.includes('EU cloud')).assertFalse();
    });
  });
}
