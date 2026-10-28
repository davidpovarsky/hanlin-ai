import { createHash } from 'node:crypto';
import { access, chmod, cp, lstat, mkdir, readFile, readdir, readlink, rm, stat, writeFile } from 'node:fs/promises';
import { createWriteStream, existsSync } from 'node:fs';
import { basename, dirname, resolve } from 'node:path';
import { execSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import https from 'node:https';
import http from 'node:http';

const scriptRoot = resolve(import.meta.dirname);
const repositoryRoot = resolve(scriptRoot, '..', '..');
const artifactsRoot = resolve(repositoryRoot, 'Packages', 'HanlinExpoRuntime', 'Artifacts');
const lockPath = resolve(scriptRoot, 'dependency-lock.json');

const readJSON = async (path) => JSON.parse(await readFile(path, 'utf8'));
const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');

export async function findBrokenSymlinks(dir) {
  const broken = [];
  if (!existsSync(dir)) return broken;
  const entries = await readdir(dir, { withFileTypes: true });
  for (const ent of entries) {
    const full = resolve(dir, ent.name);
    const lst = await lstat(full);
    if (lst.isSymbolicLink()) {
      const linkTarget = await readlink(full);
      const resolvedTarget = resolve(dirname(full), linkTarget);
      if (!existsSync(resolvedTarget)) {
        broken.push({ path: full, target: linkTarget, resolvedTarget });
      }
    } else if (lst.isDirectory()) {
      broken.push(...(await findBrokenSymlinks(full)));
    }
  }
  return broken;
}

const AVAILABLE_LIBRARIES_REGEX =
  /(<key>AvailableLibraries<\/key>\s*<array>)((?:\s*<dict>(?:(?!<dict>)[\s\S])*?<\/dict>\s*)+)(<\/array>)/;

export function parseXCFrameworkInfoPlist(plistXml) {
  const arrayMatch = plistXml.match(AVAILABLE_LIBRARIES_REGEX);
  if (!arrayMatch) {
    throw new Error('Invalid XCFramework Info.plist: missing AvailableLibraries array');
  }
  const arrayBody = arrayMatch[2];
  const libraries = [];
  for (const dm of arrayBody.matchAll(/<dict>((?:(?!<dict>)[\s\S])*?)<\/dict>/g)) {
    const rawDict = dm[0];
    const body = dm[1];
    const getString = (key) => {
      const m = body.match(new RegExp(`<key>${key}<\\/key>\\s*<string>([^<]+)<\\/string>`));
      return m ? m[1].trim() : null;
    };
    const archMatch = body.match(/<key>SupportedArchitectures<\/key>\s*<array>([\s\S]*?)<\/array>/);
    const archs = archMatch
      ? [...archMatch[1].matchAll(/<string>([^<]+)<\/string>/g)].map((x) => x[1].trim())
      : [];
    libraries.push({
      rawDict,
      LibraryIdentifier: getString('LibraryIdentifier'),
      LibraryPath: getString('LibraryPath'),
      BinaryPath: getString('BinaryPath'),
      HeadersPath: getString('HeadersPath'),
      DebugSymbolsPath: getString('DebugSymbolsPath'),
      BitcodeSymbolMapsPath: getString('BitcodeSymbolMapsPath'),
      SupportedPlatform: getString('SupportedPlatform'),
      SupportedPlatformVariant: getString('SupportedPlatformVariant'),
      SupportedArchitectures: archs,
    });
  }
  const pkgTypeMatch = plistXml.match(/<key>CFBundlePackageType<\/key>\s*<string>([^<]+)<\/string>/);
  return {
    CFBundlePackageType: pkgTypeMatch ? pkgTypeMatch[1].trim() : null,
    AvailableLibraries: libraries,
  };
}

export async function cleanBundleMetadataAndSignatures(dir) {
  if (!existsSync(dir)) return;
  const entries = await readdir(dir, { withFileTypes: true });
  for (const ent of entries) {
    const fullPath = resolve(dir, ent.name);
    const lst = await lstat(fullPath);
    if (lst.isDirectory()) {
      if (ent.name === '_CodeSignature' || ent.name === '__MACOSX') {
        await rm(fullPath, { recursive: true, force: true });
      } else {
        await cleanBundleMetadataAndSignatures(fullPath);
      }
    } else if (
      ent.name === '.build-hash' ||
      ent.name === '.DS_Store' ||
      ent.name.startsWith('._')
    ) {
      await rm(fullPath, { force: true });
    }
  }
}

export async function pruneNonIOSSlicesFromXCFramework(xcfPath) {
  const infoPlistPath = resolve(xcfPath, 'Info.plist');
  if (!existsSync(infoPlistPath)) {
    throw new Error(`Missing Info.plist in ${xcfPath}`);
  }
  const plistXml = await readFile(infoPlistPath, 'utf8');
  const parsed = parseXCFrameworkInfoPlist(plistXml);
  const keptLibraries = parsed.AvailableLibraries.filter(
    (lib) =>
      lib.SupportedPlatform === 'ios' &&
      (!lib.SupportedPlatformVariant || lib.SupportedPlatformVariant === 'simulator')
  );
  if (keptLibraries.length === 0) {
    throw new Error(`No iOS slices found in ${infoPlistPath}`);
  }

  const keptIds = new Set(keptLibraries.map((lib) => lib.LibraryIdentifier));
  const newArrayBody = '\n' + keptLibraries.map((lib) => `\t\t${lib.rawDict.trim()}`).join('\n') + '\n\t';
  const updatedXml = plistXml.replace(AVAILABLE_LIBRARIES_REGEX, `$1${newArrayBody}$3`);
  if (updatedXml !== plistXml) {
    await writeFile(infoPlistPath, updatedXml, 'utf8');
  }

  const entries = await readdir(xcfPath, { withFileTypes: true });
  for (const ent of entries) {
    if (!ent.isDirectory()) continue;
    if (ent.name === 'Headers' || ent.name === '_CodeSignature') continue;
    if (!keptIds.has(ent.name)) {
      await rm(resolve(xcfPath, ent.name), { recursive: true, force: true });
    }
  }

  for (const lib of keptLibraries) {
    const sliceDir = resolve(xcfPath, lib.LibraryIdentifier);
    if (!existsSync(sliceDir)) continue;
    if (!lib.DebugSymbolsPath) {
      const dsymsDir = resolve(sliceDir, 'dSYMs');
      if (existsSync(dsymsDir)) {
        await rm(dsymsDir, { recursive: true, force: true });
      }
    }
    if (!lib.BitcodeSymbolMapsPath) {
      const bcDir = resolve(sliceDir, 'BCSymbolMaps');
      if (existsSync(bcDir)) {
        await rm(bcDir, { recursive: true, force: true });
      }
    }
  }

  return keptLibraries;
}

export async function validateXCFrameworkStructure(
  xcfPath,
  {
    checkDarwinTools = process.platform === 'darwin',
    requireFrameworkInfoPlist = process.platform === 'darwin',
  } = {}
) {
  if (!existsSync(xcfPath)) {
    throw new Error(`XCFramework does not exist: ${xcfPath}`);
  }
  const brokenSymlinks = await findBrokenSymlinks(xcfPath);
  if (brokenSymlinks.length > 0) {
    const details = brokenSymlinks.map((b) => `${b.path} -> ${b.target}`).join('; ');
    throw new Error(`Broken symlinks detected in ${basename(xcfPath)}: ${details}`);
  }

  const infoPlistPath = resolve(xcfPath, 'Info.plist');
  if (!existsSync(infoPlistPath)) {
    throw new Error(`Missing top-level Info.plist in ${basename(xcfPath)}`);
  }

  if (checkDarwinTools) {
    execSync(`/usr/bin/plutil -lint "${infoPlistPath}"`, { stdio: 'pipe' });
  }

  const plistXml = await readFile(infoPlistPath, 'utf8');
  const parsed = parseXCFrameworkInfoPlist(plistXml);
  if (parsed.CFBundlePackageType !== 'XFWK') {
    throw new Error(
      `Invalid CFBundlePackageType in ${infoPlistPath}: expected XFWK, got ${parsed.CFBundlePackageType}`
    );
  }

  const sliceIds = new Set(parsed.AvailableLibraries.map((l) => l.LibraryIdentifier));
  if (!sliceIds.has('ios-arm64') || !sliceIds.has('ios-arm64_x86_64-simulator')) {
    throw new Error(
      `${basename(xcfPath)} must contain both ios-arm64 and ios-arm64_x86_64-simulator slices (found: ${[
        ...sliceIds,
      ].join(', ')})`
    );
  }

  for (const lib of parsed.AvailableLibraries) {
    if (
      lib.SupportedPlatform !== 'ios' ||
      (lib.SupportedPlatformVariant && lib.SupportedPlatformVariant !== 'simulator')
    ) {
      throw new Error(
        `Non-iOS slice ${lib.LibraryIdentifier} still present in ${basename(xcfPath)} Info.plist`
      );
    }

    const sliceDir = resolve(xcfPath, lib.LibraryIdentifier);
    if (!existsSync(sliceDir)) {
      throw new Error(`Missing slice directory ${sliceDir}`);
    }
    const libraryPath = resolve(sliceDir, lib.LibraryPath);
    if (!existsSync(libraryPath)) {
      throw new Error(`Missing LibraryPath ${libraryPath}`);
    }
    const binaryRelPath = lib.BinaryPath || lib.LibraryPath;
    const binaryPath = resolve(sliceDir, binaryRelPath);
    if (!existsSync(binaryPath)) {
      throw new Error(`Missing BinaryPath ${binaryPath}`);
    }
    const binStat = await stat(binaryPath);
    if (!binStat.isFile() || binStat.size === 0) {
      throw new Error(`Invalid or empty binary at ${binaryPath}`);
    }

    if (lib.LibraryPath.endsWith('.framework')) {
      const fwInfoPlist = resolve(libraryPath, 'Info.plist');
      const mustHaveFwPlist =
        requireFrameworkInfoPlist || basename(xcfPath) !== 'ExpoModulesJSI.xcframework';
      if (mustHaveFwPlist && !existsSync(fwInfoPlist)) {
        throw new Error(`Missing framework Info.plist at ${fwInfoPlist}`);
      }
      if (existsSync(fwInfoPlist)) {
        const fwBuf = await readFile(fwInfoPlist);
        if (!fwBuf.includes(Buffer.from('FMWK'))) {
          throw new Error(`Framework Info.plist at ${fwInfoPlist} is missing CFBundlePackageType=FMWK`);
        }
        if (!fwBuf.includes(Buffer.from('MinimumOSVersion'))) {
          throw new Error(`Framework Info.plist at ${fwInfoPlist} is missing MinimumOSVersion`);
        }
        if (checkDarwinTools) {
          execSync(`/usr/bin/plutil -lint "${fwInfoPlist}"`, { stdio: 'pipe' });
        }
      }
    }

    if (checkDarwinTools) {
      const lipoOut = execSync(`/usr/bin/lipo -archs "${binaryPath}"`, { encoding: 'utf8' }).trim();
      const actualArchs = new Set(lipoOut.split(/\s+/).filter(Boolean));
      for (const expectedArch of lib.SupportedArchitectures) {
        if (!actualArchs.has(expectedArch)) {
          throw new Error(
            `Architecture mismatch for ${binaryPath}: expected ${expectedArch}, got ${lipoOut}`
          );
        }
      }
    }
  }

  return parsed;
}

export async function signAndVerifyXCFramework(
  xcfPath,
  {
    checkDarwinTools = process.platform === 'darwin',
    requireFrameworkInfoPlist = process.platform === 'darwin',
  } = {}
) {
  await cleanBundleMetadataAndSignatures(xcfPath);
  await pruneNonIOSSlicesFromXCFramework(xcfPath);
  const parsed = await validateXCFrameworkStructure(xcfPath, {
    checkDarwinTools,
    requireFrameworkInfoPlist,
  });

  if (checkDarwinTools) {
    for (const lib of parsed.AvailableLibraries) {
      if (lib.LibraryPath.endsWith('.framework')) {
        const fwPath = resolve(xcfPath, lib.LibraryIdentifier, lib.LibraryPath);
        execSync(`/usr/bin/codesign --force --sign - --timestamp=none "${fwPath}"`, {
          stdio: 'pipe',
        });
        execSync(`/usr/bin/codesign --verify --strict --verbose=2 "${fwPath}"`, {
          stdio: 'pipe',
        });
      }
    }
    execSync(`/usr/bin/codesign --force --sign - --timestamp=none "${xcfPath}"`, {
      stdio: 'pipe',
    });
    execSync(`/usr/bin/codesign --verify --strict --verbose=2 "${xcfPath}"`, {
      stdio: 'pipe',
    });
    execSync(`/usr/bin/codesign -vvvv "${xcfPath}"`, {
      stdio: 'pipe',
    });
  }
}

async function downloadFile(url, destPath) {
  const curlBin = process.platform === 'win32' ? 'curl.exe' : 'curl';
  try {
    execSync(`${curlBin} -fL --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 300 -sS "${url}" -o "${destPath}"`, {
      stdio: ['ignore', 'inherit', 'inherit'],
    });
    if (existsSync(destPath)) {
      const fileStat = await stat(destPath);
      if (fileStat.size > 0) {
        return;
      }
    }
  } catch (curlErr) {
    console.warn(`[HanlinExpo] curl download attempt failed (${curlErr.message}); falling back to Node http client...`);
  }

  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      await new Promise((res, rej) => {
        function get(currentURL, redirects = 0) {
          if (redirects > 10) {
            return rej(new Error(`Too many redirects for ${url}`));
          }
          const client = currentURL.startsWith('https') ? https : http;
          const req = client.get(
            currentURL,
            { agent: false, headers: { 'User-Agent': 'hanlin-ci-builder/1.0' } },
            (response) => {
              if (response.statusCode >= 300 && response.statusCode < 400 && response.headers.location) {
                const redirectURL = new URL(response.headers.location, currentURL).toString();
                return get(redirectURL, redirects + 1);
              }
              if (response.statusCode !== 200) {
                return rej(new Error(`Download failed with status ${response.statusCode} for ${currentURL}`));
              }
              const file = createWriteStream(destPath);
              response.pipe(file);
              file.on('finish', () => {
                file.close(() => res());
              });
              file.on('error', rej);
            }
          );
          req.setTimeout(60000, () => {
            req.destroy(new Error(`Socket timeout downloading ${currentURL}`));
          });
          req.on('error', rej);
        }
        get(url);
      });
      if (existsSync(destPath) && (await stat(destPath)).size > 0) {
        return;
      }
    } catch (nodeErr) {
      console.warn(`[HanlinExpo] Node download attempt ${attempt}/3 failed (${nodeErr.message})...`);
      if (attempt === 3) throw nodeErr;
      await new Promise((r) => setTimeout(r, 2000 * attempt));
    }
  }
}

