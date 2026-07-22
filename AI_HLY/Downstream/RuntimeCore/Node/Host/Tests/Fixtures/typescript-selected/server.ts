import { createInterface } from 'node:readline';
type Request = { id?: number; method?: string; params?: { protocolVersion?: string } };
createInterface({ input: process.stdin }).on('line', (line: string) => {
  const request = JSON.parse(line) as Request;
  if (request.method === 'initialize') respond(request.id, { protocolVersion: request.params?.protocolVersion, capabilities: { tools: {} }, serverInfo: { name: 'typescript-fixture', version: '1.0.0' } });
  if (request.method === 'tools/list') respond(request.id, { tools: [] });
});
function respond(id: number | undefined, result: object): void { process.stdout.write(`${JSON.stringify({ jsonrpc: '2.0', id, result })}\n`); }
