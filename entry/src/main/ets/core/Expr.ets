/**
 * The schema v1 expression language: a tiny, safe language parsed by our own parser (never eval).
 *
 *   or      := and ("or" and)*
 *   and     := not ("and" not)*
 *   not     := "not" not | cmp
 *   cmp     := add (("==" | "!=" | "<" | "<=" | ">" | ">=") add)?
 *   add     := mul (("+" | "-") mul)*
 *   mul     := unary (("*" | "/" | "%") unary)*
 *   unary   := "-" unary | primary
 *   primary := number | string | "true" | "false" | name | func "(" args ")" | "(" or ")"
 *   func    := if | min | max | round | abs | len
 *
 * Limits: 200 characters, nesting depth 10 (a chain like a + b + c counts once), and a step budget
 * at evaluation time. Pure and deterministic: no clock, no randomness, no I/O.
 */
import { Scalar, Value, VarType } from './CapsuleTypes';

export const MAX_EXPR_LENGTH: number = 200;
export const MAX_EXPR_DEPTH: number = 10;
export const MAX_TEXT_LENGTH: number = 500;
export const MAX_LIST_ITEMS: number = 100;
export const DEFAULT_STEP_BUDGET: number = 10000;
export const KEYWORDS: string[] = ['true', 'false', 'and', 'or', 'not', 'if', 'min', 'max', 'round', 'abs', 'len'];
const FUNCTIONS: string[] = ['if', 'min', 'max', 'round', 'abs', 'len'];
const NAME_RE: RegExp = /^[A-Za-z_][A-Za-z0-9_]{0,31}$/;

/** An expression or evaluation problem. Message is user-facing. */
export class ExprError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ExprError';
  }
}

export function isValidName(name: string): boolean {
  return NAME_RE.test(name) && !KEYWORDS.includes(name);
}

// ---- Lexer ----

type TokenKind = 'num' | 'str' | 'name' | 'op' | 'lparen' | 'rparen' | 'comma' | 'end';

class Token {
  kind: TokenKind;
  text: string;
  num: number = 0;
  pos: number;

  constructor(kind: TokenKind, text: string, pos: number) {
    this.kind = kind;
    this.text = text;
    this.pos = pos;
  }
}

const TWO_CHAR_OPS: string[] = ['==', '!=', '<=', '>='];
const ONE_CHAR_OPS: string = '+-*/%<>';

function tokenize(src: string): Token[] {
  const tokens: Token[] = [];
  let i = 0;
  while (i < src.length) {
    const ch = src.charAt(i);
    if (ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r') {
      i++;
      continue;
    }
    if (ch >= '0' && ch <= '9') {
      const m = src.substring(i).match(/^\d+(\.\d+)?/);
      const text = m === null ? ch : m[0];
      const t = new Token('num', text, i);
      t.num = parseFloat(text);
      tokens.push(t);
      i += text.length;
      continue;
    }
    if (ch === '\'' || ch === '"') {
      let j = i + 1;
      let out = '';
      let closed = false;
      while (j < src.length) {
        const c = src.charAt(j);
        if (c === '\\' && j + 1 < src.length) {
          out += src.charAt(j + 1);
          j += 2;
        } else if (c === ch) {
          closed = true;
          j++;
          break;
        } else {
          out += c;
          j++;
        }
      }
      if (!closed) {
        throw new ExprError(`unterminated text starting at position ${i + 1}`);
      }
      tokens.push(new Token('str', out, i));
      i = j;
      continue;
    }
    if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch === '_') {
      const m = src.substring(i).match(/^[A-Za-z_][A-Za-z0-9_]*/);
      const text = m === null ? ch : m[0];
      tokens.push(new Token('name', text, i));
      i += text.length;
      continue;
    }
    const two = src.substring(i, i + 2);
    if (TWO_CHAR_OPS.includes(two)) {
      tokens.push(new Token('op', two, i));
      i += 2;
      continue;
    }
    if (ch === '=') {
      throw new ExprError(`use == to compare (position ${i + 1})`);
    }
    if (ONE_CHAR_OPS.includes(ch)) {
      tokens.push(new Token('op', ch, i));
      i++;
      continue;
    }
    if (ch === '(') {
      tokens.push(new Token('lparen', ch, i));
    } else if (ch === ')') {
      tokens.push(new Token('rparen', ch, i));
    } else if (ch === ',') {
      tokens.push(new Token('comma', ch, i));
    } else {
      throw new ExprError(`unexpected character "${ch}" at position ${i + 1}`);
    }
    i++;
  }
  tokens.push(new Token('end', '', src.length));
  return tokens;
}

