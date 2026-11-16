// Test-framework adapter only. The pinned upstream test source/assertions are unchanged.
const host = globalThis.__hanlinOriginalTestHost;
export function describe(name, body) { host.suite(name); body(); }
export function it(name, body) {
  const result = body();
  if (result?.then) throw Error('Async upstream tests require a reviewed test contract');
  host.passed(name);
}
export function expect(actual) {
  return {
    toEqual: expected => host.equal(actual, expected),
    toStrictEqual: expected => host.equal(actual, expected),
    toBe: expected => host.identical(actual, expected)
  };
}
