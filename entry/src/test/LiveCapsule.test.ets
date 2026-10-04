import { describe, it, expect } from '@ohos/hypium';
import { HttpResponse, HttpTransport, ModelConfig } from '../main/ets/core/ModelProvider';
import {
  finalText, isToolUnavailable, LIVE_MODEL, LiveCapsuleSource, LivePlan, liveTasksCapsule, needsLiveInfo,
  parseLivePlan, weatherCityIn
} from '../main/ets/core/LiveCapsule';
import { CapsuleSource, generateCapsuleWith, LocalSources, routesLive } from '../main/ets/core/CapsuleGenerator';
import { routeCapsule } from '../main/ets/core/CapsuleRouter';
import { validateCapsule } from '../main/ets/core/CapsuleValidator';
import { parseRequest } from '../main/ets/core/RuleParser';
import { Capsule, CapsuleComponent, DeviceComponent, GenerateResult } from '../main/ets/core/CapsuleTypes';
import {
  applyWidgetMessage, buildWidgetView, declaredAction, GateFacts, initialState, LIST_ROW, parseWidgetMessage,
  summaryLine, WidgetCheckItem, WidgetMessage
} from '../main/ets/core/WidgetModel';

const GOAL: string = 'create a to-do list using the weather in Kraków';
const PLAN: string = '{"name":"Rainy day in Kraków","tasks":["Take an umbrella","Dry laundry indoors",' +
  '"Visit the National Museum"],"summary":"Rain all day: indoor tasks first."}';
const FORECAST: string = '9°C, light rain, wind 14 km/h';

function textBlock(text: string): string {
  return `{"type":"text","text":${JSON.stringify(text)}}`;
}

function messages(blocks: string[]): string {
  return `{"id":"msg_1","type":"message","role":"assistant","content":[${blocks.join(',')}]}`;
}

const SEARCH_USE: string = '{"type":"server_tool_use","id":"srvtoolu_1","name":"web_search","input":{"query":"x"}}';
const SEARCH_ERROR: string =
  '{"type":"web_search_tool_result","tool_use_id":"srvtoolu_1","content":{"type":"web_search_tool_result_error",' +
    '"error_code":"max_uses_exceeded"}}';
const TOOL_400: string =
  '{"type":"error","error":{"type":"invalid_request_error","message":"web_search tool is not enabled"}}';

function anthropic(key: string): ModelConfig {
  return { provider: 'anthropic', apiKey: key, model: 'other', baseUrl: 'https://example.test', timeoutMs: 1000 };
}

/** Replies in order (the last one repeats); counts calls and keeps the bodies; `offline` throws. */
class ScriptedTransport implements HttpTransport {
  calls: number = 0;
  bodies: string[] = [];
  private replies: HttpResponse[];
  private offline: boolean;

  constructor(replies: HttpResponse[], offline?: boolean) {
    this.replies = replies;
    this.offline = offline ?? false;
  }

  async post(url: string, headers: Record<string, string>, body: string, timeoutMs: number): Promise<HttpResponse> {
    this.calls++;
    this.bodies.push(body);
    if (this.offline) {
      throw new Error('offline');
    }
    return this.replies[Math.min(this.calls - 1, this.replies.length - 1)];
  }
}

async function krakowForecast(cityId: string): Promise<string | null> {
  return cityId === 'krakow' ? FORECAST : null;
}

async function noForecast(cityId: string): Promise<string | null> {
  return null;
}

function ok(body: string): HttpResponse {
  return { status: 200, body: body };
}

function capsuleOf(r: GenerateResult): Capsule {
  expect(`${r.ok} ${r.error ?? ''}`).assertEqual('true ');
  return r.capsule as Capsule;
}

function kinds(c: Capsule): string {
  return c.ui.map((x: CapsuleComponent) => x.type).join(',');
}

function gate(): GateFacts {
  return { granted: ['weather'], decided: true, removed: false };
}

/** A live source that records whether it was asked. */
class SpySource implements CapsuleSource {
  asked: number = 0;

  async generate(request: string): Promise<GenerateResult> {
    this.asked++;
    const plan = parseLivePlan(PLAN) as LivePlan;
    return { ok: true, capsule: liveTasksCapsule(plan, 'krakow', true), origin: 'cloud:anthropic', details: [] };
  }
}