async function prepare() {
  console.log('[HanlinExpo] Preparing iOS Expo and React Native dependencies...');
  await mkdir(artifactsRoot, { recursive: true });
  const lock = await readJSON(lockPath);
  const tempDir = resolve(scriptRoot, '.tmp-download');
  await rm(tempDir, { recursive: true, force: true });
  await mkdir(tempDir, { recursive: true });

  try {
    for (const item of lock.artifacts) {
      const targetDir = resolve(repositoryRoot, item.target);
      const manifestPath = resolve(targetDir, '.artifact-manifest.json');
      if (existsSync(targetDir)) {
        let manifestValid = false;
        try {
          if (existsSync(manifestPath)) {
            const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
            if (manifest.sha256 === item.sha256 && manifest.name === item.name) {
              manifestValid = true;
            }
          }
        } catch (_) {}

        if (!manifestValid) {
          console.warn(`[HanlinExpo] ${item.name} at ${item.target} missing or mismatched provenance manifest (expected SHA ${item.sha256}); re-extracting...`);
          await rm(targetDir, { recursive: true, force: true });
        } else {
          try {
            await cleanBundleMetadataAndSignatures(targetDir);
            await pruneNonIOSSlicesFromXCFramework(targetDir);
            const broken = await findBrokenSymlinks(targetDir);
            if (broken.length === 0) {
              console.log(`[HanlinExpo] ${item.name} already staged and verified at ${item.target}`);
              continue;
            }
            console.warn(
              `[HanlinExpo] ${item.name} at ${item.target} has ${broken.length} broken symlink(s); re-extracting...`
            );
          } catch (validationErr) {
            console.warn(
              `[HanlinExpo] ${item.name} at ${item.target} failed pre-check (${validationErr.message}); re-extracting...`
            );
          }
          await rm(targetDir, { recursive: true, force: true });
        }
      }
      console.log(`[HanlinExpo] Fetching ${item.name}...`);
      const downloadURL = item.tarball || item.url;
      const fileName = basename(new URL(downloadURL).pathname);
      const downloadedPath = resolve(tempDir, fileName);

      if (!existsSync(downloadedPath)) {
        await downloadFile(downloadURL, downloadedPath);
      }
      const bytes = await readFile(downloadedPath);
      const digest = sha256(bytes);
      console.log(`[HanlinExpo] ${item.name} SHA256: ${digest}`);
      if (item.sha256 && digest !== item.sha256) {
        throw new Error(`[HanlinExpo] Integrity mismatch for ${item.name}: got ${digest}, expected ${item.sha256}`);
      }

      if (item.source === 'npm') {
        execSync(`tar -zxf "${downloadedPath}" -C "${tempDir}" "${item.subpath}"`);
        const extractedSub = resolve(tempDir, item.subpath);
        execSync(`tar -zxf "${extractedSub}" -C "${artifactsRoot}"`);
      } else if (item.source === 'npm-extract' || item.source === 'maven') {
        const unpackDir = resolve(tempDir, `unpack-${item.name}`);
        await mkdir(unpackDir, { recursive: true });
        execSync(`tar -zxf "${downloadedPath}" -C "${unpackDir}"`);
        const sourcePath = resolve(unpackDir, item.subpath);
        await cp(sourcePath, targetDir, { recursive: true, verbatimSymlinks: true });
      }
      await cleanBundleMetadataAndSignatures(targetDir);
      await pruneNonIOSSlicesFromXCFramework(targetDir);
      await writeFile(
        manifestPath,
        JSON.stringify({ name: item.name, version: item.version, sha256: item.sha256, stagedAt: new Date().toISOString() }, null, 2),
        'utf8'
      );
      console.log(`[HanlinExpo] Staged ${item.name} -> ${item.target}`);
    }
    console.log('[HanlinExpo] All dependencies staged successfully.');

    async function stageModularHeaders() {
      console.log('[HanlinExpo] Staging modular React and Cxx headers in ReactModularHeaders...');
      const modularHeadersRoot = resolve(artifactsRoot, 'ReactModularHeaders');
      await rm(modularHeadersRoot, { recursive: true, force: true });
      await mkdir(modularHeadersRoot, { recursive: true });

      const slices = ['ios-arm64_x86_64-simulator', 'ios-arm64'];
      const rnDepsHeaders = resolve(artifactsRoot, 'ReactNativeDependencies.xcframework', 'Headers');

      for (const slice of slices) {
        const rnHeaders = resolve(artifactsRoot, 'ReactNativeHeaders.xcframework', slice, 'Headers');

        if (existsSync(rnHeaders)) {
          const entries = await readdir(rnHeaders, { withFileTypes: true });
          for (const entry of entries) {
            if (entry.name.endsWith('.modulemap')) continue;
            const src = resolve(rnHeaders, entry.name);
            const dstMod = resolve(modularHeadersRoot, entry.name);
            if (!existsSync(dstMod)) {
              await cp(src, dstMod, { recursive: true });
            }
          }
        }
      }

      if (existsSync(rnDepsHeaders)) {
        const depEntries = await readdir(rnDepsHeaders, { withFileTypes: true });
        for (const entry of depEntries) {
          if (entry.name.endsWith('.modulemap')) continue;
          const src = resolve(rnDepsHeaders, entry.name);
          const dstMod = resolve(modularHeadersRoot, entry.name);
          if (!existsSync(dstMod)) {
            await cp(src, dstMod, { recursive: true });
          }
        }
      }

      // Ensure nested fallback directory exists for $(SRCROOT)/Packages/HanlinExpoRuntime evaluation
      const nestedFallbackDir = resolve(artifactsRoot, '..', 'Packages', 'HanlinExpoRuntime');
      await mkdir(nestedFallbackDir, { recursive: true });
      const nestedFallbackArtifacts = resolve(nestedFallbackDir, 'Artifacts');
      await rm(nestedFallbackArtifacts, { recursive: true, force: true });
      await mkdir(nestedFallbackArtifacts, { recursive: true });
      await cp(modularHeadersRoot, resolve(nestedFallbackArtifacts, 'ReactModularHeaders'), { recursive: true });
      console.log('[HanlinExpo] Modular headers and nested fallback staged successfully.');
    }
    await stageModularHeaders();

    async function patchModuleMaps() {
      console.log('[HanlinExpo] Aligning Clang modulemaps across xcframeworks...');

      // Add use declarations to Expo modulemaps
      const expoFws = ['ExpoModulesCore.xcframework', 'ExpoModulesWorklets.xcframework', 'ExpoUI.xcframework'];
      for (const fw of expoFws) {
        const fwRoot = resolve(artifactsRoot, fw);
        if (existsSync(fwRoot)) {
          const slices = await readdir(fwRoot, { withFileTypes: true });
          for (const slice of slices) {
            if (!slice.isDirectory()) continue;
            const fwName = fw.replace('.xcframework', '.framework');
            const mapPath = resolve(fwRoot, slice.name, fwName, 'Modules', 'module.modulemap');
            if (existsSync(mapPath)) {
              let content = await readFile(mapPath, 'utf8');
              if (content.includes('use React') && !content.includes('use ReactCommon')) {
                content = content.replace(
                  'use React',
                  `use React
    use ReactCommon
    use yoga
    use RCTDeprecation`
                );
                await writeFile(mapPath, content, 'utf8');
                console.log(`[HanlinExpo] Added modular use declarations to ${fw} in ${slice.name}`);
              }
            }
          }
        }
      }
    }
    await patchModuleMaps();

    async function stageModularFrameworks() {
      console.log('[HanlinExpo] Staging modular header frameworks in ModularFrameworks...');
      const modularFwsRoot = resolve(artifactsRoot, 'ModularFrameworks');
      await rm(modularFwsRoot, { recursive: true, force: true });
      await mkdir(modularFwsRoot, { recursive: true });

      const slice = 'ios-arm64_x86_64-simulator';
      const rnHeaders = resolve(artifactsRoot, 'ReactNativeHeaders.xcframework', slice, 'Headers');
      const mapPath = resolve(rnHeaders, 'module.modulemap');

      if (!existsSync(mapPath)) {
        console.warn('[HanlinExpo] Warning: ReactNativeHeaders module.modulemap not found');
        return;
      }

      let content = await readFile(mapPath, 'utf8');
      content = content.replace(
        /module ReactCommon \{[\s\S]*?\}/,
        `module ReactCommon {
  header "ReactCommon/CallInvoker.h"
  header "ReactCommon/SchedulerPriority.h"
  header "ReactCommon/RuntimeExecutor.h"
  header "ReactCommon/RuntimeExecutorSyncUIThreadUtils.h"
  export *
}`
      );
      const moduleRegex = /module\s+([A-Za-z0-9_]+)\s*\{([^}]+)\}/g;
      let m;
      let count = 0;

      while ((m = moduleRegex.exec(content)) !== null) {
        const modName = m[1];
        if (modName === 'ReactNativeHeaders_react') {
          continue;
        }
        const body = m[2];
        const headerMatches = [...body.matchAll(/header\s+"([^"]+)"/g)].map(x => x[1]);

        if (headerMatches.length === 0) continue;

        const fwDir = resolve(modularFwsRoot, `${modName}.framework`);
        const headersDir = resolve(fwDir, 'Headers');
        const modulesDir = resolve(fwDir, 'Modules');

        await mkdir(headersDir, { recursive: true });
        await mkdir(modulesDir, { recursive: true });

        // Copy all headers from the module directory if present (except yoga and ReactCommon to avoid internal C++ leaks/cycles)
        const modSourceDir = resolve(rnHeaders, modName);
        if (existsSync(modSourceDir) && modName !== 'yoga' && modName !== 'ReactCommon') {
          const allHeaders = await readdir(modSourceDir, { withFileTypes: true });
          for (const ent of allHeaders) {
            if (ent.isFile() && ent.name.endsWith('.h')) {
              await cp(resolve(modSourceDir, ent.name), resolve(headersDir, ent.name));
            }
          }
        }

        // Copy each header explicitly declared in the module
        for (const h of headerMatches) {
          const srcFile = resolve(rnHeaders, h);
          const fileName = basename(h);
          const dstFile = resolve(headersDir, fileName);
          if (existsSync(srcFile)) {
            await cp(srcFile, dstFile);
          }
        }

        // Write exact modulemap matching React Native declarations
        const moduleMapLines = [
          `framework module ${modName} {`
        ];
        if (modName === 'ReactCommon') {
          moduleMapLines.push('    use jsi');
        }
        for (const h of headerMatches) {
          moduleMapLines.push(`    header "${basename(h)}"`);
        }
        moduleMapLines.push('    export *');
        moduleMapLines.push('}');
        moduleMapLines.push('');

        await writeFile(resolve(modulesDir, 'module.modulemap'), moduleMapLines.join('\n'), 'utf8');
        count++;
      }

      // Create modular jsi.framework in ModularFrameworks to satisfy #include <jsi/jsi.h>
      const jsiSourceDir = resolve(rnHeaders, 'jsi');
      if (existsSync(jsiSourceDir)) {
        const jsiFwDir = resolve(modularFwsRoot, 'jsi.framework');
        const jsiHeadersDir = resolve(jsiFwDir, 'Headers');
        const jsiModulesDir = resolve(jsiFwDir, 'Modules');
        await mkdir(jsiHeadersDir, { recursive: true });
        await mkdir(jsiModulesDir, { recursive: true });

        const jsiFiles = await readdir(jsiSourceDir, { withFileTypes: true });
        const jsiHeaders = [];
        for (const file of jsiFiles) {
          if (file.isFile() && file.name.endsWith('.h') && file.name !== 'JSIDynamic.h') {
            await cp(resolve(jsiSourceDir, file.name), resolve(jsiHeadersDir, file.name));
            jsiHeaders.push(file.name);
          }
        }

        const jsiMap = [
          'framework module jsi {',
          ...jsiHeaders.map(h => `    header "${h}"`),
          '    export *',
          '}',
          ''
        ].join('\n');
        await writeFile(resolve(jsiModulesDir, 'module.modulemap'), jsiMap, 'utf8');
        count++;
        console.log('[HanlinExpo] Created modular jsi.framework in ModularFrameworks.');
      }

      // Create non-modular react.framework in ModularFrameworks providing unified react/ and React headers
      const reactFwDir = resolve(modularFwsRoot, 'react.framework');
      const reactHeadersDir = resolve(reactFwDir, 'Headers');
      await mkdir(reactHeadersDir, { recursive: true });

      if (existsSync(rnHeaders)) {
        await cp(rnHeaders, reactHeadersDir, { recursive: true });
      }
      const rnReactSource = resolve(rnHeaders, 'react');
      if (existsSync(rnReactSource)) {
        await cp(rnReactSource, reactHeadersDir, { recursive: true });
        const nestedReact = resolve(reactHeadersDir, 'react');
        if (!existsSync(nestedReact)) {
          await cp(rnReactSource, nestedReact, { recursive: true });
        }
      }

      const reactFwSource = resolve(artifactsRoot, 'React.xcframework', slice, 'React.framework', 'Headers');
      if (existsSync(reactFwSource)) {
        await cp(reactFwSource, reactHeadersDir, { recursive: true });
      }

      // Copy all headers from ReactModularHeaders and ReactNativeDependencies into react.framework
      const reactModularSource = resolve(artifactsRoot, 'ReactModularHeaders');
      if (existsSync(reactModularSource)) {
        await cp(reactModularSource, reactHeadersDir, { recursive: true });
      }
      const rnDepsHeaders = resolve(artifactsRoot, 'ReactNativeDependencies.xcframework', 'Headers');
      if (existsSync(rnDepsHeaders)) {
        await cp(rnDepsHeaders, reactHeadersDir, { recursive: true });
      }

      const reactCapFwDir = resolve(modularFwsRoot, 'React.framework');
      if (!existsSync(reactCapFwDir)) {
        await cp(reactFwDir, reactCapFwDir, { recursive: true });
      }

      // Also enrich React.xcframework itself with all headers from ReactNativeHeaders across all iOS slices
      const allSlices = ['ios-arm64_x86_64-simulator', 'ios-arm64'];
      for (const s of allSlices) {
        const targetHeaders = resolve(artifactsRoot, 'React.xcframework', s, 'React.framework', 'Headers');
        const sliceRnHeaders = resolve(artifactsRoot, 'ReactNativeHeaders.xcframework', s, 'Headers');
        if (existsSync(targetHeaders)) {
          if (existsSync(sliceRnHeaders)) {
            await cp(sliceRnHeaders, targetHeaders, { recursive: true });
          }
          if (existsSync(rnHeaders)) {
            await cp(rnHeaders, targetHeaders, { recursive: true });
          }
          const sliceReactSource = existsSync(sliceRnHeaders) ? resolve(sliceRnHeaders, 'react') : rnReactSource;
          if (existsSync(sliceReactSource)) {
            await cp(sliceReactSource, targetHeaders, { recursive: true });
            const nested = resolve(targetHeaders, 'react');
            if (!existsSync(nested)) {
              await cp(sliceReactSource, nested, { recursive: true });
            }
          }
          if (existsSync(reactModularSource)) {
            await cp(reactModularSource, targetHeaders, { recursive: true });
          }
          if (existsSync(rnDepsHeaders)) {
            await cp(rnDepsHeaders, targetHeaders, { recursive: true });
          }
        }
      }

      // Ensure no stray module.modulemap is left inside any Headers directory (prevents module redefinitions)
      const cleanHeaderModulemaps = async (dir) => {
        if (!existsSync(dir)) return;
        const stray = resolve(dir, 'module.modulemap');
        if (existsSync(stray)) {
          await rm(stray, { force: true });
        }
      };
      await cleanHeaderModulemaps(reactHeadersDir);
      if (existsSync(resolve(reactCapFwDir, 'Headers'))) {
        await cleanHeaderModulemaps(resolve(reactCapFwDir, 'Headers'));
      }
      for (const s of allSlices) {
        await cleanHeaderModulemaps(resolve(artifactsRoot, 'React.xcframework', s, 'React.framework', 'Headers'));
        await cleanHeaderModulemaps(resolve(artifactsRoot, 'ReactNativeHeaders.xcframework', s, 'Headers'));
      }

      // Sanitize headers to prevent modular framework include failures:
      // 1. Remove RCTInspectorNetworkHelper.h from React-umbrella.h (CDP debugger internals shouldn't pollute Swift module)
      // 2. Change angled <jsinspector-modern/...> includes to quotes to satisfy framework modular include rules
      const sanitizeHeaders = async (targetDir) => {
        if (!existsSync(targetDir)) return;
        const entries = await readdir(targetDir, { withFileTypes: true });
        for (const ent of entries) {
          const full = resolve(targetDir, ent.name);
          if (ent.isDirectory()) {
            if (ent.name === 'folly') {
              const jsonDyn = resolve(full, 'json', 'dynamic.h');
              const dyn = resolve(full, 'dynamic.h');
              const forwardToDyn = `#pragma once
#if __has_include(<folly/dynamic.h>)
#include <folly/dynamic.h>
#elif __has_include("folly/dynamic.h")
#include "folly/dynamic.h"
#elif __has_include("../dynamic.h")
#include "../dynamic.h"
#endif
`;
              const forwardToJsonDyn = `#pragma once
#if __has_include(<folly/json/dynamic.h>)
#include <folly/json/dynamic.h>
#elif __has_include("folly/json/dynamic.h")
#include "folly/json/dynamic.h"
#elif __has_include("json/dynamic.h")
#include "json/dynamic.h"
#endif
`;
              if (existsSync(jsonDyn) && !existsSync(dyn)) {
                await writeFile(dyn, forwardToJsonDyn, 'utf8');
              } else if (existsSync(dyn) && !existsSync(jsonDyn)) {
                const jsonDir = resolve(full, 'json');
                await mkdir(jsonDir, { recursive: true });
                await writeFile(resolve(jsonDir, 'dynamic.h'), forwardToDyn, 'utf8');
              } else if (existsSync(dyn) && existsSync(jsonDyn)) {
                const dynContent = await readFile(dyn, 'utf8');
                if (dynContent.length > 500) {
                  await writeFile(dyn, forwardToJsonDyn, 'utf8');
                }
              }
            }
            await sanitizeHeaders(full);
          } else if (ent.isFile() && ent.name === 'ExpoModulesCore_umbrella.h') {
            let content = await readFile(full, 'utf8');
            let filtered = content
              .replace(/^[ \t]*#import[ \t]+"ExpoViewComponentDescriptor\.h"[ \t]*\r?\n?/gm, '')
              .replace(/^[ \t]*#import[ \t]+"ExpoViewEventEmitter\.h"[ \t]*\r?\n?/gm, '')
              .replace(/^[ \t]*#import[ \t]+"ExpoViewProps\.h"[ \t]*\r?\n?/gm, '')
              .replace(/^[ \t]*#import[ \t]+"ExpoViewShadowNode\.h"[ \t]*\r?\n?/gm, '')
              .replace(/^[ \t]*#import[ \t]+"ExpoViewState\.h"[ \t]*\r?\n?/gm, '')
              .replace(/^[ \t]*#import[ \t]+"SwiftUIViewProps\.h"[ \t]*\r?\n?/gm, '')
              .replace(/^[ \t]*#import[ \t]+"TestingSyncJSCallInvoker\.h"[ \t]*\r?\n?/gm, '');
            if (!filtered.includes('"EXHostWrapper.h"') && filtered.includes('"ExpoModulesCore.h"')) {
              filtered = filtered.replace('#import "ExpoModulesCore.h"', '#import "EXHostWrapper.h"\n#import "ExpoModulesCore.h"');
            }
            if (filtered !== content) {
              await writeFile(full, filtered, 'utf8');
              console.log(`[HanlinExpo] Sanitized ExpoModulesCore_umbrella.h: ${full}`);
            }
          } else if (ent.isFile() && ent.name === 'ExpoModulesCore.h') {
            let content = await readFile(full, 'utf8');
            let filtered = content
              .replace(/^[ \t]*#import[ \t]+<ExpoModulesCore\/SwiftUIViewProps\.h>[ \t]*\r?\n?/gm, '')
              .replace(/^[ \t]*#import[ \t]+"SwiftUIViewProps\.h"[ \t]*\r?\n?/gm, '');
            if (!filtered.includes('EXHostWrapper.h') && filtered.includes('ExpoFabricViewObjC.h')) {
              filtered = filtered.replace(/#import <ExpoModulesCore\/ExpoFabricViewObjC\.h>/, '#import <ExpoModulesCore/ExpoFabricViewObjC.h>\n#import <ExpoModulesCore/EXHostWrapper.h>');
            }
            if (filtered !== content) {
              await writeFile(full, filtered, 'utf8');
              console.log(`[HanlinExpo] Sanitized ExpoModulesCore.h: ${full}`);
            }
          } else if (ent.isFile() && ent.name === 'ExpoViewShadowNode.h') {
            let content = await readFile(full, 'utf8');
            let patched = content
              .replaceAll('dynamic_cast<const react::LayoutableShadowNode *>', 'static_cast<const react::LayoutableShadowNode *>')
              .replaceAll('dynamic_cast<const ExpoViewProps *>', 'static_cast<const ExpoViewProps *>')
              .replaceAll('dynamic_cast<const react::ViewProps *>', 'static_cast<const react::ViewProps *>');
            if (patched !== content) {
              await writeFile(full, patched, 'utf8');
              console.log(`[HanlinExpo] Sanitized ExpoViewShadowNode.h: ${full}`);
            }
          } else if (ent.isFile() && ent.name === 'RawProps.h') {
            let content = await readFile(full, 'utf8');
            let changed = false;
            if (content.includes('#include <folly/dynamic.h>') && !content.includes('__has_include(<folly/dynamic.h>)')) {
              content = content.replace(
                '#include <folly/dynamic.h>',
                `#if __has_include(<folly/dynamic.h>)
#include <folly/dynamic.h>
#elif __has_include(<folly/json/dynamic.h>)
#include <folly/json/dynamic.h>
#endif`
              );
              changed = true;
            }
            if (content.includes('JSIDynamic.h')) {
              content = content.replace(/^[ \t]*#include[ \t]+<jsi\/JSIDynamic\.h>[ \t]*\r?\n?/gm, '')
                .replace(/^[ \t]*#if[ \t]+__has_include\(<jsi\/JSIDynamic\.h>\)[\s\S]*?#endif[ \t]*\r?\n?/gm, '');
              changed = true;
            }
            if (changed) {
              await writeFile(full, content, 'utf8');
              console.log(`[HanlinExpo] Sanitized RawProps.h: ${full}`);
            }
          } else if (ent.isFile() && ent.name === 'ExpoFabricViewObjC.h') {
            let content = await readFile(full, 'utf8');
            if (content.includes('RCTViewComponentView.h') || content.includes('#ifdef __cplusplus')) {
              content = content.replace(
                /#ifdef __cplusplus[\s\S]*?#endif \/\/ __cplusplus/m,
                `#if TARGET_OS_OSX
#import <React/RCTUIKit.h>
@interface ExpoFabricViewObjC : RCTUIView
#else
@interface ExpoFabricViewObjC : UIView
#endif

/*
 * Called for mounting (attaching) a child component view inside \`self\` component view.
 * Declared in main interface (not category) so Swift subclasses can override.
 */
- (void)mountChildComponentView:(nonnull UIView *)childComponentView index:(NSInteger)index;

/*
 * Called for unmounting (detaching) a child component view from \`self\` component view.
 * Declared in main interface (not category) so Swift subclasses can override.
 */
- (void)unmountChildComponentView:(nonnull UIView *)childComponentView index:(NSInteger)index;

@end`
              );
              await writeFile(full, content, 'utf8');
              console.log(`[HanlinExpo] Sanitized ExpoFabricViewObjC.h: ${full}`);
            }
          } else if (ent.isFile() && ent.name === 'EXHostWrapper.h') {
            let content = await readFile(full, 'utf8');
            let changed = false;
            if (!content.includes('@class RCTHost;')) {
              content = content.replace('#import <ExpoModulesCore/Platform.h>', '#import <ExpoModulesCore/Platform.h>\n\n@class RCTHost;');
              changed = true;
            }
            if (content.includes('RCTHost.h')) {
              content = content.replace(/#ifdef __cplusplus[\s\S]*?#endif \/\/ __cplusplus/m, '');
              content = content.replace(/#if __has_include\([\s\S]*?#endif/gm, '');
              content = content.replace(/^[ \t]*#import[ \t]+[<"][^>"]*RCTHost\.h[>"][ \t]*\r?\n?/gm, '');
              changed = true;
            }
            if (changed) {
              await writeFile(full, content, 'utf8');
              console.log(`[HanlinExpo] Sanitized EXHostWrapper.h: ${full}`);
            }
          } else if (ent.isFile() && ent.name === 'RCTAppSetupUtils.h') {
            let content = await readFile(full, 'utf8');
            if (content.includes('#ifdef __cplusplus')) {
              content = content.replace(/#ifdef __cplusplus[\s\S]*?#endif \/\/ __cplusplus\r?\n?/m, '');
              await writeFile(full, content, 'utf8');
              console.log(`[HanlinExpo] Sanitized RCTAppSetupUtils.h for C++ interop module scan: ${full}`);
            }
          } else if (ent.isFile() && ent.name === 'RCTReactNativeFactory.h') {
            let content = await readFile(full, 'utf8');
            if (content.includes('defined(__cplusplus)') || content.includes('#ifdef __cplusplus')) {
              content = content
                .replace(/#if[ \t]+defined\(__cplusplus\)[\s\S]*?#endif[ \t]*(?:\/\/[^\r\n]*)?\r?\n?/gm, '')
                .replace(/#ifdef __cplusplus[\s\S]*?#endif[ \t]*(?:\/\/[^\r\n]*)?\r?\n?/gm, '');
              await writeFile(full, content, 'utf8');
              console.log(`[HanlinExpo] Sanitized RCTReactNativeFactory.h for C++ interop module scan: ${full}`);
            }
          } else if (ent.isFile() && ent.name === 'TraceEvent.h') {
            let content = await readFile(full, 'utf8');
            if (content.includes('"tracing/TracingCategory.h"') && !content.includes('__has_include("tracing/TracingCategory.h")')) {
              content = content.replace(
                '#include "tracing/TracingCategory.h"',
                `#if __has_include("TracingCategory.h")
#include "TracingCategory.h"
#elif __has_include("tracing/TracingCategory.h")
#include "tracing/TracingCategory.h"
#elif __has_include(<jsinspector-modern/tracing/TracingCategory.h>)
#include <jsinspector-modern/tracing/TracingCategory.h>
#endif`
              );
              await writeFile(full, content, 'utf8');
              console.log(`[HanlinExpo] Sanitized TraceEvent.h: ${full}`);
            }
          } else if (ent.isFile() && ent.name === 'TestingSyncJSCallInvoker.h') {
            let content = await readFile(full, 'utf8');
            if (content.includes('#include <ReactCommon/CallInvoker.h>') && !content.includes('__has_include(<ReactCommon/CallInvoker.h>)')) {
              const replacement = `#if __has_include(<ReactCommon/CallInvoker.h>)
#include <ReactCommon/CallInvoker.h>
#elif __has_include("ReactCommon/CallInvoker.h")
#include "ReactCommon/CallInvoker.h"
#elif __has_include(<React/CallInvoker.h>)
#include <React/CallInvoker.h>
#endif`;
              content = content.replace('#include <ReactCommon/CallInvoker.h>', replacement);
              await writeFile(full, content, 'utf8');
              console.log(`[HanlinExpo] Sanitized TestingSyncJSCallInvoker.h: ${full}`);
            }
          } else if (ent.isFile() && ent.name === 'React-umbrella.h') {
            let content = await readFile(full, 'utf8');
            if (content.includes('RCTInspectorNetworkHelper.h')) {
              content = content.replace(/^[ \t]*#import[ \t]+<React\/RCTInspectorNetworkHelper\.h>[ \t]*\r?\n?/gm, '// #import <React/RCTInspectorNetworkHelper.h>\n');
              await writeFile(full, content, 'utf8');
              console.log(`[HanlinExpo] Sanitized React-umbrella.h: ${full}`);
            }
          } else if (ent.isFile() && ent.name === 'RCTInspectorNetworkHelper.h') {
            let content = await readFile(full, 'utf8');
            if (content.includes('<jsinspector-modern/')) {
              content = content.replace(/<jsinspector-modern\/([^>]+)>/g, '"jsinspector-modern/$1"');
              await writeFile(full, content, 'utf8');
              console.log(`[HanlinExpo] Sanitized RCTInspectorNetworkHelper.h: ${full}`);
            }
          } else if (ent.isFile() && ent.name.endsWith('.h') && full.includes('jsinspector-modern')) {
            let content = await readFile(full, 'utf8');
            if (content.includes('<jsinspector-modern/')) {
              content = content.replace(/<jsinspector-modern\/([^>]+)>/g, '"$1"');
              await writeFile(full, content, 'utf8');
            }
          } else if (ent.isFile() && ent.name === 'hash_combine.h') {
            let content = await readFile(full, 'utf8');
            if (content.includes('concept Hashable') && !content.includes('__cpp_concepts')) {
              const compat = `#if defined(__cpp_concepts) && __cpp_concepts >= 201907L
template <typename T>
concept Hashable = !std::is_same_v<T, const char *> && (requires(T a) {
  { std::hash<T>{}(a) } -> std::convertible_to<std::size_t>;
});

template <Hashable T, Hashable... Rest>
void hash_combine(std::size_t &seed, const T &v, const Rest &...rest)
{
  seed ^= std::hash<T>{}(v) + 0x9e3779b9 + (seed << 6) + (seed >> 2);
  (hash_combine(seed, rest), ...);
}

template <Hashable T, Hashable... Args>
std::size_t hash_combine(const T &v, const Args &...args)
{
  std::size_t seed = 0;
  hash_combine<T, Args...>(seed, v, args...);
  return seed;
}

template <Hashable... Ts>
  requires(sizeof...(Ts) <= 32)
void hash_combine_optionals(std::size_t &seed, const std::optional<Ts> &...optionals)
{
  std::uint32_t presence = 0;
  std::uint32_t bit = 1;
  ((presence |= optionals.has_value() ? bit : 0u, bit <<= 1), ...);
  std::size_t optionalsSeed = presence;

  auto combineIfEngaged = [&optionalsSeed](const auto &optional) {
    if (optional.has_value()) {
      hash_combine(optionalsSeed, *optional);
    }
  };
  (combineIfEngaged(optionals), ...);
  hash_combine(seed, optionalsSeed);
}
#else
template <typename T, typename... Rest>
void hash_combine(std::size_t &seed, const T &v, const Rest &...rest)
{
  seed ^= std::hash<T>{}(v) + 0x9e3779b9 + (seed << 6) + (seed >> 2);
  if constexpr (sizeof...(rest) > 0) {
    hash_combine(seed, rest...);
  }
}

template <typename T, typename... Args>
std::size_t hash_combine(const T &v, const Args &...args)
{
  std::size_t seed = 0;
  hash_combine(seed, v, args...);
  return seed;
}

template <typename... Ts>
void hash_combine_optionals(std::size_t &seed, const std::optional<Ts> &...optionals)
{
  static_assert(sizeof...(Ts) <= 32, "Ts count must be <= 32");
  std::uint32_t presence = 0;
  std::uint32_t bit = 1;
  ((presence |= optionals.has_value() ? bit : 0u, bit <<= 1), ...);
  std::size_t optionalsSeed = presence;

  auto combineIfEngaged = [&optionalsSeed](const auto &optional) {
    if (optional.has_value()) {
      hash_combine(optionalsSeed, *optional);
    }
  };
  (combineIfEngaged(optionals), ...);
  hash_combine(seed, optionalsSeed);
}
#endif

} // namespace facebook::react`;
              content = content.replace(
                /template <typename T>\s*concept Hashable[\s\S]*?\}\s*\/\/\s*namespace facebook::react/,
                compat
              );
              await writeFile(full, content, 'utf8');
              console.log(`[HanlinExpo] Sanitized hash_combine.h for C++17 compatibility: ${full}`);
            }
          } else if (ent.isFile() && ent.name === 'react_native_assert.h') {
            let content = await readFile(full, 'utf8');
            if (content.includes('#include <glog/logging.h>') && !content.includes('__has_include(<glog/logging.h>)')) {
              content = content.replace(
                '#include <glog/logging.h>',
                '#if __has_include(<glog/logging.h>)\n#include <glog/logging.h>\n#else\n#define GLOG_NO_ABBREVIATED_SEVERITIES\n#endif'
              );
              content = content.replace(
                '#define react_native_assert(cond)',
                '#if !__has_include(<glog/logging.h>)\n#define react_native_assert(cond) assert(cond)\n#else\n#define react_native_assert(cond)'
              );
              content = content.replace(
                /  \}\r?\n\r?\n#endif \/\/ platforms besides __ANDROID__/,
                '  }\n#endif\n\n#endif // platforms besides __ANDROID__'
              );
              await writeFile(full, content, 'utf8');
              console.log(`[HanlinExpo] Sanitized react_native_assert.h for optional glog: ${full}`);
            }
          } else if (ent.isFile() && ent.name === 'fnv1a.h') {
            let content = await readFile(full, 'utf8');
            if (content.includes('std::identity') && !content.includes('fnv1a_identity')) {
              const replacement = `#if defined(__cpp_lib_identity) || (defined(__cplusplus) && __cplusplus >= 202002L)
template <typename CharTransformT = std::identity>
#else
struct fnv1a_identity {
  template <typename T>
  constexpr auto&& operator()(T&& val) const noexcept {
    return static_cast<T&&>(val);
  }
};
template <typename CharTransformT = fnv1a_identity>
#endif`;
              content = content.replace('template <typename CharTransformT = std::identity>', replacement);
              await writeFile(full, content, 'utf8');
              console.log(`[HanlinExpo] Sanitized fnv1a.h for C++17 compatibility: ${full}`);
            }
          } else if (ent.isFile() && ent.name.endsWith('.h')) {
            let content = await readFile(full, 'utf8');
            let changed = false;
            if (content.includes('#include <folly/dynamic.h>') && !content.includes('__has_include(<folly/dynamic.h>)')) {
              const replacement = `#if __has_include(<folly/dynamic.h>)
#include <folly/dynamic.h>
#elif __has_include(<folly/json/dynamic.h>)
#include <folly/json/dynamic.h>
#endif`;
              content = content.replace(/#include <folly\/dynamic\.h>/g, replacement);
              changed = true;
            }
            if (content.includes('#else\n#include <folly/dynamic.h>\n#endif') || content.includes('#else\r\n#include <folly/dynamic.h>\r\n#endif')) {
              content = content.replace(/^[ \t]*#else[ \t]*\r?\n[ \t]*#include[ \t]+<folly\/dynamic\.h>[ \t]*\r?\n/gm, '');
              changed = true;
            }
            if (content.includes('#include <jsi/JSIDynamic.h>') && !content.includes('__has_include(<jsi/JSIDynamic.h>)')) {
              const replacement = `#if __has_include(<jsi/JSIDynamic.h>)
#include <jsi/JSIDynamic.h>
#endif`;
              content = content.replace(/#include <jsi\/JSIDynamic\.h>/g, replacement);
              changed = true;
            }
            if (content.includes('<jsinspector-modern/')) {
              content = content.replace(/<jsinspector-modern\/([^>]+)>/g, '"jsinspector-modern/$1"');
              changed = true;
            }
            if (changed) {
              await writeFile(full, content, 'utf8');
              console.log(`[HanlinExpo] Sanitized dynamic and inspector includes: ${full}`);
            }
          }
        }
      };

      await sanitizeHeaders(modularFwsRoot);
      await sanitizeHeaders(resolve(artifactsRoot, 'React.xcframework'));
      await sanitizeHeaders(resolve(artifactsRoot, 'ReactNativeHeaders.xcframework'));
      if (existsSync(resolve(artifactsRoot, 'ReactModularHeaders'))) {
        await sanitizeHeaders(resolve(artifactsRoot, 'ReactModularHeaders'));
      }
      if (existsSync(resolve(artifactsRoot, 'ReactNativeDependencies.xcframework'))) {
        await sanitizeHeaders(resolve(artifactsRoot, 'ReactNativeDependencies.xcframework'));
      }
      if (existsSync(resolve(artifactsRoot, 'ExpoModulesCore.xcframework'))) {
        await sanitizeHeaders(resolve(artifactsRoot, 'ExpoModulesCore.xcframework'));
      }

      count++;
      console.log('[HanlinExpo] Created unified non-modular react.framework in ModularFrameworks and enriched React.xcframework.');

      // Strip dummy cxxstableapi guards that reference non-existent react.framework headers
      for (const fw of await readdir(modularFwsRoot, { withFileTypes: true })) {
        if (!fw.isDirectory()) continue;
        const hDir = resolve(modularFwsRoot, fw.name, 'Headers');
        if (!existsSync(hDir)) continue;
        for (const hFile of await readdir(hDir, { withFileTypes: true })) {
          if (!hFile.isFile() || !hFile.name.endsWith('.h')) continue;
          const fullPath = resolve(hDir, hFile.name);
          let hContent = await readFile(fullPath, 'utf8');
          if (hContent.includes('cxxstableapi/')) {
            hContent = hContent.replace(/^[ \t]*#include[ \t]+<react\/cxxstableapi\/[^>]+>[ \t]*\r?\n?/gm, '');
            await writeFile(fullPath, hContent, 'utf8');
          }
        }
      }

      console.log(`[HanlinExpo] Created ${count} modular frameworks from ReactNativeHeaders modulemap.`);

      // Ensure nested fallback directory exists for $(SRCROOT)/Packages/HanlinExpoRuntime evaluation
      const nestedFallbackDir = resolve(artifactsRoot, '..', 'Packages', 'HanlinExpoRuntime');
      await mkdir(nestedFallbackDir, { recursive: true });
      const nestedFallbackArtifacts = resolve(nestedFallbackDir, 'Artifacts');
      await rm(resolve(nestedFallbackArtifacts, 'ModularFrameworks'), { recursive: true, force: true });
      await mkdir(nestedFallbackArtifacts, { recursive: true });
      await cp(modularFwsRoot, resolve(nestedFallbackArtifacts, 'ModularFrameworks'), { recursive: true });
      console.log('[HanlinExpo] ModularFrameworks nested fallback staged successfully.');
    }
    await stageModularFrameworks();

    if (process.platform === 'darwin') {
      console.log('[HanlinExpo] Building ExpoModulesJSI.xcframework for iOS device and simulator on macOS...');
      const expoModulesJSIRoot = resolve(scriptRoot, 'node_modules', 'expo-modules-jsi');
      if (existsSync(expoModulesJSIRoot)) {
        const podsRoot = resolve(scriptRoot, '.pods-root');
        await rm(podsRoot, { recursive: true, force: true });

        const publicHeaders = resolve(podsRoot, 'Headers', 'Public');
        await mkdir(publicHeaders, { recursive: true });

        // Set up React-jsi headers expected by build-xcframework.sh and Package.swift
        const rnRoot = resolve(scriptRoot, 'node_modules', 'react-native');
        const reactJsiHeaders = resolve(publicHeaders, 'React-jsi', 'jsi');
        await mkdir(reactJsiHeaders, { recursive: true });
        await cp(resolve(rnRoot, 'ReactCommon', 'jsi', 'jsi'), reactJsiHeaders, { recursive: true });

        // Set up hermes-engine headers
        const hermesHeaders = resolve(publicHeaders, 'hermes-engine', 'hermes');
        await mkdir(hermesHeaders, { recursive: true });
        const rnHeadersRoot = resolve(artifactsRoot, 'ReactNativeHeaders.xcframework', 'ios-arm64_x86_64-simulator', 'Headers');
        if (existsSync(resolve(rnHeadersRoot, 'hermes'))) {
          await cp(resolve(rnHeadersRoot, 'hermes'), hermesHeaders, { recursive: true });
        }

        // Set up cxxreact headers (provides cxxreact/ReactNativeVersion.h)
        if (existsSync(resolve(rnHeadersRoot, 'cxxreact'))) {
          await cp(resolve(rnHeadersRoot, 'cxxreact'), resolve(publicHeaders, 'cxxreact'), { recursive: true });
        }
        if (existsSync(resolve(rnHeadersRoot, 'ReactCommon'))) {
          await cp(resolve(rnHeadersRoot, 'ReactCommon'), resolve(publicHeaders, 'ReactCommon'), { recursive: true });
        }
        if (existsSync(resolve(rnHeadersRoot, 'jsinspector-modern'))) {
          await cp(resolve(rnHeadersRoot, 'jsinspector-modern'), resolve(publicHeaders, 'jsinspector-modern'), { recursive: true });
        }
        if (existsSync(resolve(rnHeadersRoot, 'reacthermes'))) {
          await cp(resolve(rnHeadersRoot, 'reacthermes'), resolve(publicHeaders, 'reacthermes'), { recursive: true });
        }
        if (existsSync(resolve(rnHeadersRoot, 'react'))) {
          await cp(resolve(rnHeadersRoot, 'react'), resolve(publicHeaders, 'react'), { recursive: true });
        }

        // Set up dependencies (Folly, fmt, fast_float, glog, DoubleConversion)
        const rnDepsHeaders = resolve(artifactsRoot, 'ReactNativeDependencies.xcframework', 'Headers');
        if (existsSync(rnDepsHeaders)) {
          if (existsSync(resolve(rnDepsHeaders, 'folly'))) {
            await cp(resolve(rnDepsHeaders, 'folly'), resolve(publicHeaders, 'RCT-Folly', 'folly'), { recursive: true });
          }
          if (existsSync(resolve(rnDepsHeaders, 'fmt'))) {
            await cp(resolve(rnDepsHeaders, 'fmt'), resolve(publicHeaders, 'fmt'), { recursive: true });
          }
          if (existsSync(resolve(rnDepsHeaders, 'fast_float'))) {
            await cp(resolve(rnDepsHeaders, 'fast_float'), resolve(publicHeaders, 'fast_float'), { recursive: true });
          }
          if (existsSync(resolve(rnDepsHeaders, 'glog'))) {
            await cp(resolve(rnDepsHeaders, 'glog'), resolve(publicHeaders, 'glog'), { recursive: true });
          }
          if (existsSync(resolve(rnDepsHeaders, 'double-conversion'))) {
            await cp(resolve(rnDepsHeaders, 'double-conversion'), resolve(publicHeaders, 'DoubleConversion'), { recursive: true });
          }
        }

        const buildScript = resolve(expoModulesJSIRoot, 'apple', 'scripts', 'build-xcframework.sh');
        const generateScript = resolve(expoModulesJSIRoot, 'apple', 'scripts', 'generate-modulemap.sh');
        const helpersScript = resolve(expoModulesJSIRoot, 'apple', 'scripts', 'xcframework-helpers.sh');
        if (existsSync(buildScript)) {
          let scriptContent = await readFile(buildScript, 'utf8');
          if (!scriptContent.includes('CODE_SIGNING_REQUIRED=NO')) {
            scriptContent = scriptContent.replace(
              'CLANG_COVERAGE_MAPPING=NO \\',
              'CLANG_COVERAGE_MAPPING=NO \\\n    CODE_SIGNING_REQUIRED=NO \\\n    CODE_SIGNING_ALLOWED=NO \\\n    CODE_SIGN_IDENTITY="" \\'
            );
          }
          if (scriptContent.includes('/^extension __ObjC\\./')) {
            scriptContent = scriptContent.replace(
              '/^extension __ObjC\\./',
              '/^extension __ObjC/'
            );
          }
          await writeFile(buildScript, scriptContent, 'utf8');
          await chmod(buildScript, 0o755);
        }
        if (existsSync(generateScript)) {
          await chmod(generateScript, 0o755);
        }
        if (existsSync(helpersScript)) {
          await chmod(helpersScript, 0o755);
        }

        execSync(`bash "${buildScript}"`, {
          env: {
            ...process.env,
            PODS_ROOT: podsRoot,
            RN_ROOT: rnRoot,
          },
          stdio: 'inherit'
        });

        const builtXCFramework = resolve(expoModulesJSIRoot, 'apple', 'Products', 'ExpoModulesJSI.xcframework');
        if (!existsSync(builtXCFramework)) {
          throw new Error(`[HanlinExpo] Expected built ExpoModulesJSI.xcframework at ${builtXCFramework}`);
        }
        const targetJsiXcf = resolve(artifactsRoot, 'ExpoModulesJSI.xcframework');
        await rm(targetJsiXcf, { recursive: true, force: true });
        await cp(builtXCFramework, targetJsiXcf, { recursive: true, verbatimSymlinks: true });
        console.log('[HanlinExpo] ExpoModulesJSI.xcframework built and staged successfully.');
      }
    }

    async function cleanSwiftInterfaces(dir) {
      if (!existsSync(dir)) return;
      const entries = await readdir(dir, { withFileTypes: true });
      for (const entry of entries) {
        const fullPath = resolve(dir, entry.name);
        if (entry.isDirectory()) {
          await cleanSwiftInterfaces(fullPath);
        } else if (entry.name.endsWith('.swiftinterface')) {
          let content = await readFile(fullPath, 'utf8');
          let cleaned = content.replace(/^extension\s+__ObjC[\s\S]*?^}[^\S\r\n]*\r?\n?/gm, '');
          cleaned = cleaned.replaceAll('(ExpoModulesCore.FunctionCallResult) ->', '(borrowing ExpoModulesCore.FunctionCallResult) ->');
          cleaned = cleaned.replaceAll('(FunctionCallResult) ->', '(borrowing FunctionCallResult) ->');
          cleaned = cleaned.replace(/:\s+((?:ExpoModulesJSI\.)?JavaScriptValue\b)/g, ': borrowing $1');
          if (cleaned !== content) {
            await writeFile(fullPath, cleaned, 'utf8');
            console.log(`[HanlinExpo] Stripped unresolved __ObjC extension and added ownership to noncopyable Result/Value in ${entry.name}`);
          }
        }
      }
    }
    await cleanSwiftInterfaces(artifactsRoot);

    for (const item of lock.artifacts) {
      const xcfPath = resolve(repositoryRoot, item.target);
      await signAndVerifyXCFramework(xcfPath);
      console.log(
        `[HanlinExpo] Normalized${process.platform === 'darwin' ? ', signed,' : ''} and verified ${basename(xcfPath)}`
      );
    }

    const configXcconfigPath = resolve(repositoryRoot, 'Config.xcconfig');
    if (existsSync(configXcconfigPath)) {
      const existingConfig = await readFile(configXcconfigPath, 'utf8');
      if (!existingConfig.includes('ModularFrameworks')) {
        const repoRootPosix = repositoryRoot.replace(/\\/g, '/');
        const expoXcconfigBlock = [
          '',
          'SWIFT_ENABLE_EXPLICIT_MODULES = NO',
          'SWIFT_OBJC_INTEROP_MODE = objcxx',
          `FRAMEWORK_SEARCH_PATHS = "${repoRootPosix}/Packages/HanlinExpoRuntime/Artifacts/ModularFrameworks" "${repoRootPosix}/Artifacts/ModularFrameworks" "$(SRCROOT)/Packages/HanlinExpoRuntime/Artifacts/ModularFrameworks" "$(SRCROOT)/Artifacts/ModularFrameworks" $(inherited)`,
          `HEADER_SEARCH_PATHS = "${repoRootPosix}/Packages/HanlinExpoRuntime/Artifacts/ReactModularHeaders" "${repoRootPosix}/Artifacts/ReactModularHeaders" "${repoRootPosix}/Packages/HanlinExpoRuntime/Artifacts/ModularFrameworks/react.framework/Headers" "${repoRootPosix}/Packages/HanlinExpoRuntime/Artifacts/ModularFrameworks/react.framework/Headers/react" "$(SRCROOT)/Packages/HanlinExpoRuntime/Artifacts/ReactModularHeaders" "$(SRCROOT)/Artifacts/ReactModularHeaders" $(inherited) "$(BUILT_PRODUCTS_DIR)/React.framework/Headers" "$(BUILT_PRODUCTS_DIR)/ExpoModulesCore.framework/Headers" "$(BUILT_PRODUCTS_DIR)/Python.framework/Headers"`,
          'CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES = YES',
          'CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = NO',
          'WARNING_CFLAGS = $(inherited) -Wno-quoted-include-in-framework-header -Wno-non-modular-include-in-framework-module',
          'OTHER_CFLAGS = $(inherited) -Wno-quoted-include-in-framework-header -Wno-non-modular-include-in-framework-module',
          `OTHER_SWIFT_FLAGS = -Xcc -F"${repoRootPosix}/Packages/HanlinExpoRuntime/Artifacts/ModularFrameworks" -Xcc -F"${repoRootPosix}/Artifacts/ModularFrameworks" -Xcc -I"${repoRootPosix}/Packages/HanlinExpoRuntime/Artifacts/ReactModularHeaders" -Xcc -I"${repoRootPosix}/Artifacts/ReactModularHeaders" -Xcc -I"${repoRootPosix}/Packages/HanlinExpoRuntime/Artifacts/ModularFrameworks/react.framework/Headers" -Xcc -I"${repoRootPosix}/Packages/HanlinExpoRuntime/Artifacts/ModularFrameworks/react.framework/Headers/react" -Xcc -F"$(SRCROOT)/Packages/HanlinExpoRuntime/Artifacts/ModularFrameworks" -Xcc -F"$(SRCROOT)/Artifacts/ModularFrameworks" $(inherited) -Xcc -Wno-quoted-include-in-framework-header -Xcc -Wno-non-modular-include-in-framework-module -Xcc -I"$(BUILT_PRODUCTS_DIR)/React.framework/Headers" -Xcc -I"$(BUILT_PRODUCTS_DIR)/ExpoModulesCore.framework/Headers"`,
          '',
        ].join('\n');
        await writeFile(configXcconfigPath, existingConfig + expoXcconfigBlock, 'utf8');
        console.log('[HanlinExpo] Enriched Config.xcconfig with ModularFrameworks search paths and interop flags.');
      }
    }
  } finally {
    await rm(tempDir, { recursive: true, force: true });
  }
}

const isMainModule =
  process.argv[1] && resolve(fileURLToPath(import.meta.url)) === resolve(process.argv[1]);

if (isMainModule) {
  prepare()
    .then(async () => {
      const nativeApiPrep = resolve(repositoryRoot, 'Scripts', 'ExpoNativeAPI', 'prepare-ios-dependencies.mjs');
      if (existsSync(nativeApiPrep)) {
        const { default: prepNativeApi } = await import(pathToFileURL(nativeApiPrep).href);
        if (typeof prepNativeApi === 'function') {
          await prepNativeApi();
        }
      }
      process.exit(0);
    })
    .catch((err) => {
      console.error('[HanlinExpo] Preparation failed:', err);
      process.exit(1);
    });
}