// ---- AST ----

export type NodeKind = 'num' | 'str' | 'bool' | 'name' | 'neg' | 'not' | 'chain' | 'cmp' | 'call';

/** chain: args[0] ops[0] args[1] ops[1] ... at one precedence level: (+ -), (* / %), and, or. */
export class ExprNode {
  kind: NodeKind;
  num: number = 0;
  str: string = '';
  bool: boolean = false;
  name: string = '';
  ops: string[] = [];
  args: ExprNode[] = [];

  constructor(kind: NodeKind) {
    this.kind = kind;
  }
}

function height(n: ExprNode): number {
  let h = 0;
  n.args.forEach((a: ExprNode) => {
    h = Math.max(h, height(a));
  });
  return h + 1;
}

// ---- Parser ----

class Parser {
  private tokens: Token[];
  private i: number = 0;

  constructor(tokens: Token[]) {
    this.tokens = tokens;
  }

  peek(): Token {
    return this.tokens[this.i];
  }

  next(): Token {
    const t = this.tokens[this.i];
    if (this.i < this.tokens.length - 1) {
      this.i++;
    }
    return t;
  }

  isWord(word: string): boolean {
    const t = this.peek();
    return t.kind === 'name' && t.text === word;
  }

  isOp(op: string): boolean {
    const t = this.peek();
    return t.kind === 'op' && t.text === op;
  }

  describe(t: Token): string {
    return t.kind === 'end' ? 'the end' : `"${t.kind === 'str' ? '\'' + t.text + '\'' : t.text}" at position ${t.pos + 1}`;
  }

  parseAll(): ExprNode {
    const node = this.parseOr();
    const t = this.peek();
    if (t.kind !== 'end') {
      throw new ExprError(`unexpected ${this.describe(t)}`);
    }
    return node;
  }

  private chain(ops: string[], words: boolean, sub: () => ExprNode): ExprNode {
    const first = sub();
    const node = new ExprNode('chain');
    node.args.push(first);
    while (true) {
      const t = this.peek();
      const matches = words ? (t.kind === 'name' && ops.includes(t.text)) : (t.kind === 'op' && ops.includes(t.text));
      if (!matches) {
        break;
      }
      this.next();
      node.ops.push(t.text);
      node.args.push(sub());
    }
    return node.ops.length === 0 ? first : node;
  }

  parseOr(): ExprNode {
    return this.chain(['or'], true, () => this.parseAnd());
  }

  parseAnd(): ExprNode {
    return this.chain(['and'], true, () => this.parseNot());
  }

  parseNot(): ExprNode {
    if (this.isWord('not')) {
      this.next();
      const node = new ExprNode('not');
      node.args.push(this.parseNot());
      return node;
    }
    return this.parseCmp();
  }

  parseCmp(): ExprNode {
    const left = this.parseAdd();
    const t = this.peek();
    if (t.kind === 'op' && ['==', '!=', '<', '<=', '>', '>='].includes(t.text)) {
      this.next();
      const node = new ExprNode('cmp');
      node.ops.push(t.text);
      node.args.push(left);
      node.args.push(this.parseAdd());
      const after = this.peek();
      if (after.kind === 'op' && ['==', '!=', '<', '<=', '>', '>='].includes(after.text)) {
        throw new ExprError(`comparisons cannot be chained; use "and" (position ${after.pos + 1})`);
      }
      return node;
    }
    return left;
  }

