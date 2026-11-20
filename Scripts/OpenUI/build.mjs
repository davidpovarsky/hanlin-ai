import { build } from 'esbuild';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const dir = dirname(fileURLToPath(import.meta.url));
const out = resolve(dir, '../../Packages/HanlinPresentationSDK/Sources/HanlinRichUI/Resources/OpenUI');
await mkdir(out, { recursive: true });
await build({ entryPoints: [resolve(dir, 'bridge.jsx')], bundle: true, minify: true,
  outfile: resolve(out, 'bridge.js'), format: 'iife', platform: 'browser', target: 'safari17',
  jsx: 'automatic', tsconfigRaw: '{}',
  define: { 'process.env.NODE_ENV': '"production"' }, legalComments: 'linked',
  loader: { '.woff2': 'file', '.woff': 'file', '.ttf': 'file', '.svg': 'dataurl' } });
await writeFile(resolve(out, 'index.html'), `<!doctype html><html dir="auto"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; font-src 'self' data:; img-src https: data: blob:; media-src https: blob:; connect-src 'none'"><link rel="stylesheet" href="bridge.css"></head><body><div id="root"></div><script src="bridge.js"></script></body></html>`);
const { outputFiles } = await build({ entryPoints: [resolve(dir, 'catalogs.jsx')], bundle: true,
  write: false, platform: 'node', format: 'esm', packages: 'external', jsx: 'automatic' });
await writeFile(resolve(dir, '.catalogs.generated.mjs'), outputFiles[0].contents);
const { openuiLibrary, torahLibrary, nativeComponentNames } = await import('./.catalogs.generated.mjs');
const options = { inlineMode: true, bindings: true, builtinFunctions: true };
const routing = `Use ordinary Markdown for prose and fenced openui-lang for rich UI. Add renderTarget=react or renderTarget=swiftui on each fence header. You choose each block's renderer. A whole response may be one OpenUI block. Every block in this message shares the same $variables and form state, even across renderers. React includes the complete original catalog. SwiftUI supports: ${nativeComponentNames.join(', ')}. Select React for other original components. Do not output JavaScript or JSX. Use only real tools supplied by the host. Query/Mutation and @ToAssistant use the existing host permissions.`;
await writeFile(resolve(out, 'original-prompt.txt'), openuiLibrary.prompt({ ...options, preamble: routing }));
await writeFile(resolve(out, 'torah-prompt.txt'), torahLibrary.prompt({ ...options, preamble: routing + '\nTorah native additions: Title, Paragraph, SourceQuote, Comparison, Conclusion, Sources, FollowUps. Cite only real references supplied in context.' }));
await writeFile(resolve(out, 'catalog-manifest.json'), JSON.stringify({
  original: { id: 'openui.original', version: 1, components: Object.keys(openuiLibrary.components) },
  native: nativeComponentNames,
  torah: { id: 'hanlin.torah', version: 1, components: Object.keys(torahLibrary.components) },
  packages: JSON.parse(await readFile(resolve(dir, 'package.json'), 'utf8')).dependencies,
}, null, 2));
let notices = '# Upstream notices\n\nThe original OpenUI runtime and React component library are bundled without changing their implementation.\n\n';
for (const pkg of ['@openuidev/lang-core', '@openuidev/react-lang', '@openuidev/react-ui', 'react', 'react-dom']) {
  const root = resolve(dir, 'node_modules', pkg);
  const info = JSON.parse(await readFile(resolve(root, 'package.json'), 'utf8'));
  let license;
  for (const name of ['LICENSE', 'LICENSE.md', 'LICENSE.txt']) {
    try { license = await readFile(resolve(root, name), 'utf8'); break; } catch { /* Try upstream's other filename. */ }
  }
  if (!license) throw new Error(`Missing distribution license: ${pkg}`);
  notices += `## ${pkg} ${info.version}\n\n${license}\n\n`;
}
await writeFile(resolve(out, 'THIRD_PARTY_NOTICES.md'), notices.trimEnd() + '\n');
console.log(`Built original OpenUI assets and versioned catalogs in ${out}`);
