import { createHash } from 'node:crypto';
import { access, chmod, cp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
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

    if (process.platform === 'darwin') {
      console.log('[HanlinExpo] Building ExpoModulesJSI.xcframework for simulator on macOS...');
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
            PLATFORM_NAME: 'iphonesimulator',
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
