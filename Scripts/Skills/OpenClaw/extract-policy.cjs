const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=__dirname;
const ts=require('typescript');
const pin=JSON.parse(fs.readFileSync(path.join(root,'policy-pin.json'),'utf8'));
const ledger=JSON.parse(fs.readFileSync(path.join(root,pin.sourceLedger),'utf8'));
if(pin.revision!==ledger.revision||ts.version!==pin.buildTools.typescript)throw Error('Policy tool/source version mismatch');
pin.sources=ledger.sources;
const sourceRoot=path.join(root,'.cache',pin.revision);
for(const source of pin.sources){
 const bytes=fs.readFileSync(path.join(sourceRoot,source.path));
 const sha=crypto.createHash('sha256').update(bytes).digest('hex');
 const blob=crypto.createHash('sha1').update(Buffer.from('blob '+bytes.length+'\0')).update(bytes).digest('hex');
 if(sha!==source.sha256||blob!==source.gitBlob)throw Error('Original source mismatch: '+source.path);
}
const norm=p=>path.resolve(p).replaceAll('\\','/');
const sources=new Map(pin.sources.map(s=>[norm(path.join(sourceRoot,s.path)),s]));
const compilerHost=ts.createCompilerHost({});
compilerHost.resolveModuleNames=(names,containing)=>names.map(name=>{
 let base=name.startsWith('.')?path.resolve(path.dirname(containing),name):
 name.startsWith('@openclaw/normalization-core')?path.join(sourceRoot,'packages/normalization-core/src',name.split('/').slice(2).join('/')||'index'):null;
 if(!base)return undefined;
 for(const p of [base,base.replace(/\.js$/,'.ts'),base.replace(/\.mjs$/,'.mts'),base+'.ts',path.join(base,'index.ts')]){
  if(sources.has(norm(p)))return {resolvedFileName:norm(p),extension:p.endsWith('.mts')?ts.Extension.Mts:ts.Extension.Ts};
 }
 return undefined;
});
const program=ts.createProgram([...sources.keys()],{noLib:true,target:ts.ScriptTarget.ESNext,module:ts.ModuleKind.ESNext,skipLibCheck:true},compilerHost);
const checker=program.getTypeChecker();
const retained=new Set(),queue=[],external=new Map(),unresolved=new Set(),usedImports=new Set();
function top(node){while(node.parent&&!ts.isSourceFile(node.parent))node=node.parent;return node;}
function add(node){const s=top(node);if(!sources.has(norm(s.getSourceFile().fileName)))return;
 if(ts.isInterfaceDeclaration(s)||ts.isTypeAliasDeclaration(s)||ts.isImportDeclaration(s))return;
 if(!retained.has(s)){retained.add(s);queue.push(s);}}
