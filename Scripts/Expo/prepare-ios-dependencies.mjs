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

      // Also enrich React.xcframework itself with all headers from ReactNativeHeaders across all slices
      const allSlices = ['ios-arm64_x86_64-simulator', 'ios-arm64', 'ios-arm64_x86_64-maccatalyst'];
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
              if (existsSync(jsonDyn)) {
                await writeFile(dyn, await readFile(jsonDyn, 'utf8'), 'utf8');
              } else if (existsSync(dyn)) {
                const jsonDir = resolve(full, 'json');
                await mkdir(jsonDir, { recursive: true });
                await writeFile(resolve(jsonDir, 'dynamic.h'), await readFile(dyn, 'utf8'), 'utf8');
              }
            }
            await sanitizeHeaders(full);
          } else if (ent.isFile() && ent.name === 'ExpoModulesCore_umbrella.h') {
            let content = await readFile(full, 'utf8');
            const filtered = content
              .replace(/^[ \t]*#import[ \t]+"ExpoViewComponentDescriptor\.h"[ \t]*\r?\n?/gm, '')
              .replace(/^[ \t]*#import[ \t]+"ExpoViewEventEmitter\.h"[ \t]*\r?\n?/gm, '')
              .replace(/^[ \t]*#import[ \t]+"ExpoViewProps\.h"[ \t]*\r?\n?/gm, '')
              .replace(/^[ \t]*#import[ \t]+"ExpoViewShadowNode\.h"[ \t]*\r?\n?/gm, '')
              .replace(/^[ \t]*#import[ \t]+"ExpoViewState\.h"[ \t]*\r?\n?/gm, '')
              .replace(/^[ \t]*#import[ \t]+"SwiftUIViewProps\.h"[ \t]*\r?\n?/gm, '')
              .replace(/^[ \t]*#import[ \t]+"ExpoFabricViewObjC\.h"[ \t]*\r?\n?/gm, '')
              .replace(/^[ \t]*#import[ \t]+"EXHostWrapper\.h"[ \t]*\r?\n?/gm, '')
              .replace(/^[ \t]*#import[ \t]+"TestingSyncJSCallInvoker\.h"[ \t]*\r?\n?/gm, '');
            if (filtered !== content) {
              await writeFile(full, filtered, 'utf8');
              console.log(`[HanlinExpo] Sanitized ExpoModulesCore_umbrella.h: ${full}`);
            }
          } else if (ent.isFile() && ent.name === 'ExpoModulesCore.h') {
            let content = await readFile(full, 'utf8');
            const filtered = content
              .replace(/^[ \t]*#import[ \t]+<ExpoModulesCore\/SwiftUIViewProps\.h>[ \t]*\r?\n?/gm, '')
              .replace(/^[ \t]*#import[ \t]+"SwiftUIViewProps\.h"[ \t]*\r?\n?/gm, '')
              .replace(/^[ \t]*#import[ \t]+<ExpoModulesCore\/ExpoFabricViewObjC\.h>[ \t]*\r?\n?/gm, '')
              .replace(/^[ \t]*#import[ \t]+"ExpoFabricViewObjC\.h"[ \t]*\r?\n?/gm, '')
              .replace(/^[ \t]*#import[ \t]+<ExpoModulesCore\/EXHostWrapper\.h>[ \t]*\r?\n?/gm, '')
              .replace(/^[ \t]*#import[ \t]+"EXHostWrapper\.h"[ \t]*\r?\n?/gm, '');
            if (filtered !== content) {
              await writeFile(full, filtered, 'utf8');
              console.log(`[HanlinExpo] Sanitized ExpoModulesCore.h: ${full}`);
            }
          } else if (ent.isFile() && ent.name === 'RawProps.h') {
            let content = await readFile(full, 'utf8');
            if (content.includes('#include <folly/dynamic.h>') && !content.includes('__has_include(<folly/dynamic.h>)')) {
              content = content.replace(
                '#include <folly/dynamic.h>',
                `#if __has_include(<folly/dynamic.h>)
#include <folly/dynamic.h>
#elif __has_include(<folly/json/dynamic.h>)
#include <folly/json/dynamic.h>
#endif`
              );
              await writeFile(full, content, 'utf8');
              console.log(`[HanlinExpo] Sanitized RawProps.h: ${full}`);
            }
          } else if (ent.isFile() && ent.name === 'EXHostWrapper.h') {
            let content = await readFile(full, 'utf8');
            if (content.includes('#import <ReactCommon/RCTHost.h>') && !content.includes('@class RCTHost;')) {
              const replacement = `#if __has_include(<ReactCommon/RCTHost.h>)
#import <ReactCommon/RCTHost.h>
#elif __has_include("ReactCommon/RCTHost.h")
#import "ReactCommon/RCTHost.h"
#elif __has_include(<React/RCTHost.h>)
#import <React/RCTHost.h>
#else
@class RCTHost;
#endif`;
              content = content.replace('#import <ReactCommon/RCTHost.h>', replacement);
              await writeFile(full, content, 'utf8');
              console.log(`[HanlinExpo] Sanitized EXHostWrapper.h: ${full}`);
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
#else
#include <folly/dynamic.h>
#endif`;
              content = content.replace(/#include <folly\/dynamic\.h>/g, replacement);
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

      // Remove stale code signatures and re-sign ad-hoc if on darwin/codesign is available
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

      const resignXcf = async (xcfPath) => {
        if (!existsSync(xcfPath)) return;
        await removeCodeSig(xcfPath);
        if (process.platform === 'darwin') {
          try {
            const fws = [];
            const findFrameworks = async (p) => {
              if (!existsSync(p)) return;
              const entries = await readdir(p, { withFileTypes: true });
              for (const ent of entries) {
                const sub = resolve(p, ent.name);
                if (ent.isDirectory()) {
                  if (ent.name.endsWith('.framework')) {
                    fws.push(sub);
                  } else {
                    await findFrameworks(sub);
                  }
                }
              }
            };
            await findFrameworks(xcfPath);
            for (const fw of fws) {
              execSync(`codesign --force --sign - --timestamp=none "${fw}"`, { stdio: 'ignore' });
            }
            execSync(`codesign --force --sign - --timestamp=none "${xcfPath}"`, { stdio: 'ignore' });
            console.log(`[HanlinExpo] Re-signed ${basename(xcfPath)} ad-hoc.`);
          } catch (signErr) {
            console.warn(`[HanlinExpo] Warning: ad-hoc codesign failed for ${basename(xcfPath)}:`, signErr.message);
          }
        }
      };

      const xcfEntries = await readdir(artifactsRoot, { withFileTypes: true });
      for (const ent of xcfEntries) {
        if (ent.isDirectory() && ent.name.endsWith('.xcframework')) {
          await resignXcf(resolve(artifactsRoot, ent.name));
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
