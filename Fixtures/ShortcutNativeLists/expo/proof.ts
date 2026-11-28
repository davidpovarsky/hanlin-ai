export type Scalar = string | number | boolean;
export type JSONValue = null | Scalar | JSONValue[] | {[key: string]: JSONValue};

// Inspect the real received value; the fixture never knows a test's expected
// list or declared Int/Double mode. Native canonical tags are checked outside JS.
export function receivedList(input: unknown): Scalar[] {
  if (!Array.isArray(input) || input.length > 32) throw new Error('Expected a bounded native list.');
  return input.map((value: unknown) => {
    if (typeof value === 'string' || typeof value === 'boolean') return value;
    if (typeof value === 'number' && Number.isFinite(value)) return value;
    throw new Error('The actual list contains a non-scalar or non-finite value.');
  });
}
