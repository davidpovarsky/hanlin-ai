#!/usr/bin/env node
import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {scriptWidgetAPI} from './scriptwidget/upstream/scriptWidgetAPI.js';
const root=path.dirname(fileURLToPath(import.meta.url));
const upstream=path.join(root,'scriptwidget/upstream');
const provenance=JSON.parse(await readFile(path.join(upstream,'provenance.json'),'utf8'));
for(const source of provenance.files) {
 const actual=createHash('sha256').update(await readFile(path.join(upstream,source.local))).digest('hex');
 if(actual!==source.sha256)throw new Error('Original ScriptWidget catalog changed: '+source.local);
}
function propertyType(property) {
 if(property.values)return property.values.map(x=>JSON.stringify(x)).join(' | ');
 switch(property.type) {
 case 'number': return 'number | string';
 case 'number|string': return 'number | string';
 case 'boolean': return 'boolean';
 case 'function': return 'string';
 case 'date|number': return 'number | Date';
 case 'string': case 'url': case 'color': case 'json': case 'action-id': case 'storage-key':return 'string';
 default:throw new Error('Unmapped original ScriptWidget property type: '+property.type);
 }
}
function props(properties) {
 return Object.entries(properties).map(([name,value])=>'    '+JSON.stringify(name)+(value.required?'': '?')+': '+propertyType(value)+';').join('\n');
}
const lines=[
'// Generated from original ScriptWidget editor catalog; do not edit.',
'// Hanlin host additions are declared separately in host-globals.d.ts.',
'declare namespace JSX {',
'  interface Element { readonly __scriptWidgetElement: unique symbol; }',
'  type Child = Element | string | number | boolean | null | undefined | readonly Child[];',
'  interface ElementChildrenAttribute { children: {}; }',
'  interface GlobalProperties {',props(scriptWidgetAPI.globalProperties),'    children?: Child;','  }',
'  interface IntrinsicElements {'
];
for(const [name,component] of Object.entries(scriptWidgetAPI.components)) {
 lines.push('    '+JSON.stringify(name.toLowerCase())+': GlobalProperties & {',props(component.properties??{}),'    };');
}
lines.push('  }','}','');
const output=path.join(root,'scriptwidget/components.d.ts'),text=lines.join('\n');
if(process.argv.includes('--check')) {
 if(await readFile(output,'utf8')!==text)throw new Error('ScriptWidget declarations are stale');
} else await writeFile(output,text);
console.log('ScriptWidget catalog: '+Object.keys(scriptWidgetAPI.components).length+' component declarations generated from original source.');