export default function liveCapsuleTest() {
  describe('LiveCapsule (T4-23)', () => {
    it('routes live-information requests and nothing else', 0, () => {
      const live: string[] = [GOAL, 'weather in Warsaw', 'what are the latest headlines', 'price of bitcoin',
        'opening hours of the castle', 'look up the train times', 'is it rainy tomorrow'];
      live.forEach((r: string) => expect(`${r}: ${needsLiveInfo(r)}`).assertEqual(`${r}: true`));
      const notLive: string[] = ['timer 10 minutes', 'shopping list', 'count my squats', 'split 84 between 4',
        'pomodoro', 'packing list for camping'];
      notLive.forEach((r: string) => expect(`${r}: ${needsLiveInfo(r)}`).assertEqual(`${r}: false`));
      expect(routesLive(GOAL, { allowNonEu: true })).assertTrue();
      expect(routesLive(GOAL, { allowNonEu: false })).assertFalse();
      expect(routesLive(GOAL, { allowNonEu: true, mode: 'on-device-only' })).assertFalse();
      expect(routesLive(GOAL, { allowNonEu: true, allowCloud: false })).assertFalse();
      expect(routesLive('timer 10 minutes', { allowNonEu: true })).assertFalse();
      expect(weatherCityIn(GOAL)).assertEqual('krakow');
      expect(LIVE_MODEL).assertEqual('claude-haiku-4-5-20251001');
    });

    it('sends the goal to the live source, skipping the rules task list; plain weather stays on rules', 0,
      async (done: Function) => {
        const spy = new SpySource();
        const local: LocalSources = { live: spy };
        const r = await generateCapsuleWith(GOAL, [], '', null, { allowNonEu: true }, local);
        expect(spy.asked).assertEqual(1);
        expect(r.origin).assertEqual('cloud:anthropic');
        const plain = await generateCapsuleWith('weather in Kraków', [], '', null, { allowNonEu: true }, local);
        expect(`${plain.origin} ${spy.asked}`).assertEqual('rules 1');
        const eu = await generateCapsuleWith(GOAL, [], '', null, { allowNonEu: false }, local);
        expect(`${eu.origin === 'cloud:anthropic'} ${spy.asked}`).assertEqual('false 1'); // EU only: never Claude
        const other = await generateCapsuleWith('count my squats', [], '', null, { allowNonEu: true }, local);
        expect(`${other.origin} ${spy.asked}`).assertEqual('rules 1');
        done();
      });

    it('reads only the final text block and reports a search error inside a 200', 0, () => {
      const r = finalText(messages([textBlock('Let me search.'), SEARCH_USE,
        '{"type":"web_search_tool_result","tool_use_id":"srvtoolu_1","content":[]}', textBlock(PLAN)]));
      expect(r.text).assertEqual(PLAN);
      expect(r.searchError).assertEqual('');
      const e = finalText(messages([SEARCH_USE, SEARCH_ERROR, textBlock(PLAN)]));
      expect(e.text).assertEqual(PLAN);
      expect(e.searchError).assertEqual('max_uses_exceeded');
      expect(finalText('not json').text).assertEqual('');
      expect(isToolUnavailable({ status: 400, body: TOOL_400 })).assertTrue();
      expect(isToolUnavailable({ status: 400, body: '{"error":{"message":"max_tokens too big"}}' })).assertFalse();
      expect(isToolUnavailable({ status: 500, body: TOOL_400 })).assertFalse();
    });

    it('puts the forecast in the prompt (no search) and builds the rules "Tasks and weather" shape', 0,
      async (done: Function) => {
        const t = new ScriptedTransport([ok(messages([textBlock(PLAN)]))]);
        const c = capsuleOf(await new LiveCapsuleSource(anthropic('k'), t, krakowForecast).generate(GOAL));
        expect(t.calls).assertEqual(1);
        expect(t.bodies[0].includes(FORECAST)).assertTrue();
        expect(t.bodies[0].includes('web_search')).assertFalse();
        expect(t.bodies[0].includes(LIVE_MODEL)).assertTrue();
        const rulesShape = parseRequest('task list and weather in Kraków') as Capsule;
        expect(kinds(c).replace(',text', '')).assertEqual(kinds(rulesShape));
        expect((c.ui[0] as DeviceComponent).city).assertEqual('krakow');
        expect(c.permissions.join()).assertEqual('weather');
        expect(JSON.stringify(c).includes('Take an umbrella')).assertTrue();
        expect(validateCapsule(JSON.stringify(c)).ok).assertTrue();
        done();
      });

    it('handles a search error inside a 200 and retries once without the tool on a 400', 0, async (done: Function) => {
      const searched = new ScriptedTransport([ok(messages([SEARCH_USE, SEARCH_ERROR, textBlock(PLAN)]))]);
      const r = await new LiveCapsuleSource(anthropic('k'), searched, noForecast).generate(GOAL);
      expect(capsuleOf(r).name).assertEqual('Rainy day in Kraków');
      expect(searched.bodies[0].includes('web_search_20250305')).assertTrue();
      expect(r.details.join().includes('max_uses_exceeded')).assertTrue();

      const retry = new ScriptedTransport([{ status: 400, body: TOOL_400 }, ok(messages([textBlock(PLAN)]))]);
      capsuleOf(await new LiveCapsuleSource(anthropic('k'), retry, noForecast).generate(GOAL));
      expect(retry.calls).assertEqual(2);
      expect(retry.bodies[0].includes('web_search')).assertTrue();
      expect(retry.bodies[1].includes('web_search')).assertFalse();

      const bad = new ScriptedTransport([{ status: 400, body: '{"error":{"message":"bad max_tokens"}}' }]);
      const b = await new LiveCapsuleSource(anthropic('k'), bad, noForecast).generate(GOAL);
      expect(`${bad.calls} ${b.origin}`).assertEqual('1 rules'); // no retry for other 400s: the fallback
      done();
    });

    it('falls back to the rules "Tasks and weather" capsule without a key or network', 0, async (done: Function) => {
      const t = new ScriptedTransport([ok(messages([textBlock(PLAN)]))]);
      const noKey = await new LiveCapsuleSource(null, t, krakowForecast).generate(GOAL);
      expect(`${noKey.origin} ${t.calls}`).assertEqual('rules 0');
      const rulesShape = parseRequest('task list and weather in Kraków') as Capsule;
      expect(JSON.stringify(capsuleOf(noKey).ui)).assertEqual(JSON.stringify(rulesShape.ui));
      const offline = new ScriptedTransport([], true);
      const o = await new LiveCapsuleSource(anthropic('k'), offline, krakowForecast).generate(GOAL);
      expect(o.origin).assertEqual('rules');
      expect(o.details.join().includes('no network')).assertTrue();
      const empty = new ScriptedTransport([ok(messages([textBlock('Sorry, no idea.')]))]);
      expect((await new LiveCapsuleSource(anthropic('k'), empty, krakowForecast).generate(GOAL)).origin)
        .assertEqual('rules');
      const news = await new LiveCapsuleSource(null, t, noForecast).generate('latest news headlines');
      expect(news.ok).assertFalse(); // no rules answer for news: a clear error
      done();
    });

    it('puts the live task list on a widget; tapping a task finishes it', 0, () => {
      const c = liveTasksCapsule(parseLivePlan(PLAN) as LivePlan, 'krakow', true);
      const route = routeCapsule(c);
      expect(`${route.widget} ${route.reason}`).assertEqual('true Widget: a task list (add tasks in the app).');
      expect(routeCapsule(parseRequest('task list and weather in Kraków') as Capsule).widget).assertTrue();
      expect(routeCapsule(parseRequest('weather in Kraków') as Capsule).widget).assertFalse();
      expect(routeCapsule(parseRequest('split 84 between 4') as Capsule).condensed).assertTrue();
      const v = buildWidgetView(c, initialState(c), gate(), 0, false);
      expect(`${v.status} ${v.layout} ${v.caption}`).assertEqual('ok checklist Tasks to do: 3');
      expect(v.rows.length).assertEqual(1);
      expect(v.rows[0].open.map((i: WidgetCheckItem) => i.text).join('|'))
        .assertEqual('Take an umbrella|Dry laundry indoors|Visit the National Museum');
      expect(v.buttons.length).assertEqual(0); // "Add" needs typing: app only
      expect(summaryLine(v, 0)).assertEqual('3 to do');
      const tap = parseWidgetMessage(`{"op":"toggle","id":"${LIST_ROW}tasks","index":0}`) as WidgetMessage;
      expect(declaredAction(c, tap)).assertEqual('');
      const next = applyWidgetMessage(c, initialState(c), tap, 0);
      const after = buildWidgetView(c, next, gate(), 0, false);
      expect(after.caption).assertEqual('Tasks to do: 2');
      expect(after.rows[0].open.map((i: WidgetCheckItem) => i.text).join('|')).assertEqual('Dry laundry indoors|Visit the National Museum');
      const wrong = parseWidgetMessage(`{"op":"toggle","id":"${LIST_ROW}nope","index":0}`) as WidgetMessage;
      expect(declaredAction(c, wrong) === null).assertTrue();
    });
  });
}
