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

      // Copy ReactNativeDependencies headers (glog, folly, fmt, fast_float, double-conversion, etc.)
      const allSlices = ['ios-arm64_x86_64-simulator', 'ios-arm64', 'ios-arm64_x86_64-maccatalyst'];
      const depSources = [
        resolve(artifactsRoot, 'ReactNativeDependencies.xcframework', 'Headers'),
        ...allSlices.map(s => resolve(artifactsRoot, 'ReactNativeDependencies.xcframework', s, 'Headers'))
      ];

      const copyDeps = async (destDir) => {
        for (const depSrc of depSources) {
          if (existsSync(depSrc)) {
            const entries = await readdir(depSrc, { withFileTypes: true });
            for (const ent of entries) {
              if (ent.name.endsWith('.modulemap')) continue;
              const src = resolve(depSrc, ent.name);
              const dst = resolve(destDir, ent.name);
              await cp(src, dst, { recursive: true });
            }
          }
        }
        if (existsSync(resolve(destDir, 'double-conversion')) && !existsSync(resolve(destDir, 'DoubleConversion'))) {
          await cp(resolve(destDir, 'double-conversion'), resolve(destDir, 'DoubleConversion'), { recursive: true });
        }
        if (existsSync(resolve(destDir, 'folly')) && !existsSync(resolve(destDir, 'RCT-Folly', 'folly'))) {
          await cp(resolve(destDir, 'folly'), resolve(destDir, 'RCT-Folly', 'folly'), { recursive: true });
        }
      };

      await copyDeps(reactHeadersDir);

      const reactCapFwDir = resolve(modularFwsRoot, 'React.framework');
      if (!existsSync(reactCapFwDir)) {
        await cp(reactFwDir, reactCapFwDir, { recursive: true });
      } else {
        await copyDeps(resolve(reactCapFwDir, 'Headers'));
      }

      // Also enrich React.xcframework itself with all headers from ReactNativeHeaders and ReactNativeDependencies across all slices
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
          await copyDeps(targetHeaders);
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

      // Sanitize headers to prevent Clang module errors with non-modular C++ jsinspector-modern and cmark-gfm utf8.h collision
      const sanitizeHeaders = async (dir) => {
        if (!existsSync(dir)) return;
        const u = resolve(dir, 'jsinspector-modern', 'Utf8.h');
        if (existsSync(u)) {
          await rm(u, { force: true });
          console.log(`[HanlinExpo] Removed colliding Utf8.h from ${dir}`);
        }
        const umb = resolve(dir, 'React-umbrella.h');
        if (existsSync(umb)) {
          let content = await readFile(umb, 'utf8');
          const stripped = content.replace(/^[ \t]*#import[ \t]+<React\/RCTInspectorNetworkHelper\.h>[ \t]*\r?\n?/gm, '');
          if (stripped !== content) {
            await writeFile(umb, stripped, 'utf8');
            console.log(`[HanlinExpo] Stripped RCTInspectorNetworkHelper.h from ${umb}`);
          }
        }
        const hlp = resolve(dir, 'RCTInspectorNetworkHelper.h');
        if (existsSync(hlp)) {
          let content = await readFile(hlp, 'utf8');
          const stripped = content.replace(/^[ \t]*#import[ \t]+<jsinspector-modern\/ReactCdp\.h>[ \t]*\r?\n?/gm, '// #import <jsinspector-modern/ReactCdp.h>\n');
          if (stripped !== content) {
            await writeFile(hlp, stripped, 'utf8');
            console.log(`[HanlinExpo] Neutralized non-modular jsinspector import in ${hlp}`);
          }
        }
      };
      await sanitizeHeaders(reactHeadersDir);
      if (existsSync(resolve(reactCapFwDir, 'Headers'))) {
        await sanitizeHeaders(resolve(reactCapFwDir, 'Headers'));
      }
      for (const s of allSlices) {
        await sanitizeHeaders(resolve(artifactsRoot, 'React.xcframework', s, 'React.framework', 'Headers'));
        await sanitizeHeaders(resolve(artifactsRoot, 'ReactNativeHeaders.xcframework', s, 'Headers'));
      }

      // 1. Neutralize C++20 concepts in hash_combine.h across all staged artifacts
      const patchHashCombine = async (dir) => {
        if (!existsSync(dir)) return;
        const entries = await readdir(dir, { withFileTypes: true });
        for (const entry of entries) {
          const fullPath = resolve(dir, entry.name);
          if (entry.isDirectory()) {
            await patchHashCombine(fullPath);
          } else if (entry.name === 'hash_combine.h') {
            let content = await readFile(fullPath, 'utf8');
            if (content.includes('concept Hashable')) {
              content = content.replace(/template\s*<\s*typename\s+T\s*>\s*concept\s+Hashable\s*=\s*[\s\S]*?\);/g, '// concept Hashable disabled for C++17/interop compatibility');
              content = content.replace(/template\s*<\s*Hashable\s+T\s*,\s*Hashable\.\.\.\s*Rest\s*>/g, 'template <typename T, typename... Rest>');
              content = content.replace(/template\s*<\s*Hashable\s+T\s*,\s*Hashable\.\.\.\s*Args\s*>/g, 'template <typename T, typename... Args>');
              await writeFile(fullPath, content, 'utf8');
              console.log(`[HanlinExpo] Neutralized C++20 concept in ${fullPath}`);
            }
          }
        }
      };
      await patchHashCombine(artifactsRoot);

      // 2. Strip internal C++ ContentOriginRegistry.h from ExpoModulesCore_umbrella.h
      const patchExpoUmbrellas = async (dir) => {
        if (!existsSync(dir)) return;
        const entries = await readdir(dir, { withFileTypes: true });
        for (const entry of entries) {
          const fullPath = resolve(dir, entry.name);
          if (entry.isDirectory()) {
            await patchExpoUmbrellas(fullPath);
          } else if (entry.name === 'ExpoModulesCore_umbrella.h') {
            let content = await readFile(fullPath, 'utf8');
            const stripped = content.replace(/^[ \t]*#import[ \t]+["<]ContentOriginRegistry\.h[">][ \t]*\r?\n?/gm, '');
            if (stripped !== content) {
              await writeFile(fullPath, stripped, 'utf8');
              console.log(`[HanlinExpo] Stripped ContentOriginRegistry.h from ${fullPath}`);
            }
          }
        }
      };
      await patchExpoUmbrellas(artifactsRoot);

      // Remove stale code signatures and re-sign ad-hoc if on darwin/codesign is available
      const reactXcf = resolve(artifactsRoot, 'React.xcframework');
      if (existsSync(reactXcf)) {
        const removeCodeSig = async (dir) => {
          if (!existsSync(dir)) return;
          const entries = await readdir(dir, { withFileTypes: true });
          for (const ent of entries) {
            const fullPath = resolve(dir, ent.name);
            if (ent.isDirectory()) {
              if (ent.name === '_CodeSignature') {
                await rm(fullPath, { recursive: true, force: true });
              } else {
                await removeCodeSig(fullPath);
              }
            }
          }
        };
        await removeCodeSig(reactXcf);
        if (process.platform === 'darwin') {
          try {
            for (const s of allSlices) {
              const fw = resolve(reactXcf, s, 'React.framework');
              if (existsSync(fw)) {
                execSync(`codesign --force --sign - --timestamp=none "${fw}"`, { stdio: 'ignore' });
              }
            }
            execSync(`codesign --force --sign - --timestamp=none "${reactXcf}"`, { stdio: 'ignore' });
            console.log('[HanlinExpo] Re-signed React.xcframework ad-hoc.');
          } catch (signErr) {
            console.warn('[HanlinExpo] Warning: ad-hoc codesign failed:', signErr.message);
          }
        }
      }

      const rnHeadersXcf = resolve(artifactsRoot, 'ReactNativeHeaders.xcframework');
      if (existsSync(rnHeadersXcf)) {
        const removeCodeSig = async (dir) => {
          if (!existsSync(dir)) return;
          const entries = await readdir(dir, { withFileTypes: true });
          for (const ent of entries) {
            const fullPath = resolve(dir, ent.name);
            if (ent.isDirectory()) {
              if (ent.name === '_CodeSignature') {
                await rm(fullPath, { recursive: true, force: true });
              } else {
                await removeCodeSig(fullPath);
              }
            }
          }
        };
        await removeCodeSig(rnHeadersXcf);
        if (process.platform === 'darwin') {
          try {
            execSync(`codesign --force --sign - --timestamp=none "${rnHeadersXcf}"`, { stdio: 'ignore' });
            console.log('[HanlinExpo] Re-signed ReactNativeHeaders.xcframework ad-hoc.');
          } catch (signErr) {
            console.warn('[HanlinExpo] Warning: ad-hoc codesign failed for ReactNativeHeaders:', signErr.message);
          }
        }
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
        if (entry.isDirectory() && entry.name.endsWith('.xcframework')) {
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

            try { execSync(`codesign --remove-signature "${fwPath}"`, { stdio: 'ignore' }); } catch (_) {}
            try { execSync(`codesign --force --deep --sign - "${fwPath}"`, { stdio: 'ignore' }); } catch (_) {}

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
