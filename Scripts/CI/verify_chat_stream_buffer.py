#!/usr/bin/env python3
"""Run actual stream batching logic on desktop Swift, without simulator work.

Opaque StreamData payload types are replaced only in a temporary DTO. The
production buffer itself is compiled unchanged. All DTO fields must occur in
its classification, so a future metadata field cannot silently become text.
"""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--swiftc', default='swiftc')
args = parser.parse_args()
api = (root / 'AI_HLY/Services/ChatServices/APIManager.swift').read_text(encoding='utf-8-sig')
shape = re.search(r'struct StreamData \{(.*?)\n\}', api, re.S).group(1)
source = root / 'AI_HLY/Downstream/ChatPresentation/HanlinChatStreamBuffer.swift'
buffer = source.read_text(encoding='utf-8-sig')
fields = re.findall(r'var (\w+):\s*([^\n]+)', shape)
classified = set(re.findall(r'data\.(\w+)', buffer))
assert {name for name, _ in fields} == classified, 'StreamData classification is incomplete'
lines = ['import Foundation', 'struct StreamData {']
for name, type_name in fields:
    if name == 'agentEvents':
        lines.append('    var agentEvents: [String] = []')
    elif name == 'modelRoundID':
        lines.append('    var modelRoundID: UUID? = nil')
    else:
        lines.append(f'    var {name}: String?')
lines.append('}')
with tempfile.TemporaryDirectory(prefix='hanlin-stream-') as tmp:
    tmp = Path(tmp)
    dto = tmp / 'StreamData.swift'
    dto.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    binary = tmp / ('stream-checks.exe' if __import__('os').name == 'nt' else 'stream-checks')
    subprocess.run([args.swiftc, '-swift-version', '6', '-parse-as-library', str(dto), str(source), str(root / 'Scripts/CI/ChatStreamBufferChecks.swift'), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
