import {promises as fs, createReadStream} from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';

/** npm permits command-only and metadata/subpath-only packages. Installation
 * validation must not invent a root library export or execute a CLI with made-up
 * arguments. A file receipt is explicitly distinct from an executed import.
 * importLibrary belongs to the original job source's module-resolution context.
 */
export async function validateGlobalPackage({name, packageRoot, importLibrary}) {
  const root=await fs.realpath(packageRoot);
  const manifest=JSON.parse(await fs.readFile(path.join(root,'package.json'),'utf8'));
  if(manifest.name!==name)throw new Error('The staged package identity changed before validation.');
  let library=false;
  if(Object.hasOwn(manifest,'exports')) library=hasRootExport(manifest.exports);
  else {
    library=typeof manifest.main==='string'&&manifest.main.length>0;
    if(!library)for(const file of ['index.js','index.json','index.node']) {
      try {if((await fs.stat(path.join(root,file))).isFile()){library=true;break;}}
      catch(error){if(!['ENOENT','ENOTDIR'].includes(error.code))throw error;}
    }
  }
  if(library) {
    if(typeof importLibrary!=='function')throw new TypeError('Library validation requires the original caller module context.');
    const loader=await importLibrary();
    return {name,version:manifest.version,validationMode:'library-load',executed:true,
      loader:['require','import'].includes(loader)?loader:'caller-loader'};
  }
  const declared=typeof manifest.bin==='string'?{[name.split('/').at(-1)]:manifest.bin}:manifest.bin??{};
  if(!declared||Array.isArray(declared)||typeof declared!=='object')throw new TypeError('Invalid npm command entry metadata.');
  const commands=[];
  for(const [command,relative] of Object.entries(declared)) {
    if(typeof relative!=='string'||!relative.length)throw new TypeError('An npm command entry must name a file.');
    const file=await fs.realpath(path.resolve(root,relative)),inside=path.relative(root,file);
    if(inside==='..'||inside.startsWith('..'+path.sep)||path.isAbsolute(inside))throw new Error('The npm command entry escapes its installed package.');
    const stat=await fs.stat(file);
    if(!stat.isFile())throw new Error('The npm command entry is not a regular file.');
    const hash=createHash('sha256');let bytes=0;
    for await(const chunk of createReadStream(file)){hash.update(chunk);bytes+=chunk.length;}
    commands.push({command,entryPoint:file,bytes,sha256:hash.digest('hex')});
  }
  const exportedSubpaths=manifest.exports&&typeof manifest.exports==='object'&&!Array.isArray(manifest.exports)
    ? Object.keys(manifest.exports).filter(key=>key.startsWith('./')):[];
  return {name,version:manifest.version,validationMode:commands.length?'command-entry-files':'package-metadata',
    executed:false,commands,exportedSubpaths,
    diagnostic:commands.length?'Command files verified; execute with actual caller arguments to verify runtime behavior.'
      :'No root library entry is declared. Metadata verification does not claim an executed import.'};
}

function hasRootExport(value) {
  if(typeof value==='string')return true;
  if(Array.isArray(value))return value.some(hasRootExport);
  if(!value||typeof value!=='object')return false;
  const entries=Object.entries(value);
  if(entries.some(([key])=>key.startsWith('.')))return hasRootExport(value['.']);
  return entries.some(([,target])=>hasRootExport(target));
}
