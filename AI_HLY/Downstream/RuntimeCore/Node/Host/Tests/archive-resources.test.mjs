import test from 'node:test';
import assert from 'node:assert/strict';
import {promises as fs} from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {inspectArchiveSafety} from '../package-compatibility.mjs';

test('real archive inventory exceeds former file/size caps with bounded I/O and preserves caller budgets', async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(),'hanlin-archive-resources-'));
  t.after(() => fs.rm(root,{recursive:true,force:true}));
  const count = 25_010;
  for (let start=0; start<count; start+=64) {
    await Promise.all(Array.from({length:Math.min(64,count-start)},(_,offset) => fs.writeFile(path.join(root,`file-${start+offset}.txt`),'')));
  }
  const large = await fs.open(path.join(root,'large-data.bin'),'w');
  try {await large.truncate(256*1024*1024+1);} finally {await large.close();}
  const inventory = await inspectArchiveSafety(root);
  assert.equal(inventory.treeFileCount,count+1);
  assert.deepEqual(inventory.findings,[]);
  const bounded = await inspectArchiveSafety(root,{maximumFiles:10});
  assert.ok(bounded.findings.some(finding => finding.code==='archive_file_limit'));
  const sizeBounded = await inspectArchiveSafety(root,{maximumFileBytes:256*1024*1024});
  assert.ok(sizeBounded.findings.some(finding => finding.code==='archive_file_too_large' && finding.path==='large-data.bin'));
  await assert.rejects(inspectArchiveSafety(root,{maximumFiles:-1}),RangeError);
  const controller = new AbortController(); controller.abort(new Error('User cancelled archive inventory'));
  await assert.rejects(inspectArchiveSafety(root,{signal:controller.signal}),/User cancelled/);
  assert.equal((await fs.stat(path.join(root,'large-data.bin'))).size,256*1024*1024+1);
});
