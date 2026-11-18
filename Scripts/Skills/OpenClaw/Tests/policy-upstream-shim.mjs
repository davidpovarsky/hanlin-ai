// Framework/fixture adapter only. Every retained original test statement is byte-identical.
import assert from 'node:assert/strict';
import { setActiveDegradedSecretOwners } from '../generated/policy.mjs';
export const results = { suites: [], cases: [], assertions: 0 };
const initialPlatform = Object.getOwnPropertyDescriptor(process, 'platform');
export function mockProcessPlatform(value) {
  Object.defineProperty(process, 'platform', { configurable: true, enumerable: true, value });
}
export function describe(name, body) { results.suites.push(name); body(); }
export function it(name, body) {
  setActiveDegradedSecretOwners([]);
  try {
    const value = body();
    if (value?.then) throw Error('Async original test requires a reviewed adapter');
    results.cases.push(name);
  } finally {
    setActiveDegradedSecretOwners([]);
    Object.defineProperty(process, 'platform', initialPlatform);
  }
}
it.each = rows => (name, body) => rows.forEach(row => it(name.replace('%j', JSON.stringify(row)), () => body(row)));
export const test = it;
export function expectDefined(value, message) { assert.notEqual(value, undefined, message); return value; }
export function expect(actual) {
  return {
    toBe(expected) { results.assertions++; assert.equal(actual, expected); },
    toEqual(expected) { results.assertions++; assert.deepEqual(actual, expected); },
    toStrictEqual(expected) { results.assertions++; assert.deepEqual(actual, expected); },
    toBeUndefined() { results.assertions++; assert.equal(actual, undefined); }
  };
}