  parseAdd(): ExprNode {
    return this.chain(['+', '-'], false, () => this.parseMul());
  }

  parseMul(): ExprNode {
    return this.chain(['*', '/', '%'], false, () => this.parseUnary());
  }

  parseUnary(): ExprNode {
    if (this.isOp('-')) {
      this.next();
      const node = new ExprNode('neg');
      node.args.push(this.parseUnary());
      return node;
    }
    return this.parsePrimary();
  }

  parsePrimary(): ExprNode {
    const t = this.next();
    if (t.kind === 'num') {
      const n = new ExprNode('num');
      n.num = t.num;
      return n;
    }
    if (t.kind === 'str') {
      const n = new ExprNode('str');
      n.str = t.text;
      return n;
    }
    if (t.kind === 'lparen') {
      const inner = this.parseOr();
      const close = this.next();
      if (close.kind !== 'rparen') {
        throw new ExprError(`expected ")" but found ${this.describe(close)}`);
      }
      return inner;
    }
    if (t.kind === 'name') {
      if (t.text === 'true' || t.text === 'false') {
        const n = new ExprNode('bool');
        n.bool = t.text === 'true';
        return n;
      }
      if (FUNCTIONS.includes(t.text)) {
        const open = this.next();
        if (open.kind !== 'lparen') {
          throw new ExprError(`${t.text} needs "(" after it (position ${t.pos + 1})`);
        }
        const call = new ExprNode('call');
        call.name = t.text;
        if (this.peek().kind !== 'rparen') {
          call.args.push(this.parseOr());
          while (this.peek().kind === 'comma') {
            this.next();
            call.args.push(this.parseOr());
          }
        }
        const close = this.next();
        if (close.kind !== 'rparen') {
          throw new ExprError(`expected "," or ")" in ${t.text}(...) but found ${this.describe(close)}`);
        }
        return call;
      }
      if (KEYWORDS.includes(t.text)) {
        throw new ExprError(`unexpected "${t.text}" at position ${t.pos + 1}`);
      }
      if (this.peek().kind === 'lparen') {
        throw new ExprError(`unknown function "${t.text}" (allowed: ${FUNCTIONS.join(', ')})`);
      }
      const n = new ExprNode('name');
      n.name = t.text;
      return n;
    }
    throw new ExprError(`unexpected ${this.describe(t)}`);
  }
}

const parseCache: Map<string, ExprNode> = new Map<string, ExprNode>();
const MAX_CACHE: number = 1000;

/** Parses an expression or throws ExprError. Results are cached; treat the node as read-only. */
export function parseExpr(src: string): ExprNode {
  const cached = parseCache.get(src);
  if (cached !== undefined) {
    return cached;
  }
  if (src.trim().length === 0) {
    throw new ExprError('empty expression');
  }
  if (src.length > MAX_EXPR_LENGTH) {
    throw new ExprError(`expression is ${src.length} characters (max ${MAX_EXPR_LENGTH})`);
  }
  const node = new Parser(tokenize(src)).parseAll();
  if (height(node) > MAX_EXPR_DEPTH) {
    throw new ExprError(`expression is nested too deeply (max depth ${MAX_EXPR_DEPTH})`);
  }
  if (parseCache.size >= MAX_CACHE) {
    parseCache.clear();
  }
  parseCache.set(src, node);
  return node;
}

/** Every name an expression reads, in order of first use. */
export function namesIn(node: ExprNode): string[] {
  const out: string[] = [];
  const walk = (n: ExprNode): void => {
    if (n.kind === 'name' && !out.includes(n.name)) {
      out.push(n.name);
    }
    n.args.forEach(walk);
  };
  walk(node);
  return out;
}

// ---- Type checking ----

/** Returns the type of a name, or null if it does not exist. */
export type TypeLookup = (name: string) => VarType | null;

function expectType(actual: VarType, wanted: VarType, what: string): void {
  if (actual !== wanted) {
    throw new ExprError(`${what} must be ${wanted}, got ${actual}`);
  }
}

