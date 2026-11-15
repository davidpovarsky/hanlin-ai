import { createHash } from 'node:crypto';
import { readFile, realpath, writeFile } from 'node:fs/promises';
import { basename, dirname, isAbsolute, relative, resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

// Exclusive generated-input scope. This is not a language classifier or an
// exemption from the metadata collector's public-root/alias checks.
const scopedHeaders = Object.freeze({
  'ReactCommon.framework': ['CallInvoker.h', 'RuntimeExecutor.h', 'RuntimeExecutorSyncUIThreadUtils.h', 'SchedulerPriority.h'],
  'jsi.framework': ['decorator.h', 'hermes-interfaces.h', 'instrumentation.h', 'jsi-inl.h', 'jsi.h', 'jsilib.h', 'threadsafe.h'],
  'reactperflogger.framework': ['BridgeNativeModulePerfLogger.h', 'FuseboxPerfettoDataSource.h', 'FuseboxTracer.h', 'HermesPerfettoDataSource.h', 'NativeModulePerfLogger.h', 'ReactPerfetto.h', 'ReactPerfettoCategories.h', 'ReactPerfettoLogger.h'],
});

export const defaultContractPath = fileURLToPath(new URL('./metadata-interface-contract.json', import.meta.url));
const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');
const sortedJSON = (values) => JSON.stringify([...values].sort());

export function preservesPartitionUmbrellaContract(framework, header) {
  return Object.hasOwn(scopedHeaders, framework) && scopedHeaders[framework].includes(header);
}

function requireRelativePath(value) {
  if (typeof value !== 'string' || !value || isAbsolute(value) || value.includes('\\') ||
      value.split('/').some((part) => !part || part === '.' || part === '..')) {
    throw new Error(`Unsafe contract input path: ${value}`);
  }
}

async function readOwnedFile(root, input) {
  requireRelativePath(input);
  const resolvedRoot = await realpath(root);
  const target = await realpath(resolve(resolvedRoot, input));
  const child = relative(resolvedRoot, target);
  if (isAbsolute(child) || child === '..' || child.startsWith(`..${sep}`)) {
    throw new Error(`Contract input escapes its source root: ${input}`);
  }
  return readFile(target);
}

function validateContractShape(contract) {
  // Version1 deliberately has no approved projection representation. A changed
  // status/boolean cannot activate an unimplemented or unverified transform.
  if (contract.schemaVersion !== 1 || contract.status !== 'INCOMPLETE' ||
      contract.productionProjectionEnabled !== false) {
    throw new Error('Unsupported interface contract; version1 permits incomplete inventory only');
  }
  if (sortedJSON(Object.keys(contract.frameworks ?? {})) !== sortedJSON(Object.keys(scopedHeaders))) {
    throw new Error('Interface framework scope changed');
  }
  for (const [framework, names] of Object.entries(scopedHeaders)) {
    const group = contract.frameworks[framework];
    if (!Array.isArray(group.headers) || sortedJSON(group.headers.map((entry) => entry.generated)) !==
        sortedJSON(names.map((name) => `Headers/${name}`))) {
      throw new Error(`Interface header scope changed: ${framework}`);
    }
    for (const entry of group.headers) {
      requireRelativePath(entry.source);
      const expectedSource = `${framework.slice(0, -'.framework'.length)}/${entry.generated.slice('Headers/'.length)}`;
      if (entry.source !== expectedSource || entry.languageRegions !== null ||
          entry.publicCObjCInventory?.status !== 'INCOMPLETE') {
        throw new Error(`Unreviewed interface projection: ${framework}/${entry.generated}`);
      }
      if (contract.rnDependencyClosure?.[entry.source]?.sha256 !== entry.sha256) {
        throw new Error(`Missing/inconsistent source closure: ${entry.source}`);
      }
    }
    if (group.moduleMap?.generated !== 'Modules/module.modulemap' || group.moduleMap.transform !== 'NONE') {
      throw new Error(`Unreviewed module-map transformation: ${framework}`);
    }
  }
  if (!Array.isArray(contract.missingFacts) || !contract.missingFacts.length) {
    throw new Error('Incomplete interface contract must identify missing facts');
  }
  for (const [input, receipt] of Object.entries(contract.rnDependencyClosure)) {
    requireRelativePath(input);
    if (!/^[0-9a-f]{64}$/.test(receipt.sha256) || !Array.isArray(receipt.includes)) {
      throw new Error(`Malformed source receipt: ${input}`);
    }
    for (const edge of receipt.includes) {
      if (edge.resolvedRNSource !== null && !Object.hasOwn(contract.rnDependencyClosure, edge.resolvedRNSource)) {
        throw new Error(`Missing transitive source closure: ${edge.resolvedRNSource}`);
      }
    }
  }
}

/** Read-only reconciliation of actual source/header/map bytes with the contract.
 * Source equality is provenance, not an exhaustive C/ObjC ABI absence proof.
 * Generated header differences are retained as facts; they never become aliases.
 */
export async function auditInterfacePartitionInputs({
  rnHeadersRoot,
  modularFrameworksRoot,
  contractPath = defaultContractPath,
}) {
  const contractBytes = await readFile(contractPath);
  const contract = JSON.parse(contractBytes.toString('utf8'));
  validateContractShape(contract);
  const report = {
    schemaVersion: 1,
    contractSHA256: sha256(contractBytes),
    status: 'INCOMPLETE',
    projectionEnabled: false,
    metadataInputRole: 'PUBLIC',
    sourceChecks: [],
    generatedChecks: [],
    sourceDrift: [],
    requiredProofs: contract.requiredProofs,
    missingFacts: contract.missingFacts,
    boundary: 'Read-only source inventory. No language projection, alias waiver, native compilation or API-preservation pass.',
  };
  for (const [input, receipt] of Object.entries(contract.rnDependencyClosure ?? {})) {
    const bytes = await readOwnedFile(rnHeadersRoot, input);
    const actualSHA256 = sha256(bytes);
    report.sourceChecks.push({ input, expectedSHA256: receipt.sha256, actualSHA256 });
    if (receipt.sha256 !== actualSHA256) report.sourceDrift.push(input);
  }
  for (const [framework, group] of Object.entries(contract.frameworks)) {
    for (const header of group.headers) {
      const source = await readOwnedFile(rnHeadersRoot, header.source);
      const actualSourceSHA256 = sha256(source);
      // Validate root receipts independently of the transitive-file map.
      if (actualSourceSHA256 !== header.sha256) report.sourceDrift.push(header.source);
      const input = `${framework}/${header.generated}`;
      const generated = await readOwnedFile(modularFrameworksRoot, input);
      report.generatedChecks.push({ input, source: header.source, sourceSHA256: actualSourceSHA256,
        generatedSHA256: sha256(generated), sourceEqual: source.equals(generated) });
    }
    const input = `${framework}/${group.moduleMap.generated}`;
    const bytes = await readOwnedFile(modularFrameworksRoot, input);
    const actualSHA256 = sha256(bytes);
    report.generatedChecks.push({ input, expectedSHA256: group.moduleMap.sha256, generatedSHA256: actualSHA256 });
    if (actualSHA256 !== group.moduleMap.sha256 || bytes.toString('utf8') !== group.moduleMap.content) {
      report.sourceDrift.push(input);
    }
  }
  report.sourceDrift = [...new Set(report.sourceDrift)];
  if (report.sourceDrift.length) report.status = 'SOURCE_DRIFT';
  return report;
}

export function assertInterfacePartitionReady(report) {
  // Never accept caller-supplied status booleans as native preservation evidence.
  // A future contract/projection implementation needs a separate reviewed schema.
  throw new Error(`Interface partition unavailable (${report.status}): version1 has no approved API/type contract or native equivalence receipts`);
}

async function main() {
  const args = process.argv.slice(2);
  const options = {};
  for (let index = 0; index < args.length; index += 2) {
    const key = { '--rn-headers': 'rnHeadersRoot', '--modular-frameworks': 'modularFrameworksRoot',
      '--contract': 'contractPath', '--output': 'output' }[args[index]];
    if (!key || !args[index + 1] || Object.hasOwn(options, key)) {
      throw new Error('Usage: metadata-interface-partition.mjs --rn-headers DIR --modular-frameworks DIR [--contract FILE] [--output FILE]');
    }
    options[key] = args[index + 1];
  }
  if (!options.rnHeadersRoot || !options.modularFrameworksRoot) throw new Error('Both source roots are required');
  const report = await auditInterfacePartitionInputs(options);
  const rendered = `${JSON.stringify(report, null, 2)}\n`;
  if (options.output) {
    // An evidence output must not alias any input, including through symlinks.
    const outputParent = await realpath(dirname(resolve(options.output)));
    const output = resolve(outputParent, basename(options.output));
    const protectedRoots = [await realpath(options.rnHeadersRoot), await realpath(options.modularFrameworksRoot)];
    for (const root of protectedRoots) {
      const child = relative(root, output);
      if (!isAbsolute(child) && child !== '..' && !child.startsWith(`..${sep}`)) throw new Error('Evidence output is inside an input root');
    }
    try {
      // Refuse existing outputs: this also prevents following a file symlink.
      await writeFile(output, rendered, { flag: 'wx' });
    } catch (error) {
      throw new Error(`Cannot create new evidence output: ${error.message}`);
    }
  } else {
    process.stdout.write(rendered);
  }
  process.exitCode = report.status === 'SOURCE_DRIFT' ? 3 : 2;
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  main().catch((error) => { process.stderr.write(`${error.message}\n`); process.exitCode = 1; });
}