for(const [file,names]of Object.entries(pin.entryExports)){
 const sf=program.getSourceFile(norm(path.join(sourceRoot,file)));
 const module=checker.getSymbolAtLocation(sf);
 for(const name of names){const symbol=checker.getExportsOfModule(module).find(s=>s.name===name);if(!symbol)throw Error('Missing original export '+name);for(const d of symbol.declarations||[])add(d);}
}
while(queue.length){const statement=queue.shift();
 function visit(node){
  if(ts.isTypeNode(node))return;
  if(ts.isIdentifier(node)){
   let symbol=checker.getSymbolAtLocation(node);
   if(symbol?.flags&ts.SymbolFlags.Alias){
    const declaration=symbol.declarations?.[0],importNode=declaration&&top(declaration);
    if(declaration)usedImports.add(declaration);
    const alias=checker.getAliasedSymbol(symbol);
    if(alias?.declarations?.length){symbol=alias;}
    else if(importNode&&ts.isImportDeclaration(importNode)){
     const name=importNode.moduleSpecifier.text;
     if(!external.has(name))external.set(name,new Set());external.get(name).add(symbol.name);
     return;
    }
   }
   if(symbol)for(const d of symbol.declarations||[])add(d);
   else if(!ts.isPropertyAccessExpression(node.parent)||node.parent.name!==node)unresolved.add(node.text);
  }
  ts.forEachChild(node,visit);
 }
 visit(statement);
}
const modules=new Map();
for(const s of retained){const sf=s.getSourceFile(),file=norm(sf.fileName);if(!modules.has(file))modules.set(file,[]);modules.get(file).push(s);}
// A source pin is necessary but not sufficient: reject executable omitted module
// initialization. Only inert declarations and unreferenced fresh data allocations
// may be omitted. No sideEffects:false override or original body replacement.
function inertValue(node){
 if(!node)return true;
 if(ts.isAsExpression(node)||ts.isTypeAssertionExpression(node)||ts.isParenthesizedExpression(node)||ts.isNonNullExpression(node))return inertValue(node.expression);
 if(ts.isStringLiteral(node)||ts.isNumericLiteral(node)||ts.isRegularExpressionLiteral(node)||
    [ts.SyntaxKind.TrueKeyword,ts.SyntaxKind.FalseKeyword,ts.SyntaxKind.NullKeyword].includes(node.kind))return true;
 if(ts.isIdentifier(node))return node.text==='undefined';
 if(ts.isArrayLiteralExpression(node))return node.elements.every(inertValue);
 if(ts.isObjectLiteralExpression(node))return node.properties.every(p=>ts.isPropertyAssignment(p)&&!ts.isComputedPropertyName(p.name)&&inertValue(p.initializer));
 if(ts.isNewExpression(node)&&ts.isIdentifier(node.expression)&&['Map','Set','WeakMap','WeakSet'].includes(node.expression.text))return (node.arguments||[]).every(inertValue);
 return false;
}
function inertOmitted(node){
 if(ts.isInterfaceDeclaration(node)||ts.isTypeAliasDeclaration(node)||ts.isFunctionDeclaration(node)||ts.isExportDeclaration(node))return true;
 if(ts.isVariableStatement(node))return node.declarationList.declarations.every(d=>inertValue(d.initializer));
 if(ts.isClassDeclaration(node)){
  if((node.heritageClauses||[]).some(c=>c.types.some(t=>t.expression.getText()!=='Error')))return false;
  return node.members.every(m=>!(ts.getModifiers(m)||[]).some(x=>x.kind===ts.SyntaxKind.StaticKeyword)&&!ts.isClassStaticBlockDeclaration(m)&&!(ts.getDecorators(m)||[]).length);
 }
 return false;
}
for(const [file,statements]of modules){
 const sf=statements[0].getSourceFile();
 for(const node of sf.statements){
  if(retained.has(node))continue;
  if(ts.isImportDeclaration(node)){
   if(!node.importClause)throw Error('Side-effect-only import needs explicit review: '+sources.get(file).path);
   continue;
  }
  if(!inertOmitted(node))throw Error('Omitted executable initialization: '+sources.get(file).path+':'+node.getStart(sf));
 }
}
for(const name of unresolved)if(!pin.permittedGlobalIdentifiers.includes(name))throw Error('Unresolved runtime identifier: '+name);
for(const name of external.keys())if(!pin.permittedRuntimeImports.includes(name)&&!Object.hasOwn(pin.bundledDependencies,name))throw Error('Unexpected external dependency: '+name);
fs.mkdirSync(path.join(root,'generated'),{recursive:true});
const output={status:'ORIGINAL_DECLARATIONS_EXTRACTED_NOT_PRODUCT_ACCEPTANCE',revision:pin.revision,typescript:ts.version,
 retainedDeclarations:retained.size,modules:[],externalImports:[...external].map(([name,symbols])=>({name,symbols:[...symbols].sort()})),unresolvedIdentifiers:[...unresolved].sort(),
 boundary:'Retained declaration bodies are original bytes; only imports are narrowed by TypeScript symbol reachability. Omitted initialization is checked structurally before emission. Native and parity evidence are separate.'};
