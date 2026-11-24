// Both upstream renderers return through the same existing Hanlin Host bridge.
// lang-core takes positional arguments and a raw result. react-lang's public
// toolProvider takes an MCP request object and decodes an MCP result envelope.
export function createHostToolProviders(post) {
  const nativeToolProvider = {
    callTool: (name, args) => post({
      kind: 'tool', name, args: JSON.parse(JSON.stringify(args)),
    }),
  };
  const reactToolProvider = {
    async callTool({ name, arguments: args = {} }) {
      return { structuredContent: await nativeToolProvider.callTool(name, args) };
    },
  };
  return { nativeToolProvider, reactToolProvider };
}
