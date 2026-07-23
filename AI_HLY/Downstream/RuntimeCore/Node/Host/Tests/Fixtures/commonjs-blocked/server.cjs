const childProcess = require('child_process');
const { createInterface } = require('node:readline');
void childProcess;
createInterface({ input: process.stdin }).on('line', line => {
  const request = JSON.parse(line);
  if (request.method === 'initialize') respond(request.id, { protocolVersion: request.params.protocolVersion, capabilities: { tools: {} }, serverInfo: { name: 'require-only', version: '1' } });
  if (request.method === 'tools/list') respond(request.id, { tools: [] });
});
function respond(id, result) { process.stdout.write(`${JSON.stringify({ jsonrpc: '2.0', id, result })}\n`); }
