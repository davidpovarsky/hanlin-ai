// The original React DatePicker stores real JavaScript Dates. Preserve that
// type across the existing JSON message snapshot, native controls and reload.
export const dateTag = '__hanlinOpenUIDate';
export function encodeState(value) {
  if (value instanceof Date) return Number.isFinite(value.getTime()) ? { [dateTag]: value.toISOString() } : null;
  if (Array.isArray(value)) return value.map(encodeState);
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([key, child]) => [key, encodeState(child)]));
  return value ?? null;
}
export function decodeState(value) {
  if (Array.isArray(value)) return value.map(decodeState);
  if (value && typeof value === 'object') {
    if (Object.keys(value).length === 1 && typeof value[dateTag] === 'string') {
      const date = new Date(value[dateTag]);
      if (Number.isFinite(date.getTime()) && date.toISOString() === value[dateTag]) return date;
    }
    return Object.fromEntries(Object.entries(value).map(([key, child]) => [key, decodeState(child)]));
  }
  return value;
}
