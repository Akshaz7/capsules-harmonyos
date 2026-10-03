import { describe, it, expect } from '@ohos/hypium';
import {
  evalExpr, ExprError, formatValue, isValidName, parseExpr, parseTemplate, StepBudget, TemplatePart, typeOf
} from '../main/ets/core/Expr';
import { Value, VarType } from '../main/ets/core/CapsuleTypes';

const VALUES: Record<string, Value> = {};
VALUES['a'] = 7;
VALUES['b'] = 2;
VALUES['name'] = 'Ash';
VALUES['on'] = true;
VALUES['off'] = false;
VALUES['items'] = ['milk', 'eggs'];
VALUES['zero'] = 0;

function lookupType(n: string): VarType | null {
  const v = VALUES[n];
  if (v === undefined) {
    return null;
  }
  return Array.isArray(v) ? 'list' : (typeof v === 'number' ? 'number' : (typeof v === 'boolean' ? 'bool' : 'text'));
}

function run(src: string): Value {
  return evalExpr(parseExpr(src), (n: string) => VALUES[n], new StepBudget());
}

function parseError(src: string): string {
  try {
    parseExpr(src);
    return '';
  } catch (e) {
    return (e as ExprError).message;
  }
}

function typeError(src: string): string {
  try {
    typeOf(parseExpr(src), lookupType);
    return '';
  } catch (e) {
    return (e as ExprError).message;
  }
}

function runError(src: string): string {
  try {
    run(src);
    return '';
  } catch (e) {
    return (e as ExprError).message;
  }
}

export default function exprTest() {
  describe('Expr', () => {
    it('evaluates literals and arithmetic with precedence', 0, () => {
      expect(run('1 + 2 * 3')).assertEqual(7);
      expect(run('(1 + 2) * 3')).assertEqual(9);
      expect(run('10 - 4 - 3')).assertEqual(3);
      expect(run('a % b')).assertEqual(1);
      expect(run('-a + 10')).assertEqual(3);
      expect(run('7 / 2')).assertEqual(3.5);
    });

    it('concatenates text with +', 0, () => {
      expect(run('"Hi " + name')).assertEqual('Hi Ash');
      expect(run("'Score: ' + a + '-' + b")).assertEqual('Score: 7-2');
      expect(run('a + b + " pts"')).assertEqual('9 pts');
    });

    it('compares and combines with and/or/not', 0, () => {
      expect(run('a > b and not off')).assertEqual(true);
      expect(run('a == 7 or zero == 1')).assertEqual(true);
      expect(run('name != "Ash"')).assertEqual(false);
      expect(run('a <= 6')).assertEqual(false);
    });

    it('short-circuits and/or', 0, () => {
      // The right side would divide by zero if evaluated.
      expect(run('off and a / zero > 1')).assertEqual(false);
      expect(run('on or a / zero > 1')).assertEqual(true);
    });

    it('runs if, min, max, round, abs and len', 0, () => {
      expect(run("if(a > b, 'A', 'B')")).assertEqual('A');
      expect(run('min(a, b, 5)')).assertEqual(2);
      expect(run('max(a, b)')).assertEqual(7);
      expect(run('round(10 / 3, 2)')).assertEqual(3.33);
      expect(run('round(2.5)')).assertEqual(3);
      expect(run('abs(b - a)')).assertEqual(5);
      expect(run('len(items)')).assertEqual(2);
      expect(run('len(name)')).assertEqual(3);
    });

    it('rejects syntax errors with clear messages', 0, () => {
      expect(parseError('a = 1')).assertContain('use == to compare');
      expect(parseError('1 +')).assertContain('unexpected the end');
      expect(parseError('(1 + 2')).assertContain('expected ")"');
      expect(parseError('sqrt(4)')).assertContain('unknown function "sqrt"');
      expect(parseError('a < b < 3')).assertContain('cannot be chained');
      expect(parseError("'open")).assertContain('unterminated text');
      expect(parseError('a $ b')).assertContain('unexpected character "$"');
      expect(parseError('')).assertContain('empty expression');
    });

    it('enforces the 200 character and depth 10 limits', 0, () => {
      expect(parseError('1' + ' + 1'.repeat(60))).assertContain('max 200');
      expect(parseError('1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1')).assertEqual(''); // a chain counts once
      expect(parseError('abs(abs(abs(abs(abs(abs(abs(abs(abs(abs(1))))))))))')).assertContain('nested too deeply');
      expect(parseError('abs(abs(abs(abs(abs(abs(abs(abs(1))))))))')).assertEqual('');
    });

    it('type-checks names, operators and function arguments', 0, () => {
      expect(typeError('a + b')).assertEqual('');
      expect(typeError('missing + 1')).assertContain('unknown name "missing"');
      expect(typeError('a and on')).assertContain('must be bool, got number');
      expect(typeError('name < 3')).assertContain('must be number, got text');
      expect(typeError("if(on, 1, 'x')")).assertContain('same type');
      expect(typeError('if(a, 1, 2)')).assertContain('condition of if() must be bool');
      expect(typeError('len(a)')).assertContain('needs a list or text');
      expect(typeError('items + 1')).assertContain('lists cannot be used');
      expect(typeError('a == name')).assertContain('cannot compare number with text');
      expect(typeError('min(a)')).assertContain('takes 2 to 10 arguments');
    });

    it('reports runtime errors instead of producing NaN or Infinity', 0, () => {
      expect(runError('a / zero')).assertEqual('division by zero');
      expect(runError('a % zero')).assertEqual('remainder by zero');
      expect(runError('round(a, 9)')).assertContain('0 to 6');
    });

    it('stops runaway evaluation with the step budget', 0, () => {
      const node = parseExpr('a + a + a + a + a');
      let message = '';
      try {
        evalExpr(node, (n: string) => VALUES[n], new StepBudget(3));
      } catch (e) {
        message = (e as ExprError).message;
      }
      expect(message).assertContain('too many steps');
    });

    it('formats values for display', 0, () => {
      expect(formatValue(21)).assertEqual('21');
      expect(formatValue(33.3333)).assertEqual('33.33');
      expect(formatValue(2.5)).assertEqual('2.5');
      expect(formatValue(true)).assertEqual('true');
      expect(formatValue(['a', 1])).assertEqual('a, 1');
    });

    it('parses display templates', 0, () => {
      const parts = parseTemplate("{p1} - {p2} {{braces}} {if(on, '}', 'x')}");
      expect(parts.map((p: TemplatePart) => p.isExpr ? `[${p.expr}]` : p.literal).join(''))
        .assertEqual("[p1] - [p2] {braces} [if(on, '}', 'x')]");
      let message = '';
      try {
        parseTemplate('{a');
      } catch (e) {
        message = (e as ExprError).message;
      }
      expect(message).assertContain('unclosed "{"');
    });

    it('checks names', 0, () => {
      expect(isValidName('p1')).assertTrue();
      expect(isValidName('_tip')).assertTrue();
      expect(isValidName('1p')).assertFalse();
      expect(isValidName('if')).assertFalse();
      expect(isValidName('a-b')).assertFalse();
    });
  });
}