for(const [file,statements]of modules){const sf=statements[0].getSourceFile();
 const unretainedInitializers=sf.statements.filter(s=>!retained.has(s)&&!ts.isImportDeclaration(s)&&!ts.isInterfaceDeclaration(s)&&!ts.isTypeAliasDeclaration(s)&&!ts.isFunctionDeclaration(s)&&!ts.isExportDeclaration(s));
 output.modules.push({path:sources.get(file).path,retained:statements.map(s=>({kind:ts.SyntaxKind[s.kind],start:s.getStart(sf),end:s.end,sha256:crypto.createHash('sha256').update(s.getText(sf)).digest('hex')})),
  unretainedInitializationStatements:unretainedInitializers.map(s=>({kind:ts.SyntaxKind[s.kind],start:s.getStart(sf),end:s.end,source:s.getText(sf).slice(0,500)}))});
}
fs.writeFileSync(path.join(root,'generated/policy-declaration-closure.json'),JSON.stringify(output,null,2)+'\n');
// Maintained deterministic emitter. Original retained declaration text is byte-identical;
// import lists are narrowed by the actual TypeScript symbol closure, never regexes.
const extracted=path.join(root,'.cache',pin.revision+'-policy-declarations');
const printer=ts.createPrinter();
for(const [file,statements]of modules){
 const sf=statements[0].getSourceFile(),parts=[];
 for(const s of sf.statements){
  if(ts.isImportDeclaration(s)){
   const clause=s.importClause;if(!clause||clause.isTypeOnly)continue;
   const defaultName=clause.name&&usedImports.has(clause)?clause.name:undefined;
   let bindings;
   if(clause.namedBindings&&ts.isNamespaceImport(clause.namedBindings)){
    if(usedImports.has(clause.namedBindings))bindings=clause.namedBindings;
   }else if(clause.namedBindings){
    const groups=new Map();
    for(const n of clause.namedBindings.elements.filter(n=>usedImports.has(n)&&!n.isTypeOnly)){
     const alias=checker.getSymbolAtLocation(n.name),target=alias&&(alias.flags&ts.SymbolFlags.Alias)?checker.getAliasedSymbol(alias):alias;
     const targetFile=target?.declarations?.[0]?.getSourceFile().fileName;
     let specifier=s.moduleSpecifier.text,imported=n;
     if(targetFile&&sources.has(norm(targetFile))){
      specifier=path.relative(path.dirname(file),targetFile).replaceAll('\\','/');if(!specifier.startsWith('.'))specifier='./'+specifier;
      imported=ts.factory.updateImportSpecifier(n,false,target.name===n.name.text?undefined:ts.factory.createIdentifier(target.name),n.name);
     }
     if(!groups.has(specifier))groups.set(specifier,[]);groups.get(specifier).push(imported);
    }
    for(const [specifier,names]of groups){
     const narrowed=ts.factory.updateImportClause(clause,false,undefined,ts.factory.updateNamedImports(clause.namedBindings,names));
     parts.push(printer.printNode(ts.EmitHint.Unspecified,ts.factory.updateImportDeclaration(s,s.modifiers,narrowed,ts.factory.createStringLiteral(specifier),s.attributes),sf));
    }
   }
   if(defaultName||bindings){const narrowed=ts.factory.updateImportClause(clause,false,defaultName,bindings);
    parts.push(printer.printNode(ts.EmitHint.Unspecified,ts.factory.updateImportDeclaration(s,s.modifiers,narrowed,s.moduleSpecifier,s.attributes),sf));}
  }else if(retained.has(s)){parts.push(s.getText(sf));}
 }
 const dest=path.join(extracted,sources.get(file).path);fs.mkdirSync(path.dirname(dest),{recursive:true});fs.writeFileSync(dest,parts.join('\n')+'\n');
}
output.initializationAudit=[...sources.keys()].map(file=>program.getSourceFile(file)).filter(Boolean).flatMap(sf=>sf.statements.filter(s=>
 ts.isExpressionStatement(s)||ts.isIfStatement(s)||ts.isTryStatement(s)||ts.isThrowStatement(s)||ts.isForStatement(s)).map(s=>({
 path:sources.get(norm(sf.fileName)).path,kind:ts.SyntaxKind[s.kind],start:s.getStart(sf),source:s.getText(sf).slice(0,1000)})));
output.initializerCalls=[];
for(const file of sources.keys()){
 const sf=program.getSourceFile(file);if(!sf)continue;
 for(const statement of sf.statements){
  if(!ts.isVariableStatement(statement))continue;
  for(const d of statement.declarationList.declarations){
   if(!d.initializer)continue;
   function calls(n){
    if(ts.isFunctionLike(n))return;
    if(ts.isCallExpression(n)||ts.isNewExpression(n))output.initializerCalls.push({path:sources.get(file).path,
     retained:retained.has(statement),binding:d.name.getText(sf),expression:n.getText(sf).slice(0,500)});
    ts.forEachChild(n,calls);
   }
   calls(d.initializer);
  }
 }
}
fs.writeFileSync(path.join(root,'generated/policy-declaration-closure.json'),JSON.stringify(output,null,2)+'\n');
console.log(JSON.stringify({status:output.status,declarations:retained.size,modules:modules.size,externalImports:output.externalImports,unresolvedCount:unresolved.size},null,2));