/** Static type of an expression. Throws ExprError for unknown names or type mismatches. */
export function typeOf(node: ExprNode, lookup: TypeLookup): VarType {
  switch (node.kind) {
    case 'num':
      return 'number';
    case 'str':
      return 'text';
    case 'bool':
      return 'bool';
    case 'name': {
      const t = lookup(node.name);
      if (t === null) {
        throw new ExprError(`unknown name "${node.name}"`);
      }
      return t;
    }
    case 'neg':
      expectType(typeOf(node.args[0], lookup), 'number', 'the value after "-"');
      return 'number';
    case 'not':
      expectType(typeOf(node.args[0], lookup), 'bool', 'the value after "not"');
      return 'bool';
    case 'cmp': {
      const a = typeOf(node.args[0], lookup);
      const b = typeOf(node.args[1], lookup);
      const op = node.ops[0];
      if (op === '==' || op === '!=') {
        if (a === 'list' || b === 'list') {
          throw new ExprError(`lists cannot be compared with ${op}; compare len(...) instead`);
        }
        if (a !== b) {
          throw new ExprError(`cannot compare ${a} with ${b} using ${op}`);
        }
      } else {
        expectType(a, 'number', `the left side of ${op}`);
        expectType(b, 'number', `the right side of ${op}`);
      }
      return 'bool';
    }
    case 'chain': {
      const types = node.args.map((a: ExprNode) => typeOf(a, lookup));
      const op0 = node.ops[0];
      if (op0 === 'and' || op0 === 'or') {
        types.forEach((t: VarType) => expectType(t, 'bool', `each side of "${op0}"`));
        return 'bool';
      }
      if (op0 === '+' || op0 === '-') {
        // Left to right: number + number stays number; once text appears, + concatenates.
        let acc: VarType = types[0];
        node.ops.forEach((op: string, k: number) => {
          const rhs = types[k + 1];
          if (acc === 'list' || rhs === 'list') {
            throw new ExprError(`lists cannot be used with ${op}`);
          }
          if (op === '+' && (acc === 'text' || rhs === 'text')) {
            acc = 'text';
          } else {
            expectType(acc, 'number', `the left side of ${op}`);
            expectType(rhs, 'number', `the right side of ${op}`);
            acc = 'number';
          }
        });
        return acc;
      }
      types.forEach((t: VarType) => expectType(t, 'number', `each side of ${node.ops.join(' ')}`));
      return 'number';
    }
    case 'call':
      return typeOfCall(node, lookup);
    default:
      throw new ExprError('unknown expression');
  }
}

function arity(node: ExprNode, min: number, max: number): void {
  const n = node.args.length;
  if (n < min || n > max) {
    const want = min === max ? `${min}` : `${min} to ${max}`;
    throw new ExprError(`${node.name}() takes ${want} argument${max === 1 ? '' : 's'}, got ${n}`);
  }
}

function typeOfCall(node: ExprNode, lookup: TypeLookup): VarType {
  const types = node.args.map((a: ExprNode) => typeOf(a, lookup));
  switch (node.name) {
    case 'if': {
      arity(node, 3, 3);
      expectType(types[0], 'bool', 'the condition of if()');
      if (types[1] !== types[2]) {
        throw new ExprError(`both branches of if() must have the same type, got ${types[1]} and ${types[2]}`);
      }
      return types[1];
    }
    case 'min':
    case 'max':
      arity(node, 2, 10);
      types.forEach((t: VarType) => expectType(t, 'number', `each argument of ${node.name}()`));
      return 'number';
    case 'round':
      arity(node, 1, 2);
      types.forEach((t: VarType) => expectType(t, 'number', 'each argument of round()'));
      return 'number';
    case 'abs':
      arity(node, 1, 1);
      expectType(types[0], 'number', 'the argument of abs()');
      return 'number';
    case 'len':
      arity(node, 1, 1);
      if (types[0] !== 'list' && types[0] !== 'text') {
        throw new ExprError(`len() needs a list or text, got ${types[0]}`);
      }
      return 'number';
    default:
      throw new ExprError(`unknown function "${node.name}"`);
  }
}

