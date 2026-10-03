import { describe, it, expect } from '@ohos/hypium';
import { Capsule } from '../main/ets/core/CapsuleTypes';
import { validateCapsule } from '../main/ets/core/CapsuleValidator';
import {
  exportCapsuleJson,
  MAX_SHARE_BYTES,
  onImported,
  PreparedImport,
  prepareImport,
  utf8ByteLength
} from '../main/ets/sharing/CapsuleShare';

function times(unit: string, count: number): string {
  let out: string = '';
  for (let i = 0; i < count; i++) {
    out += unit;
  }
  return out;
}

function capsuleJson(id: string, name: string, text: string): string {
  return `{"schemaVersion":0,"id":"${id}","name":"${name}","permissions":[],` +
    `"ui":[{"type":"text","text":${JSON.stringify(text)}}]}`;
}

function errorOf(json: string): string {
  const r = prepareImport(json);
  expect(r.ok).assertFalse();
  return r.error ?? '';
}

export default function sharingTest() {
  describe('Sharing', () => {
    it('measures UTF-8 bytes, not string length', 0, () => {
      expect(utf8ByteLength('a')).assertEqual(1);
      expect(utf8ByteLength('é')).assertEqual(2);
      expect(utf8ByteLength('😀')).assertEqual(4);
    });

    it('imports a valid capsule and gives it a new id', 0, () => {
      const r = prepareImport(capsuleJson('pasta', 'Pasta night', 'Dinner'));
      expect(r.ok).assertTrue();
      expect(r.capsule?.name).assertEqual('Pasta night');
      expect(r.capsule?.id === 'pasta').assertFalse();
      expect((r.capsule?.id ?? '').startsWith('imported-')).assertTrue();
      expect(r.json ?? '').assertContain('"id":"imported-');
    });

    it('accepts a file of exactly 8 KB and rejects one byte more', 0, () => {
      const base: string = capsuleJson('cap', 'Cap', '');
      const pad: number = MAX_SHARE_BYTES - utf8ByteLength(base);
      const exact: string = capsuleJson('cap', 'Cap', times('a', pad));
      expect(utf8ByteLength(exact)).assertEqual(MAX_SHARE_BYTES);
      expect(prepareImport(exact).ok).assertTrue();
      expect(prepareImport(capsuleJson('cap', 'Cap', times('a', pad + 1))).ok).assertFalse();
    });

    it('rejects an oversized ASCII file with the size message', 0, () => {
      expect(errorOf(capsuleJson('big', 'Big', times('a', 9000))))
        .assertContain('File too large (max 8 KB)');
    });

    it('rejects an oversized file whose string length is under 8 KB (multi-byte)', 0, () => {
      const json: string = capsuleJson('big', 'Big', times('😀', 2100));
      expect(json.length < MAX_SHARE_BYTES).assertTrue();
      expect(utf8ByteLength(json) > MAX_SHARE_BYTES).assertTrue();
      expect(errorOf(json)).assertContain('File too large (max 8 KB)');
    });

    it('rejects empty text', 0, () => {
      expect(errorOf('')).assertContain('empty');
      expect(errorOf('   ')).assertContain('empty');
    });

    it('rejects random text and truncated JSON', 0, () => {
      expect(errorOf('hello, this is not a capsule')).assertContain('not valid JSON');
      expect(errorOf('{"schemaVersion":0,"id":')).assertContain('not valid JSON');
    });

    it('rejects schema-invalid capsules with the validator message', 0, () => {
      expect(errorOf('{"schemaVersion":0,"id":"x","name":"X","permissions":[],"ui":[],"script":"alert(1)"}'))
        .assertContain('unknown field "script"');
      expect(errorOf('{"schemaVersion":0,"id":"x","name":"X","permissions":["camera"],"ui":[]}'))
        .assertContain('unknown permission "camera"');
    });

    it('carries no grants over: extra fields are rejected and the capsule keeps only schema fields', 0, () => {
      expect(errorOf('{"schemaVersion":0,"id":"x","name":"X","permissions":[],"ui":[],"grants":["reminders"]}'))
        .assertContain('unknown field "grants"');
      const r = prepareImport(capsuleJson('cap', 'Cap', 'hi'));
      expect(r.ok).assertTrue();
      const keys: string[] = Object.keys(r.capsule as Capsule).sort();
      expect(keys.join(',')).assertEqual('id,name,permissions,schemaVersion,ui');
    });

    it('round-trips export then import: same name and ui, different id', 0, () => {
      const original: Capsule = validateCapsule(capsuleJson('pasta', 'Pasta night', 'Dinner 7pm')).capsule as Capsule;
      const reimported = prepareImport(exportCapsuleJson(original));
      expect(reimported.ok).assertTrue();
      const capsule: Capsule = reimported.capsule as Capsule;
      expect(capsule.name).assertEqual(original.name);
      expect(JSON.stringify(capsule.ui)).assertEqual(JSON.stringify(original.ui));
      expect(capsule.id === original.id).assertFalse();
      expect(reimported.json).assertEqual(exportCapsuleJson(capsule));
    });

    it('onImported hands over only a successful import', 0, () => {
      let delivered: number = 0;
      let deliveredName: string = '';
      const handedBad: boolean = onImported(prepareImport('nope'), (p: PreparedImport) => {
        delivered++;
      });
      expect(handedBad).assertFalse();
      const handedGood: boolean = onImported(prepareImport(capsuleJson('cap', 'Cap', 'hi')), (p: PreparedImport) => {
        delivered++;
        deliveredName = p.capsule.name;
      });
      expect(handedGood).assertTrue();
      expect(delivered).assertEqual(1);
      expect(deliveredName).assertEqual('Cap');
    });
  });
}
