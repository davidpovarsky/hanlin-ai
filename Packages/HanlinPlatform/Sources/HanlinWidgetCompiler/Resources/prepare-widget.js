/* Hanlin install-time adapter. The execution-guard visitor below is ported from
 * everettjf/scriptwidget@68f04194f00222558c44d5a832e7617a96f62574
 * Shared/ScriptWidgetRuntime/Widget/Runtime/ScriptWidgetRuntime.swift (Apache-2.0).
 * Expo modules use the pinned widgets JSX/global ABI, not the Scripting ABI. */
function __hanlinCompileWidget(input) {
  const guardName = '__scriptWidgetCheckExecution';
  const guardPlugin = function ({ types: t }) {
    const check = () => t.expressionStatement(t.callExpression(t.identifier(guardName), []));
    const guardBody = path => {
      path.ensureBlock();
      path.get('body').unshiftContainer('body', check());
    };
    return { visitor: {
      Program(path) {
        path.traverse({
          Identifier(identifier) {
            if (!__scriptWidgetCompileActive()) throw new Error('Compilation time limit exceeded');
            if (identifier.node.name === guardName) throw new Error('Reserved runtime identifier: ' + guardName);
          },
          WithStatement() { throw new Error('with statements are unsupported'); }
        });
      },
      'Loop|Function': { exit: guardBody },
      CatchClause: { exit(path) { path.get('body').unshiftContainer('body', check()); } },
      TryStatement: { exit(path) {
        if (path.node.finalizer) path.get('finalizer').unshiftContainer('body', check());
      } }
    } };
  };
  if (input.engine === 'scriptwidget') {
    const calls = input.actions.filter(a => a.handler).map(a => {
      if (!/^[A-Za-z_$][A-Za-z0-9_$]*$/.test(a.handler)) throw new Error('Invalid action handler');
      return 'case ' + JSON.stringify(a.id) + ': await ' + a.handler + '(__hanlinEvent); break;';
    }).join('\n');
    // Original lifecycle: the script calls $render inside async $main. Action
    // functions retain their lexical scope and run in that same fresh context.
    const wrapped = 'async function $main() { try {\n' + input.files[input.entry] +
      '\nif (__hanlinAction) { switch(__hanlinAction) {\n' + calls +
      '\ndefault: throw new Error("Undeclared widget action"); } }\n' +
      '} catch(e) { $error(String(e)); } }';
    return Babel.transform(wrapped, {
      presets: input.format === 'jsx' ? ['scriptwidget'] : [],
      plugins: [guardPlugin]
    }).code;
  }
  if (input.engine !== 'expo') throw new Error('Unsupported widget engine');
  if (input.format === 'expo-layout') {
    return Babel.transform('(' + input.files[input.entry] + ')', { plugins: [guardPlugin] }).code.replace(/;\s*$/, '');
  }
  const factories = Object.keys(input.files).sort().map(path => {
    const plugins = ['transform-modules-commonjs', guardPlugin];
    const presets = input.format === 'tsx' ? ['typescript', 'scriptwidget'] :
      input.format === 'jsx' ? ['scriptwidget'] : [];
    const code = Babel.transform(input.files[path], { filename: path, presets, plugins }).code;
    return JSON.stringify(path) + ': function(module, exports, require) {\n' + code + '\n}';
  });
  return '(function() {\n' +
    'const ScriptWidget = { createElement: React.createElement, Fragment: React.Fragment };\n' +
    'const factories = {' + factories.join(',\n') + '}; const cache = {};\n' +
    'function load(name, parent) {\n' +
    'if (["react", "react/jsx-runtime", "@expo/ui/swift-ui", "@expo/ui/swift-ui/modifiers"].includes(name)) return globalThis;\n' +
    'if (name[0] === ".") { const parts = parent.split("/"); parts.pop(); for (const part of name.split("/")) { if (part === "..") parts.pop(); else if (part !== ".") parts.push(part); } name = parts.join("/"); }\n' +
    'if (!factories[name]) { const resolved = [".js", ".jsx", ".ts", ".tsx"].map(ext => name + ext).find(p => factories[p]); if (!resolved) throw new Error("Unsupported widget import: " + name); name = resolved; }\n' +
    'if (cache[name]) return cache[name].exports; const module = {exports:{}}; cache[name] = module; factories[name](module, module.exports, child => load(child, name)); return module.exports; }\n' +
    'const entry = load(' + JSON.stringify(input.entry) + ', "");\n' +
    'if (typeof entry.default !== "function") throw new Error("Expo widget must export a default layout function");\n' +
    'return entry.default; })()';
}
