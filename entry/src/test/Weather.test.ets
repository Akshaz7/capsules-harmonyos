import { describe, it, expect } from '@ohos/hypium';
import { validateCapsule } from '../main/ets/core/CapsuleValidator';
import { routeCapsule } from '../main/ets/core/CapsuleRouter';
import { parseRequest } from '../main/ets/core/RuleParser';
import { Capsule, CapsuleComponent, DeviceComponent, StateVar } from '../main/ets/core/CapsuleTypes';
import {
  CITIES, City, cityById, cityIdFromText, cityName, parseOpenMeteo, WeatherReading, weatherLabel, weatherSymbolKey,
  weatherValue
} from '../main/ets/capabilities/WeatherData';
import {
  Capability, generatorCapabilitiesText, implementedCapabilities
} from '../main/ets/capabilities/CapabilityRegistry';

const GOOD: string = '{"latitude":50.06,"longitude":19.94,"current_units":{"temperature_2m":"°C"},' +
  '"current":{"time":"2026-10-04T00:45","interval":900,"temperature_2m":11.3,"weather_code":1,"wind_speed_10m":3.6}}';

function errorsOf(json: string): string {
  return validateCapsule(json).errors.join(' | ');
}

function weatherCapsule(permissions: string, extra: string): string {
  return `{"schemaVersion":1,"id":"w","name":"W","permissions":${permissions},"ui":` +
    `[{"type":"device","bind":"weather"${extra}}]}`;
}

function built(req: string): Capsule {
  const c = parseRequest(req);
  expect(c !== null).assertTrue();
  return c as Capsule;
}

