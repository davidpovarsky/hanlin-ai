export const Fragment = "fragment";

function normalizeChildren(value) {
  const result = [];
  const visit = child => {
    if (Array.isArray(child)) child.forEach(visit);
    else if (child == null || child === false || child === true) return;
    else if (typeof child === "string" || typeof child === "number") result.push({ kind: "text", properties: { text: String(child) }, children: [] });
    else result.push(child);
  };
  visit(value);
  return result;
}

export function jsx(kind, properties = {}, key) {
  const { children, ...rest } = properties ?? {};
  return { kind, key: key == null ? null : String(key), properties: rest, children: normalizeChildren(children) };
}

export const jsxs = jsx;

export function createHooks(host) {
  let cursor = 0;
  const state = [];
  const effects = new Map();
  return {
    beginRender() { cursor = 0; },
    useState(initial) {
      const index = cursor++;
      if (!(index in state)) state[index] = typeof initial === "function" ? initial() : initial;
      return [state[index], value => { state[index] = typeof value === "function" ? value(state[index]) : value; host.invalidate(); }];
    },
    useEffect(setup, dependencies = []) {
      const index = cursor++;
      const previous = effects.get(index);
      const changed = !previous || dependencies.length !== previous.dependencies.length || dependencies.some((value, offset) => !Object.is(value, previous.dependencies[offset]));
      if (changed) {
        previous?.dispose?.();
        effects.set(index, { dependencies, dispose: setup() });
      }
    },
    dispose() { for (const effect of effects.values()) effect.dispose?.(); effects.clear(); },
  };
}
