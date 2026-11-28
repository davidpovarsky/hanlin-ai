import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
void spawn;
createInterface({ input: process.stdin }).on('line', line => {
  const request = JSON.parse(line);
  if (request.method === 'initialize') respond(request.id, { protocolVersion: request.params.protocolVersion, capabilities: { tools: {} }, serverInfo: { name: 'import-only', version: '1' } });
  if (request.method === 'tools/list') respond(request.id, { tools: [] });
});
function respond(id, result) { process.stdout.write(`${JSON.stringify({ jsonrpc: '2.0', id, result })}\n`); }