// ---- Evaluation ----

/** Shared step counter for one evaluation pass (e.g. one render or one button press). */
export class StepBudget {
  remaining: number;

  constructor(steps?: number) {
    this.remaining = steps ?? DEFAULT_STEP_BUDGET;
  }

  spend(): void {
    this.remaining--;
    if (this.remaining < 0) {
      throw new ExprError('evaluation took too many steps');
    }
  }
}

/** Returns a name's value, or throws ExprError. */
export type ValueLookup = (name: string) => Value;

export function typeOfValue(v: Value): VarType {
  if (Array.isArray(v)) {
    return 'list';
  }
  if (typeof v === 'number') {
    return 'number';
  }
  if (typeof v === 'boolean') {
    return 'bool';
  }
  return 'text';
}

function num(v: Value): number {
  if (typeof v !== 'number') {
    throw new ExprError(`expected a number, got ${typeOfValue(v)}`);
  }
  return v as number;
}

function bool(v: Value): boolean {
  if (typeof v !== 'boolean') {
    throw new ExprError(`expected true or false, got ${typeOfValue(v)}`);
  }
  return v as boolean;
}

function finite(n: number): number {
  if (!Number.isFinite(n)) {
    throw new ExprError('the result is not a finite number');
  }
  return n;
}

function text(s: string): string {
  if (s.length > MAX_TEXT_LENGTH) {
    throw new ExprError(`text is longer than ${MAX_TEXT_LENGTH} characters`);
  }
  return s;
}

/** How a value is shown: integers plainly, other numbers with up to 2 decimals, lists comma-separated. */
export function formatValue(v: Value): string {
  if (Array.isArray(v)) {
    return (v as Scalar[]).map((x: Scalar) => formatValue(x)).join(', ');
  }
  if (typeof v === 'number') {
    const n = v as number;
    if (Number.isInteger(n)) {
      return n.toString();
    }
    return n.toFixed(2).replace(/\.?0+$/, '');
  }
  if (typeof v === 'boolean') {
    return (v as boolean) ? 'true' : 'false';
  }
  return v as string;
}

function equal(a: Value, b: Value): boolean {
  return typeOfValue(a) === typeOfValue(b) && a === b;
}

/** Evaluates a parsed expression. Throws ExprError on runtime errors or when the budget runs out. */
export function evalExpr(node: ExprNode, lookup: ValueLookup, budget: StepBudget): Value {
  budget.spend();
  switch (node.kind) {
    case 'num':
      return node.num;
    case 'str':
      return node.str;
    case 'bool':
      return node.bool;
    case 'name':
      return lookup(node.name);
    case 'neg':
      return finite(-num(evalExpr(node.args[0], lookup, budget)));
    case 'not':
      return !bool(evalExpr(node.args[0], lookup, budget));
    case 'cmp': {
      const a = evalExpr(node.args[0], lookup, budget);
      const b = evalExpr(node.args[1], lookup, budget);
      switch (node.ops[0]) {
        case '==':
          return equal(a, b);
        case '!=':
          return !equal(a, b);
        case '<':
          return num(a) < num(b);
        case '<=':
          return num(a) <= num(b);
        case '>':
          return num(a) > num(b);
        default:
          return num(a) >= num(b);
      }
    }
    case 'chain':
      return evalChain(node, lookup, budget);
    case 'call':
      return evalCall(node, lookup, budget);
    default:
      throw new ExprError('unknown expression');
  }
}

