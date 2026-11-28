import { promises as fs } from 'node:fs';

const files = {
  state: 'AI_HLY/Downstream/MCP/Core/MCPInstallState.swift',
  provider: 'AI_HLY/Downstream/MCP/Runtime/MCPRuntimeProvider.swift',
  installView: 'AI_HLY/Downstream/MCP/UI/Settings/MCPServerInstallView.swift',
  detailView: 'AI_HLY/Downstream/MCP/UI/Settings/MCPServerDetailView.swift',
  progressView: 'AI_HLY/Downstream/MCP/UI/Settings/MCPInstallProgressView.swift',
  host: 'AI_HLY/Downstream/RuntimeCore/Node/Host/host.mjs',
};
const source = Object.fromEntries(await Promise.all(
  Object.entries(files).map(async ([name, file]) => [name, await fs.readFile(file, 'utf8')]),
));

requireText(source.state, 'case failed(operationID: UUID?', 'terminal install state must retain operationID');
requireText(source.host, 'terminalError:', 'host progress must publish one structured terminal error');
requireText(source.host, 'operationID: error.operationID ?? null', 'host error response must retain operationID');
requireText(source.provider, 'reportedOperationID == operationID', 'request and progress failures must deduplicate by operationID');
requireText(source.installView, 'The operation-scoped progress card owns terminal install failures.', 'install view must not append the same terminal error');
requireText(source.detailView, 'if case .failed = provider.installState', 'replacement UI must not duplicate its terminal error');

const terminalLabels = [...source.progressView.matchAll(/Label\(message,/g)].length;
if (terminalLabels !== 1) throw new Error(`Expected one terminal install error label, found ${terminalLabels}.`);
console.log('Validated operationID-scoped MCP terminal error deduplication.');

function requireText(value, expected, message) {
  if (!value.includes(expected)) throw new Error(message);
}
