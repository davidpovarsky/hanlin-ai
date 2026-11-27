/* Hanlin widget-only additions to the original Expo Widgets runtime.
 * Native Toggle uses the original Expo UI component/props and a SetValueIntent.
 * Buttons and Live Activity button callbacks keep the original implementation.
 */
(function () {
  'use strict';
  if (typeof globalThis.__hanlinWidgetHandleToggle === 'function') return;
  const render = globalThis.__expoWidgetRender;
  if (typeof render !== 'function') throw new Error('Original Expo Widgets renderer is unavailable');

  // Expo's app Toggle deliberately discards a callback's return value. Widget
  // callbacks instead return the next props, just like original widget buttons.
  // Keep the original component, children and modifier construction intact.
  const originalToggle = globalThis.Toggle;
  if (typeof originalToggle === 'function') {
    globalThis.Toggle = function (props) {
      const node = originalToggle(props);
      if (node && node.props && typeof props.onIsOnChange === 'function') {
        node.props.onIsOnChange = event => props.onIsOnChange(event.nativeEvent.isOn);
      }
      return node;
    };
  }

  function visit(node, path, action) {
    if (!node || typeof node !== 'object') return;
    if (Array.isArray(node)) {
      node.forEach((child, index) => visit(child, path + '/' + index, action));
    } else if (typeof node.type === 'string') {
      action(node, path);
      visit(node.props && node.props.children, path + '/children', action);
    } else if (!('type' in node)) {
      Object.keys(node).forEach(key => visit(node[key], path + '/' + key, action));
    }
  }

  globalThis.__expoWidgetRender = function (props, environment) {
    const node = render(props, environment);
    const targets = new Set();
    visit(node, 'root', (child, path) => {
      if (child.type !== 'ToggleView') return;
      const values = child.props || (child.props = {});
      if (values.target == null) {
        values.target = '__hanlin_toggle_' + JSON.stringify([child.key || child.__expoWidgetIdentity || path]);
      }
      if (typeof values.target !== 'string' || values.target.length === 0 ||
          targets.has(values.target)) throw new Error('Widget Toggle targets must be unique nonempty strings');
      targets.add(values.target);
      if (typeof values.isOn !== 'boolean') throw new Error('Widget Toggle isOn must be a Boolean');
    });
    return node;
  };

  globalThis.__hanlinWidgetHandleToggle = function (props, environment) {
    const { target, __hanlinToggleValue: value, ...renderEnvironment } = environment;
    if (typeof target !== 'string' || typeof value !== 'boolean') {
      throw new Error('Widget Toggle requires its target and an intended Boolean value');
    }
    let selected;
    visit(globalThis.__expoWidgetRender(props, renderEnvironment), 'root', node => {
      if (node.type === 'ToggleView' && node.props && node.props.target === target) {
        if (selected) throw new Error('Duplicate widget Toggle target');
        selected = node.props;
      }
    });
    if (!selected || typeof selected.onIsOnChange !== 'function') {
      throw new Error('No matching widget Toggle callback');
    }
    const disabled = selected.disabled === true || selected.enabled === false ||
      (selected.modifiers || []).some(modifier =>
        modifier && modifier.$type === 'disabled' && modifier.disabled === true);
    if (disabled) throw new Error('Widget Toggle is disabled');
    const result = selected.onIsOnChange({ nativeEvent: { isOn: value } });
    if (!result || typeof result !== 'object' || Array.isArray(result) ||
        typeof result.then === 'function') {
      throw new Error('Widget Toggle callback must synchronously return the next props object');
    }
    // Serialization happens before native storage commits, so cyclic/non-JSON
    // results leave the previous valid state and timeline untouched.
    return JSON.parse(JSON.stringify(result));
  };
})();
