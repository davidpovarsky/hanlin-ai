import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
const [producer,input]=process.argv.slice(2);
const {generatedHostVersions}=await import(pathToFileURL(resolve(producer)).href);
process.stdout.write(generatedHostVersions(JSON.parse(await readFile(input,'utf8'))));
