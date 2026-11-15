import {promises as fs} from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';

const hash=value=>createHash('sha256').update(value).digest('hex');
const option=name=>process.argv.includes(name)?process.argv[process.argv.indexOf(name)+1]:undefined;
const root=path.resolve(option('--root')??fileURLToPath(new URL('../../AI_HLY/Downstream/RuntimeCore/Node/Host',import.meta.url)));
const compilerRoot=path.resolve(option('--compiler-root')??fileURLToPath(new URL('HostGrammarTools',import.meta.url)));
const require=createRequire(path.join(compilerRoot,'package.json'));
const peg=require('pegjs');
if(peg.VERSION!=='0.10.0')throw new Error('Use the original pinned PEG.js 0.10.0 grammar compiler.');
const manifestPath=path.join(root,'host-dependency-patches.json');
const manifest=JSON.parse(await fs.readFile(manifestPath,'utf8'));
const grammarPath='node_modules/@yarnpkg/parsers/lib/grammars/shell.pegjs';
const parserPath='node_modules/@yarnpkg/parsers/lib/grammars/shell.js';
const originalGrammarSHA='015b8ec6f42ed0bb096f6151defd3aadc396f9f0c1b81a032bd9cb956efe62bd';
const originalParserSHA='1b19831e36ee819515f96d53a527862bb98caf7010bdd8475c772b9c7563f8c0';
const changes=[
  ['= S* line:ShellLine? { return line ? line : [] }','= WS* line:ShellLine? WS* { return line ? line : [] }'],
  ['= S* then:ShellLine S* { return then }','= WS* then:ShellLine WS* { return then }'],
  ["ShellLineType\n  = ';'\n  / '&'","ShellLineType\n  = ';'\n  / '&'\n  / Newline+ { return ';' }"],
  ['type:CommandLineType S* then:CommandLine','type:CommandLineType WS* then:CommandLine'],
  ['type:CommandChainType S* then:CommandChain','type:CommandChainType WS* then:CommandChain'],
  ['"(" S* subshell:ShellLine S* ")"','"(" WS* subshell:ShellLine WS* ")"'],
  ['"{" S* group:ShellLine S* "}"','"{" WS* group:ShellLine WS* "}"'],
  ["= '$(' command:ShellLine ')'", "= '$(' WS* command:ShellLine WS* ')'"],
  ["= '\\\\\\n' { return `` }","= '\\\\' Newline { return `` }"],
  ["= chars:('\\\\' c:. { return c } / '{}'", "= chars:('\\\\' Newline { return `` } / '\\\\' c:. { return c } / '{}'"],
  ['= [()}<>$|&; \\t"\']','= [()}<>$|&; \\t\\r\\n"\']'],
  ['= [<>&; \\t"\']','= [<>&; \\t\\r\\n"\']'],
  ['S = [ \\t]+',"Newline = '\\r\\n' / '\\n'\nComment = '#' [^\\r\\n]*\nWS = (S / Newline)+\nS = ([ \\t] / '\\\\' Newline / Comment)+"],
];
let original=await fs.readFile(path.join(root,grammarPath),'utf8');
if(hash(original)!==originalGrammarSHA){
  for(const {before,after} of [...(manifest.files.find(item=>item.path===grammarPath)?.replacements??[])].reverse())original=original.replace(after,()=>before);
}
if(hash(original)!==originalGrammarSHA)throw new Error('Unknown published Yarn grammar bytes.');
if(hash(peg.generate(original,{output:'source',format:'commonjs'}))!==originalParserSHA)throw new Error('Compiler does not reproduce the exact published parser.');
let grammar=original;
for(const [before,after] of changes){
  if(grammar.split(before).length!==2)throw new Error('Ambiguous grammar anchor: '+before);
  grammar=grammar.replace(before,()=>after);
}
const parser=peg.generate(grammar,{output:'source',format:'commonjs'});
const parent=manifest.files.find(item=>item.package==='@yarnpkg/parsers');
const identity=Object.fromEntries(['package','version','license','upstreamTarball','upstreamIntegrity'].map(key=>[key,parent[key]]));
const entries=[
  {...identity,path:grammarPath,upstreamSHA256:originalGrammarSHA,patchedSHA256:hash(grammar),replacements:changes.map(([before,after])=>({before,after}))},
  {...identity,path:parserPath,upstreamSHA256:originalParserSHA,patchedSHA256:hash(parser),generator:{type:'pegjs',version:'0.10.0',grammar:grammarPath,grammarSHA256:hash(grammar),compilerIntegrity:'sha512-qI5+oFNEGi3L5HAxDwN2LA4Gg7irF70Zs25edhjld9QemOgp0CbvMtbFcMvFtEo1OityPrcCzkQFB8JP/hxgow=='}}
];
if(process.argv.includes('--write')){
  manifest.files=manifest.files.filter(item=>![grammarPath,parserPath].includes(item.path)).concat(entries);
  manifest.licenses??=[];
  if(!manifest.licenses.some(item=>item.path==='PEGJS-LICENSE.txt'))manifest.licenses.push({path:'PEGJS-LICENSE.txt',sha256:'e56890ff38a31e1adc0617f57c23056289dd27a9ff6263eaf6137dacd1253d9d',license:'MIT',source:'https://registry.npmjs.org/pegjs/-/pegjs-0.10.0.tgz'});
  await fs.writeFile(manifestPath,JSON.stringify(manifest,null,2)+'\n');
}else{
  for(const entry of entries)if(JSON.stringify(manifest.files.find(item=>item.path===entry.path))!==JSON.stringify(entry))throw new Error('Regenerate the authenticated multiline grammar patch.');
}
console.log(JSON.stringify({compiler:peg.VERSION,originalParserReproduced:true,grammarSHA256:hash(grammar),parserSHA256:hash(parser)}));
