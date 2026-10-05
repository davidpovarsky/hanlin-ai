import { createHash } from 'node:crypto';
import { access, chmod, cp, mkdir, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { createWriteStream, existsSync } from 'node:fs';
import { basename, resolve } from 'node:path';
import { execSync } from 'node:child_process';
import https from 'node:https';
import http from 'node:http';

const scriptRoot = resolve(import.meta.dirname);
const repositoryRoot = resolve(scriptRoot, '..', '..');
const artifactsRoot = resolve(repositoryRoot, 'Packages', 'HanlinExpoRuntime', 'Artifacts');
const lockPath = resolve(scriptRoot, 'dependency-lock.json');

const readJSON = async (path) => JSON.parse(await readFile(path, 'utf8'));
const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');

async function downloadFile(url, destPath) {
  return new Promise((res, rej) => {
    function get(currentURL) {
      const client = currentURL.startsWith('https') ? https : http;
      client.get(currentURL, { agent: false }, (response) => {
        if (response.statusCode >= 300 && response.statusCode < 400 && response.headers.location) {
          const redirectURL = new URL(response.headers.location, currentURL).toString();
          return get(redirectURL);
        }
        if (response.statusCode !== 200) {
          return rej(new Error(`Download failed with status ${response.statusCode} for ${currentURL}`));
        }
        const file = createWriteStream(destPath);
        response.pipe(file);
        file.on('finish', () => {
          file.close(() => res());
        });
      }).on('error', rej);
    }
    get(url);
  });
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
      if (existsSync(targetDir)) {
        console.log(`[HanlinExpo] ${item.name} already staged at ${item.target}`);
        continue;
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
        const subTarball = resolve(tempDir, basename(item.subpath));
        execSync(`tar -zxf "${downloadedPath}" -C "${tempDir}" "${item.subpath}"`);
        const extractedSub = resolve(tempDir, item.subpath);
        execSync(`tar -zxf "${extractedSub}" -C "${artifactsRoot}"`);
      } else if (item.source === 'npm-extract' || item.source === 'maven') {
        const unpackDir = resolve(tempDir, `unpack-${item.name}`);
        await mkdir(unpackDir, { recursive: true });
        execSync(`tar -zxf "${downloadedPath}" -C "${unpackDir}"`);
        const sourcePath = resolve(unpackDir, item.subpath);
        await cp(sourcePath, targetDir, { recursive: true });
      }
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
        for (const h of headerMatches) {
          moduleMapLines.push(`    header "${basename(h)}"`);
        }
        moduleMapLines.push('    export *');
        moduleMapLines.push('}');
        moduleMapLines.push('');

        await writeFile(resolve(modulesDir, 'module.modulemap'), moduleMapLines.join('\n'), 'utf8');
        count++;
      }

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
        if (existsSync(builtXCFramework)) {
          await cp(builtXCFramework, resolve(artifactsRoot, 'ExpoModulesJSI.xcframework'), { recursive: true });
          console.log('[HanlinExpo] ExpoModulesJSI.xcframework built and staged successfully.');
        }
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
          const content = await readFile(fullPath, 'utf8');
          const cleaned = content.replace(/^extension\s+__ObjC[\s\S]*?^}[^\S\r\n]*\r?\n?/gm, '');
          if (cleaned !== content) {
            await writeFile(fullPath, cleaned, 'utf8');
            console.log(`[HanlinExpo] Stripped unresolved __ObjC extension from ${entry.name}`);
          }
        }
      }
    }
    await cleanSwiftInterfaces(artifactsRoot);

    if (process.platform === 'darwin') {
      const artifactEntries = await readdir(artifactsRoot, { withFileTypes: true });
      for (const entry of artifactEntries) {
        if (entry.isDirectory() && entry.name.endsWith('.xcframework') && entry.name.startsWith('Expo')) {
          const fwPath = resolve(artifactsRoot, entry.name);
          try {
            let innerFws = [];
            try {
              const findOutput = execSync(`find "${fwPath}" -type d -name "*.framework"`, { encoding: 'utf8' });
              innerFws = findOutput.trim().split('\n').filter(Boolean);
            } catch (_) {}

            for (const inner of innerFws) {
              try { execSync(`codesign --remove-signature "${inner}"`, { stdio: 'ignore' }); } catch (_) {}
              try { execSync(`codesign --force --deep --sign - "${inner}"`, { stdio: 'ignore' }); } catch (_) {}
            }

            console.log(`[HanlinExpo] Ad-hoc re-signed ${entry.name}`);
          } catch (e) {
            console.log(`[HanlinExpo] Re-signing notice for ${entry.name}: ${e.message}`);
          }
        }
      }
    }
  } finally {
    await rm(tempDir, { recursive: true, force: true });
  }
}

prepare()
  .then(() => {
    process.exit(0);
  })
  .catch((err) => {
    console.error('[HanlinExpo] Preparation failed:', err);
    process.exit(1);
  });
