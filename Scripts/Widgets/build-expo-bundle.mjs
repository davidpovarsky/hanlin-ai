import { createRequire } from 'node:module';
import path from 'node:path';
import fs from 'node:fs/promises';
import { existsSync } from 'node:fs';

const require = createRequire(import.meta.url);
const repoRoot = path.resolve(import.meta.dirname, '../..');
const esbuild = require(path.join(repoRoot, 'Scripts/Expo/node_modules/esbuild'));

// Upstream expo-widgets source location
const packageRoot = path.join(repoRoot, 'scratch/expo-widgets-source/package');
const fallbackPackageRoot = path.resolve('C:/Users/DAVID/.gemini/antigravity/brain/ec337a59-3bc1-4f74-b199-e8057268ddd6/scratch/expo-widgets-source/package');
const resolvedPackageRoot = existsSync(packageRoot) ? packageRoot : fallbackPackageRoot;

const bundleDir = path.join(resolvedPackageRoot, 'bundle');
const entryPoint = path.join(bundleDir, 'index.ts');

const emptyPlugin = {
  name: 'empty-resolver',
  setup(build) {
    build.onResolve({ filter: /^react-native\/.+/ }, () => ({ path: 'empty-rn', namespace: 'empty' }));
    build.onResolve({ filter: /^react-native-worklets$|^react-native-reanimated$|^@expo\/ui\/jetpack-compose$/ }, () => ({ path: 'empty-pkg', namespace: 'empty' }));
    build.onLoad({ filter: /.*/, namespace: 'empty' }, () => ({ contents: 'module.exports = {};', loader: 'js' }));
  }
};

async function buildExpoWidgetsBundle() {
  console.log('[HanlinWidgets] Bundling ExpoWidgets.bundle with esbuild...');

  const result = await esbuild.build({
    entryPoints: [entryPoint],
    bundle: true,
    write: false,
    format: 'iife',
    minify: false, // Keep readable for inspection/debugging in development
    nodePaths: [path.join(repoRoot, 'Scripts/Expo/node_modules')],
    alias: {
      'expo': path.join(bundleDir, 'expo-stub.ts'),
      'expo-modules-core': path.join(bundleDir, 'expo-modules-core-stub.ts'),
      'react': path.join(bundleDir, 'react-stub.ts'),
      'react/jsx-runtime': path.join(bundleDir, 'jsx-runtime-stub.ts'),
      'react/jsx-dev-runtime': path.join(bundleDir, 'jsx-runtime-stub.ts'),
      'react-native': path.join(bundleDir, 'react-native-stub.ts'),
    },
    plugins: [emptyPlugin],
  });

  const bundleCode = result.outputFiles[0].text;
  console.log(`[HanlinWidgets] Bundle successfully generated (${bundleCode.length} bytes).`);

  const targets = [
    path.join(repoRoot, 'Packages/HanlinPlatform/Sources/HanlinScriptExtensions/Resources/ExpoWidgets.bundle'),
    path.join(repoRoot, 'HanlinScriptingWidgets/Resources/ExpoWidgets.bundle'),
  ];

  for (const target of targets) {
    await fs.mkdir(path.dirname(target), { recursive: true });
    await fs.writeFile(target, bundleCode, 'utf8');
    console.log(`[HanlinWidgets] Wrote ${target}`);
  }
}

buildExpoWidgetsBundle().catch(err => {
  console.error('[HanlinWidgets] Failed to build ExpoWidgets.bundle:', err);
  process.exit(1);
});
