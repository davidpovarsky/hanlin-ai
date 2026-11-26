import fs from 'node:fs';import path from 'node:path';import {pathToFileURL} from 'node:url';
const workspace=process.argv[1];const modulePath=process.argv[2];const started=performance.now();
const ts=await import(pathToFileURL(modulePath).href);const configPath=path.join(workspace,'tsconfig.json');
const c=ts.readConfigFile(configPath,ts.sys.readFile);const parsed=ts.parseJsonConfigFileContent(c.config,ts.sys,workspace,{},configPath);
const program=ts.createProgram({rootNames:parsed.fileNames,options:parsed.options,projectReferences:parsed.projectReferences});
const diagnostics=[...parsed.errors,...ts.getPreEmitDiagnostics(program)];const files=[];
if(!diagnostics.some(d=>d.category===ts.DiagnosticCategory.Error)){const emitted=program.emit(undefined,(f,data,bom)=>{fs.mkdirSync(path.dirname(f),{recursive:true});ts.sys.writeFile(f,data,bom);files.push(path.relative(workspace,f));});diagnostics.push(...emitted.diagnostics);}
console.log(JSON.stringify({node:process.version,compilerVersion:ts.version,defaultCompilerVersion:ts.default?.version,elapsedSeconds:(performance.now()-started)/1000,files,diagnostics:diagnostics.map(d=>({code:d.code,category:d.category,message:ts.flattenDiagnosticMessageText(d.messageText,' '),file:d.file?path.relative(workspace,d.file.fileName):null})),succeeded:!diagnostics.some(d=>d.category===ts.DiagnosticCategory.Error)}));