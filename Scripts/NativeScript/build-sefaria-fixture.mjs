import { resolve } from 'node:path';
import { execSync } from 'node:child_process';
import { rm } from 'node:fs/promises';

const scriptRoot = resolve(import.meta.dirname);
const fixtureDir = resolve(scriptRoot, 'Fixtures', 'sefaria-reader-core-source');
const targetZip = resolve(scriptRoot, 'Fixtures', 'sefaria-reader-core.hanlinNativeScript');

await rm(targetZip, { force: true });
const pyCmd = `python3 -c "import zipfile, os, sys; zf = zipfile.ZipFile(sys.argv[1], 'w', zipfile.ZIP_DEFLATED); [zf.write(os.path.join(r, f), os.path.relpath(os.path.join(r, f), sys.argv[2]).replace('\\\\\\\\', '/')) for r, d, files in os.walk(sys.argv[2]) for f in files]; zf.close()" "${targetZip}" "${fixtureDir}"`;
try {
  execSync(pyCmd);
} catch {
  execSync(pyCmd.replace('python3', 'python'));
}
console.log(`Created Sefaria Core fixture at ${targetZip}`);
