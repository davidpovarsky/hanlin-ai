import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import ts from 'typescript';

const scriptRoot = resolve(import.meta.dirname);
const repositoryRoot = resolve(scriptRoot, '..', '..');
const expoRoot = resolve(scriptRoot, 'node_modules', '@expo', 'ui', 'build', 'swift-ui');
const outputPath = resolve(repositoryRoot, 'Tools', 'SwiftUIBridge', 'configuration.json');
const rulesPath = resolve(repositoryRoot, 'Tools', 'SwiftUIBridge', 'rules.json');
const reviewedCapabilitiesPath = resolve(repositoryRoot, 'Tools', 'SwiftUIBridge', 'expo-reviewed-capabilities.json');

function exportedCallableNames(entry, capitalized) {
  const program = ts.createProgram([entry], {
    allowJs: false,
    module: ts.ModuleKind.ESNext,
    moduleResolution: ts.ModuleResolutionKind.Bundler,
    noEmit: true,
    skipLibCheck: true,
  });
  const checker = program.getTypeChecker();
  const source = program.getSourceFile(entry);
  if (!source) throw new Error(`Unable to read Expo UI declarations at ${entry}`);
  const moduleSymbol = checker.getSymbolAtLocation(source);
  if (!moduleSymbol) throw new Error(`Unable to resolve Expo UI exports at ${entry}`);
  return checker.getExportsOfModule(moduleSymbol)
    .filter((symbol) => {
      const name = symbol.getName();
      if (!name || name === 'default') return false;
      if (capitalized !== /^[A-Z]/.test(name)) return false;
      const declaration = symbol.valueDeclaration ?? symbol.declarations?.[0];
      if (!declaration) return false;
      const type = checker.getTypeOfSymbolAtLocation(symbol, declaration);
      return checker.getSignaturesOfType(type, ts.SignatureKind.Call).length > 0;
    })
    .map((symbol) => symbol.getName())
    .sort();
}

const rules = JSON.parse(await readFile(rulesPath, 'utf8'));
const reviewedCapabilities = JSON.parse(await readFile(reviewedCapabilitiesPath, 'utf8'));
const configuration = {
  runtimeVersion: '58.0.3',
  bridgeVersion: '1.0.0',
  expoUIVersion: '58.0.3',
  expoViews: exportedCallableNames(resolve(expoRoot, 'index.d.ts'), true),
  expoModifiers: exportedCallableNames(resolve(expoRoot, 'modifiers', 'index.d.ts'), false),
  expoReviewedViews: reviewedCapabilities.views,
  expoReviewedModifiers: reviewedCapabilities.modifiers,
  rules,
};

await mkdir(dirname(outputPath), { recursive: true });
await writeFile(outputPath, `${JSON.stringify(configuration, null, 2)}\n`);
console.log(`Wrote Expo UI inventory: ${configuration.expoViews.length} views, ${configuration.expoModifiers.length} modifiers`);
