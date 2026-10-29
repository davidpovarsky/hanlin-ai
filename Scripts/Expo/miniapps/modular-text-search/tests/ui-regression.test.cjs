const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root=path.resolve(__dirname,'..');
const app=fs.readFileSync(path.join(root,'App.tsx'),'utf8');
const pkg=JSON.parse(fs.readFileSync(path.join(root,'script.json'),'utf8'));
assert(!app.includes('<Searchable'), 'Legacy native Searchable wrapper should not hide dynamic List');
assert(app.includes('<EditableField value={query} onChange={setQuery}'), 'Must show a real editable query field');
assert(app.includes('onPress={()=>{setQuery(q);search({query:q});}}'), 'Quick queries must submit instead of only populating the field');
assert(app.includes('...effective(q,0),...(override||{}),query:q,start:0'), 'Submission must retain advanced search settings');
assert(app.includes('setSearchPhase(\'failed\')'), 'Search failures must have explicit status');
assert(app.includes('{error}'), 'Errors must be displayed in the search area');
assert(app.includes('checkConnection()'), 'Permission/Node diagnostics must be user-accessible');
assert(pkg.version === '1.0.2');
assert(pkg.capabilities.includes('runtime.node') && pkg.capabilities.includes('network'));
console.log('PASS: visible query field, quick-search, retained options, visible failures and diagnostics');
