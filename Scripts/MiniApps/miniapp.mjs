#!/usr/bin/env node
import {promises as fs} from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {runMiniAppOperation} from '../../AI_HLY/Downstream/RuntimeCore/Node/Host/miniapp-authoring.mjs';

const [operation, ...argumentsList] = process.argv.slice(2);
const options = {};
for (let index = 0; index < argumentsList.length; index += 2) {
  const key = argumentsList[index];
  const value = argumentsList[index + 1];
  if (!['--sdk', '--project', '--engine', '--resource', '--archive', '--report'].includes(key) || !value)
    throw new Error('Usage: miniapp.mjs sdk|validate|build --sdk <SDK directory> [--engine expo|nativescript|scriptwidget] [--project <directory>] [--resource <SDK path>] [--archive <new archive>] [--report <JSON path>]');
  options[key.slice(2)] = value;
}
if (!['sdk', 'validate', 'build'].includes(operation) || !options.sdk ||
  (operation !== 'sdk' && !options.project)) throw new Error('A known operation, --sdk and (for validate/build) --project are required.');
const compiler = process.env.HANLIN_AUTHORING_TYPESCRIPT
  ? (await import(process.env.HANLIN_AUTHORING_TYPESCRIPT.startsWith('file:')
      ? process.env.HANLIN_AUTHORING_TYPESCRIPT : pathToFileURL(process.env.HANLIN_AUTHORING_TYPESCRIPT).href)).default
  : undefined;
let report = await runMiniAppOperation({
  operation, engine: options.engine, resource: options.resource,
  projectRoot: options.project && path.resolve(options.project)
}, {sdkRoot: path.resolve(options.sdk), compiler});
if (operation === 'build' && report.succeeded) {
  const suffix = report.engine === 'expo' ? '.hanlinExpo' : report.engine === 'nativescript' ? '.hanlinNativeScript' : '.zip';
  const archive = options.archive ? path.resolve(options.archive)
    : path.join(path.dirname(report.preparedPackagePath), 'MiniApp' + suffix);
  // iOS uses its existing ZIPFoundation; the desktop CLI uses Python's standard zipfile.
  const zip = [
    'import pathlib, sys, zipfile',
    'root = pathlib.Path(sys.argv[1])',
    'target = pathlib.Path(sys.argv[2])',
    'target.parent.mkdir(parents=True, exist_ok=True)',
    "with zipfile.ZipFile(target, 'x', compression=zipfile.ZIP_DEFLATED) as archive:",
    "    for source in sorted(root.rglob('*')):",
    '        if source.is_file():',
    '            entry = zipfile.ZipInfo(source.relative_to(root).as_posix(), (2000, 1, 1, 0, 0, 0))',
    '            entry.compress_type = zipfile.ZIP_DEFLATED',
    '            archive.writestr(entry, source.read_bytes())'
  ].join('\n');
  let packed = spawnSync('python3', ['-c', zip, report.preparedPackagePath, archive], {encoding: 'utf8', shell: false});
  if (packed.error?.code === 'ENOENT')
    packed = spawnSync('python', ['-c', zip, report.preparedPackagePath, archive], {encoding: 'utf8', shell: false});
  if (packed.status !== 0 || packed.error) {
    report = {...report, succeeded: false, diagnostics: [...report.diagnostics,
      {code: 'MINIAPP_ARCHIVE_FAILED', category: 'error', message: packed.error?.message ?? packed.stderr.trim()}]};
  } else report.archivePath = archive;
}
if (options.report) {
  const output = path.resolve(options.report);
  await fs.mkdir(path.dirname(output), {recursive: true});
  await fs.writeFile(output, JSON.stringify(report, null, 2) + '\n');
}
console.log(JSON.stringify(report, null, 2));
process.exitCode = report.succeeded === false ? 1 : 0;
