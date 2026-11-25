#!/usr/bin/env node
/** Resolve additive Hanlin exports against the exact original Expo UI API. */
import {readFile,writeFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

export async function syncOriginalUIExports({root=path.resolve(import.meta.dirname,'../..'),check=false}={}) {
  const toolingRoot=path.join(root,'Scripts/Expo');
  const require=createRequire(path.join(toolingRoot,'package.json'));
  const ts=require('typescript');
  const options={target:ts.ScriptTarget.ESNext,module:ts.ModuleKind.ESNext,moduleResolution:ts.ModuleResolutionKind.Bundler};
  const moduleName='@expo/ui/swift-ui/modifiers';
  const resolved=ts.resolveModuleName(moduleName,path.join(toolingRoot,'__hanlin_type_exports__.ts'),options,ts.sys).resolvedModule;
  if(!resolved)throw new Error('Original Expo UI modifier exports could not be resolved from the host package graph.');
  const generated=path.join(root,'Packages/HanlinExpoUI/src/generated/modifiers.ts');
  const program=ts.createProgram([resolved.resolvedFileName,generated],options);
  const checker=program.getTypeChecker();
  const exports=file=>{
    const source=program.getSourceFile(file);
    const symbol=source&&checker.getSymbolAtLocation(source);
    if(!symbol)throw new Error('Cannot inspect real modifier module: '+file);
    return new Map(checker.getExportsOfModule(symbol).map(value=>[value.getName(),value]));
  };
  const original=exports(resolved.resolvedFileName),additional=exports(generated);
  const overlap=[...additional.keys()].filter(name=>name!=='default'&&original.has(name)).sort();
  const values=[],types=[];
  for(const name of overlap) {
    if(!/^[$A-Z_a-z][$\w]*$/.test(name))throw new Error('Unsupported original export identifier: '+name);
    let symbol=original.get(name);
    if(symbol.flags&ts.SymbolFlags.Alias)symbol=checker.getAliasedSymbol(symbol);
    (symbol.flags&ts.SymbolFlags.Value?values:types).push(name);
  }
  const begin='// BEGIN ORIGINAL EXPO MODIFIER PRECEDENCE';
  const end='// END ORIGINAL EXPO MODIFIER PRECEDENCE';
  const lines=[begin,
    '// Generated from the installed original package. New upstream APIs take precedence',
    '// over same-named Hanlin additions; unrelated additions remain available.',
    ...(values.length?[`export { ${values.join(', ')} } from '${moduleName}';`]:[]),
    ...(types.length?[`export type { ${types.join(', ')} } from '${moduleName}';`]:[]),
    end];
  const file=path.join(root,'Packages/HanlinExpoUI/src/modifiers.ts');
  const previous=await readFile(file,'utf8');
  const start=previous.indexOf(begin),finish=previous.indexOf(end);
  if((start<0)!==(finish<0)||start>finish)throw new Error('Incomplete original export precedence markers.');
  const content=start>=0?previous.slice(0,start)+lines.join('\n')+previous.slice(finish+end.length):
    previous.trimEnd()+'\n\n'+lines.join('\n')+'\n';
  if(check&&content!==previous)throw new Error('Original Expo UI modifier exports need synchronization.');
  if(content!==previous)await writeFile(file,content);
  return {module:moduleName,originalExports:original.size,additionalExports:additional.size,originalPrecedence:overlap};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href)
  syncOriginalUIExports({check:process.argv.includes('--check')}).then(result=>console.log(JSON.stringify(result)))
    .catch(error=>{console.error(error.stack);process.exitCode=1;});