export default function weatherTest() {
  describe('Weather (Open-Meteo capability)', () => {
    it('bundles a small curated city list with unique ids and sane coordinates', 0, () => {
      expect(CITIES.length).assertEqual(12);
      const ids = new Set<string>();
      CITIES.forEach((c: City) => {
        ids.add(c.id);
        expect(c.latitude >= -90 && c.latitude <= 90).assertTrue();
        expect(c.longitude >= -180 && c.longitude <= 180).assertTrue();
      });
      expect(ids.size).assertEqual(12);
      expect(cityById('krakow') !== undefined).assertTrue();
      expect(cityName('krakow')).assertEqual('Kraków');
    });

    it('matches city names with or without Polish diacritics', 0, () => {
      expect(cityIdFromText('krakow')).assertEqual('krakow');
      expect(cityIdFromText('Kraków')).assertEqual('krakow');
      expect(cityIdFromText(' Łódź ')).assertEqual('lodz');
      expect(cityIdFromText('atlantis')).assertEqual('');
    });

    it('parses a real Open-Meteo body and refuses anything unexpected', 0, () => {
      const r = parseOpenMeteo(GOOD, 1234);
      expect(r === null).assertFalse();
      expect(Math.round((r as WeatherReading).tempC * 10)).assertEqual(113);
      expect(parseOpenMeteo('{}', 1) === null).assertTrue();
      expect(parseOpenMeteo('{"current":{"temperature_2m":"warm","weather_code":1,"wind_speed_10m":3}}', 1) === null)
        .assertTrue();
      expect(parseOpenMeteo('{"current":{"temperature_2m":11,"weather_code":100,"wind_speed_10m":3}}', 1) === null)
        .assertTrue();
      expect(parseOpenMeteo('x'.repeat(9000), 1) === null).assertTrue();
      expect(parseOpenMeteo('not json', 1) === null).assertTrue();
    });

    it('labels WMO codes and picks a symbol bucket', 0, () => {
      expect(weatherLabel(0)).assertEqual('Clear');
      expect(weatherLabel(3)).assertEqual('Overcast');
      expect(weatherLabel(61)).assertEqual('Rain');
      expect(weatherLabel(75)).assertEqual('Snow');
      expect(weatherLabel(95)).assertEqual('Thunderstorm');
      expect(weatherSymbolKey(0)).assertEqual('sun');
      expect(weatherSymbolKey(2)).assertEqual('partly');
      expect(weatherSymbolKey(61)).assertEqual('rain');
      expect(weatherSymbolKey(75)).assertEqual('snow');
      expect(weatherSymbolKey(95)).assertEqual('storm');
      expect(weatherValue({ tempC: 11.3, code: 2, windKmh: 3.6, fetchedAt: 1 }))
        .assertEqual('11°C · Partly cloudy · Wind 4 km/h');
    });

    it('validates a weather reading: permission, bundled city, one per capsule', 0, () => {
      expect(validateCapsule(weatherCapsule('["weather"]', ', "city": "krakow"')).ok).assertTrue();
      expect(validateCapsule(weatherCapsule('["weather"]', '')).ok).assertTrue();
      expect(errorsOf(weatherCapsule('[]', ', "city": "krakow"'))).assertContain('needs permission "weather"');
      expect(errorsOf(weatherCapsule('["weather"]', ', "city": "atlantis"'))).assertContain('bundled city id');
      const two = '{"schemaVersion":1,"id":"w","name":"W","permissions":["weather"],"ui":' +
        '[{"type":"device","bind":"weather"},{"type":"device","bind":"weather"}]}';
      expect(errorsOf(two)).assertContain('max 1');
    });

    it('builds "weather in Kraków" and "weather" without a model, and keeps them in the app', 0, () => {
      const named = parseRequest('weather in Kraków') as Capsule;
      expect(named === null).assertFalse();
      expect(named.permissions.join()).assertEqual('weather');
      const comp = named.ui[0] as DeviceComponent;
      expect(comp.bind).assertEqual('weather');
      expect(comp.city).assertEqual('krakow');
      expect(validateCapsule(JSON.stringify(named)).ok).assertTrue();
      expect(routeCapsule(named).widget).assertFalse();
      const cityFirst = parseRequest('paris weather') as Capsule;
      expect((cityFirst.ui[0] as DeviceComponent).city).assertEqual('paris');
      const plain = parseRequest('weather') as Capsule;
      expect((plain.ui[0] as DeviceComponent).city === undefined).assertTrue();
    });

    it('advertises only implemented capabilities to the generator', 0, () => {
      const ids = implementedCapabilities().map((c: Capability) => c.id);
      expect(ids.join()).assertEqual('motion,battery,weather');
      const text = generatorCapabilitiesText();
      expect(text.includes('motion')).assertTrue();
      expect(text.includes('battery')).assertTrue();
      expect(text.includes('weather')).assertTrue();
      expect(text.includes('gyroscope')).assertFalse();
      expect(text.includes('pedometer')).assertFalse();
    });

    it('builds a task list with the weather in one capsule, by rule', 0, () => {
      const inputs: string[] = [
        'a task list and the weather for Kraków',
        'task list and weather',
        'todo list with today\'s weather',
        'weather in Warsaw and a to-do list'
      ];
      inputs.forEach((req: string) => {
        const c = built(req);
        expect(validateCapsule(JSON.stringify(c)).errors.join(' | ')).assertEqual('');
        expect(`${req} -> ${c.permissions.join()}`).assertEqual(`${req} -> weather`);
        const wx = c.ui.find((x: CapsuleComponent) => x.type === 'device') as DeviceComponent;
        expect(wx === undefined).assertFalse();
        expect(wx.bind).assertEqual('weather');
        const hasList: boolean = c.ui.some((x: CapsuleComponent) => x.type === 'list');
        expect(`${req} list ${hasList}`).assertEqual(`${req} list true`);
        expect(c.state !== undefined).assertTrue();
        expect((c.state as Record<string, StateVar>)['tasks'] !== undefined).assertTrue();
        expect(routeCapsule(c).widget).assertFalse();
      });
      const named = built('a task list and the weather for Kraków');
      expect((named.ui.find((x: CapsuleComponent) => x.type === 'device') as DeviceComponent).city)
        .assertEqual('krakow');
      expect(named.name).assertContain('Kraków');
      const unnamed = built('task list and weather');
      expect((unnamed.ui.find((x: CapsuleComponent) => x.type === 'device') as DeviceComponent).city === undefined)
        .assertTrue();
      expect(unnamed.name).assertEqual('Tasks and weather');
    });

    it('no longer swallows unknown city-first requests, and still takes a real city', 0, () => {
      expect(parseRequest('nice weather') === null).assertTrue();
      expect(parseRequest('task list and weather') !== null).assertTrue();
      const paris = built('paris weather');
      expect((paris.ui[0] as DeviceComponent).city).assertEqual('paris');
    });
  });
}