function evalChain(node: ExprNode, lookup: ValueLookup, budget: StepBudget): Value {
  const op0 = node.ops[0];
  if (op0 === 'and' || op0 === 'or') {
    // Short-circuit.
    for (const arg of node.args) {
      const v = bool(evalExpr(arg, lookup, budget));
      if (op0 === 'and' && !v) {
        return false;
      }
      if (op0 === 'or' && v) {
        return true;
      }
    }
    return op0 === 'and';
  }
  let acc: Value = evalExpr(node.args[0], lookup, budget);
  for (let k = 0; k < node.ops.length; k++) {
    const op = node.ops[k];
    const rhs = evalExpr(node.args[k + 1], lookup, budget);
    if (op === '+' && (typeof acc === 'string' || typeof rhs === 'string')) {
      acc = text(formatValue(acc) + formatValue(rhs));
      continue;
    }
    const a = num(acc);
    const b = num(rhs);
    if ((op === '/' || op === '%') && b === 0) {
      throw new ExprError(op === '/' ? 'division by zero' : 'remainder by zero');
    }
    switch (op) {
      case '+':
        acc = finite(a + b);
        break;
      case '-':
        acc = finite(a - b);
        break;
      case '*':
        acc = finite(a * b);
        break;
      case '/':
        acc = finite(a / b);
        break;
      default:
        acc = finite(a % b);
        break;
    }
  }
  return acc;
}

function evalCall(node: ExprNode, lookup: ValueLookup, budget: StepBudget): Value {
  if (node.name === 'if') {
    const cond = bool(evalExpr(node.args[0], lookup, budget));
    return evalExpr(node.args[cond ? 1 : 2], lookup, budget);
  }
  const vals = node.args.map((a: ExprNode) => evalExpr(a, lookup, budget));
  switch (node.name) {
    case 'min':
      return Math.min(...vals.map((v: Value) => num(v)));
    case 'max':
      return Math.max(...vals.map((v: Value) => num(v)));
    case 'round': {
      const digits = vals.length > 1 ? num(vals[1]) : 0;
      if (!Number.isInteger(digits) || digits < 0 || digits > 6) {
        throw new ExprError('round() digits must be a whole number from 0 to 6');
      }
      const f = Math.pow(10, digits);
      return finite(Math.round(num(vals[0]) * f) / f);
    }
    case 'abs':
      return Math.abs(num(vals[0]));
    case 'len': {
      const v = vals[0];
      if (Array.isArray(v)) {
        return (v as Scalar[]).length;
      }
      if (typeof v === 'string') {
        return (v as string).length;
      }
      throw new ExprError(`len() needs a list or text, got ${typeOfValue(v)}`);
    }
    default:
      throw new ExprError(`unknown function "${node.name}"`);
  }
}

// ---- Templates ----

/** A display template piece: literal text, or an expression source to evaluate. */
export class TemplatePart {
  literal: string = '';
  expr: string = '';
  isExpr: boolean = false;
}

/** Splits "{a} - {b}" into parts. "{{" and "}}" are literal braces. Throws ExprError. */
export function parseTemplate(template: string): TemplatePart[] {
  const parts: TemplatePart[] = [];
  let lit = '';
  let i = 0;
  const flush = (): void => {
    if (lit.length > 0) {
      const p = new TemplatePart();
      p.literal = lit;
      parts.push(p);
      lit = '';
    }
  };
  while (i < template.length) {
    const ch = template.charAt(i);
    if (ch === '{' && template.charAt(i + 1) === '{') {
      lit += '{';
      i += 2;
    } else if (ch === '}' && template.charAt(i + 1) === '}') {
      lit += '}';
      i += 2;
    } else if (ch === '}') {
      throw new ExprError(`unmatched "}" at position ${i + 1}; write "}}" for a literal brace`);
    } else if (ch === '{') {
      // Find the closing brace, skipping quoted text inside the expression.
      let j = i + 1;
      let quote = '';
      while (j < template.length) {
        const c = template.charAt(j);
        if (quote.length > 0) {
          if (c === '\\') {
            j++;
          } else if (c === quote) {
            quote = '';
          }
        } else if (c === '\'' || c === '"') {
          quote = c;
        } else if (c === '}') {
          break;
        }
        j++;
      }
      if (j >= template.length) {
        throw new ExprError(`unclosed "{" at position ${i + 1}`);
      }
      flush();
      const p = new TemplatePart();
      p.expr = template.substring(i + 1, j);
      p.isExpr = true;
      parts.push(p);
      i = j + 1;
    } else {
      lit += ch;
      i++;
    }
  }
  flush();
  return parts;
}
