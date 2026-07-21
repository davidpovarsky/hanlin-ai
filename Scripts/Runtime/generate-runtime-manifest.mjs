#!/usr/bin/env node

import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';

const lockPath = process.argv[2] ?? 'RuntimeDependencies.lock.json';
const outputPath = process.argv[3] ?? 'AI_HLY/Downstream/RuntimeCore/Resources/RuntimeManifest.json';
const lock = JSON.parse(await readFile(lockPath, 'utf8'));
const manifest = {
  schemaVersion: lock.schemaVersion,
  runtimeBundle: lock.runtimeBundle,
  runtimes: [
    {
      id: 'node',
      sourceProject: lock.node.sourceRepository,
      version: lock.node.version,
      revision: lock.node.commit,
      license: lock.node.license,
      bundleHash: lock.node.xcframeworkSha256,
      verificationStatus: lock.node.verificationStatus,
    },
    {
      id: 'python',
      sourceProject: lock.python.sourceRepository,
      version: lock.python.version,
      revision: lock.python.release,
      license: lock.python.license,
      bundleHash: lock.python.archive.sha256,
      verificationStatus: 'archive-verified',
    },
    {
      id: 'typescript',
      sourceProject: 'https://github.com/microsoft/TypeScript',
      version: lock.typescript.version,
      revision: lock.typescript.version,
      license: lock.typescript.license,
      bundleHash: lock.typescript.integrity,
      verificationStatus: 'package-integrity-verified',
    },
    {
      id: 'ios-system',
      sourceProject: lock.iosSystem.sourceRepository,
      version: lock.iosSystem.release,
      revision: lock.iosSystem.commit,
      license: lock.iosSystem.license,
      bundleHash: null,
      componentHashes: Object.fromEntries(lock.iosSystem.components.map(component => [component.name, component.sha256])),
      verificationStatus: 'release-assets-verified',
    },
  ],
};

await mkdir(path.dirname(outputPath), { recursive: true });
await writeFile(outputPath, `${JSON.stringify(manifest, null, 2)}\n`);
process.stdout.write(`Generated ${outputPath}.\n`);
