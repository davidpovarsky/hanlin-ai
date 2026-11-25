import { realpath } from 'node:fs/promises';
import { dirname, isAbsolute, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

function toolOutput(tool, args) {
  const result = spawnSync(tool, args, { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  if (result.error || result.status !== 0) {
    throw new Error('Unable to inspect the built host image: ' + args.at(-1), {
      cause: result.error ?? new Error(result.stderr || tool + ' exited ' + result.status),
    });
  }
  return result.stdout;
}

function inspectBinary(path) {
  return {
    architectures: toolOutput('/usr/bin/lipo', ['-archs', path]).trim().split(/\s+/),
    loadCommands: toolOutput('/usr/bin/otool', ['-l', path]),
  };
}

function slicesForImage({ architectures, loadCommands }, path) {
  if (!architectures.length || architectures.some((architecture) => !architecture)) {
    throw new Error('Unable to identify the built host image architectures: ' + path);
  }
  const headers = [...loadCommands.matchAll(/^.+ \(architecture ([^)]+)\):[^\S\r\n]*$/gm)];
  const blocks = headers.length
    ? headers.map((header, index) => ({
      architecture: header[1],
      text: loadCommands.slice(header.index, headers[index + 1]?.index ?? loadCommands.length),
    }))
    : [{ architecture: architectures.length === 1 ? architectures[0] : null, text: loadCommands }];
  if (blocks.length !== architectures.length
      || new Set(blocks.map((block) => block.architecture)).size !== architectures.length
      || blocks.some((block) => !architectures.includes(block.architecture))) {
    throw new Error('Unable to inspect every architecture of the built host image: ' + path);
  }
  return new Map(blocks.map(({ architecture, text }) => {
    const dependencies = [];
    const runpaths = [];
    for (const command of text.split(/^\s*Load command \d+\s*$/m).slice(1)) {
      const kind = command.match(/^\s*cmd\s+(LC_[A-Z_]+)\s*$/m)?.[1];
      if (['LC_LOAD_DYLIB', 'LC_LOAD_WEAK_DYLIB', 'LC_REEXPORT_DYLIB', 'LC_LOAD_UPWARD_DYLIB'].includes(kind)) {
        const name = command.match(/^\s*name\s+(.+?)\s+\(offset \d+\)\s*$/m)?.[1];
        if (name) dependencies.push(name);
      } else if (kind === 'LC_RPATH') {
        const name = command.match(/^\s*path\s+(.+?)\s+\(offset \d+\)\s*$/m)?.[1];
        if (name) runpaths.push(name);
      }
    }
    const metadata = [];
    for (const section of text.split(/^\s*Section\s*$/m).slice(1)) {
      if (section.match(/^\s*sectname\s+(\S+)\s*$/m)?.[1] !== '__TNSMetadata'
          || section.match(/^\s*segname\s+(\S+)\s*$/m)?.[1] !== '__DATA') continue;
      const size = section.match(/^\s*size\s+(0x[0-9a-fA-F]+|\d+)\s*$/m)?.[1];
      if (!size) throw new Error('Unable to read NativeScript metadata section size in ' + path);
      metadata.push(BigInt(size));
    }
    return [architecture, { dependencies, runpaths, metadata }];
  }));
}

function expandPath(path, image, appRoot) {
  if (path === '@executable_path' || path.startsWith('@executable_path/')) {
    return resolve(appRoot, path.slice('@executable_path'.length).replace(/^\//, ''));
  }
  if (path === '@loader_path' || path.startsWith('@loader_path/')) {
    return resolve(dirname(image), path.slice('@loader_path'.length).replace(/^\//, ''));
  }
  return isAbsolute(path) ? path : null;
}

async function linkedImage(name, image, appRoot, runpaths) {
  const candidates = name.startsWith('@rpath/')
    ? runpaths.map((path) => resolve(path, name.slice('@rpath/'.length)))
    : [expandPath(name, image, appRoot)].filter(Boolean);
  for (const candidate of candidates) {
    try {
      // Respect dyld search order; do not substitute an app-local shadow for an
      // existing image that resolves outside the direct host directory.
      return await realpath(candidate);
    } catch (error) {
      if (error.code !== 'ENOENT' && error.code !== 'ENOTDIR') throw error;
    }
  }
  return null;
}

// Match HanlinHostMetadataPointer: only loaded direct main-bundle images, never
// SDK/framework metadata or an unlinked dylib merely present beside the app.
export async function collectHostImages(appRoot, executable, inspect = inspectBinary) {
  const bundle = await realpath(appRoot);
  const main = await realpath(executable);
  if (dirname(main) !== bundle) throw new Error('The built app executable is outside its main bundle');
  const inspected = new Map();
  const inspectOnce = (path) => {
    if (!inspected.has(path)) inspected.set(path, slicesForImage(inspect(path), path));
    return inspected.get(path);
  };
  const pending = [...inspectOnce(main).keys()].map((architecture) => ({
    path: main, architecture, inheritedRunpaths: [],
  }));
  const visited = new Set();
  const images = [];
  for (const image of pending) {
    const identity = image.path + '\0' + image.architecture;
    if (visited.has(identity)) continue;
    visited.add(identity);
    const slice = inspectOnce(image.path).get(image.architecture);
    if (!slice) throw new Error('Linked host image lacks ' + image.architecture + ': ' + image.path);
    images.push({ path: image.path, architecture: image.architecture, metadata: slice.metadata });
    const runpaths = [...new Set([
      ...slice.runpaths.map((path) => expandPath(path, image.path, bundle)).filter(Boolean),
      ...image.inheritedRunpaths,
    ])];
    for (const dependency of slice.dependencies) {
      const candidate = await linkedImage(dependency, image.path, bundle, runpaths);
      if (candidate && dirname(candidate) === bundle) {
        pending.push({ path: candidate, architecture: image.architecture, inheritedRunpaths: runpaths });
      }
    }
  }
  return images;
}

export function requireHostMetadata(images) {
  const owners = new Map();
  for (const architecture of new Set(images.map((image) => image.architecture))) {
    const matches = images.filter((image) => image.architecture === architecture
      && image.metadata.some((size) => size > 0n));
    if (matches.length !== 1 || matches[0].metadata.length !== 1) {
      throw new Error('The built app must contain exactly one nonempty __DATA,__TNSMetadata section for '
        + architecture + '; found ' + matches.length + ' host images');
    }
    owners.set(architecture, matches[0].path);
  }
  if (!owners.size) throw new Error('The built app contains no inspectable host images');
  return owners;
}
