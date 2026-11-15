import {promises as fs,constants} from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {isUtf8} from 'node:buffer';

// Node's fatal TextDecoder requires ICU, which the embedded build deliberately
// omits. Buffer's SIMD UTF-8 validator is independent of ICU. Keep incomplete
// scalars between reads; invalid encodings still fail rather than being repaired.
class StrictUTF8InputDecoder {
  #pending=Buffer.alloc(0);
  #first=true;
  decode(chunk=Buffer.alloc(0),final=false) {
    const bytes=this.#pending.length?Buffer.concat([this.#pending,chunk]):chunk;
    let end=bytes.length;
    if(!final&&end) {
      let start=end-1;
      while(start>Math.max(0,end-4)&&(bytes[start]&0xc0)===0x80)start--;
      const lead=bytes[start],length=lead<0x80?1:lead>=0xc2&&lead<=0xdf?2:lead>=0xe0&&lead<=0xef?3:lead>=0xf0&&lead<=0xf4?4:0;
      if(length&&end-start<length)end=start;
    }
    const complete=bytes.subarray(0,end);
    if(!isUtf8(complete))throw new TypeError('Execution input is not valid UTF-8.');
    this.#pending=Buffer.from(bytes.subarray(end));
    let text=complete.toString('utf8');
    if(this.#first&&text.length) {
      this.#first=false;
      if(text.charCodeAt(0)===0xfeff)text=text.slice(1);
    }
    return text;
  }
}

/** Claim a UUID-named input into its already reserved job. The authenticated
 * HTTP control envelope carries only size/hash, never an arbitrary file path.
 * No payload ceiling: JSON/engine memory and actual filesystem errors apply.
 */
export function validateExecutionInputReceipt(artifact) {
  if(!artifact||!Number.isSafeInteger(artifact.bytes)||artifact.bytes<1
      ||typeof artifact.sha256!=='string'||!/^[a-f0-9]{64}$/.test(artifact.sha256))
    throw new Error('Invalid execution input receipt.');
  return {bytes:artifact.bytes,sha256:artifact.sha256};
}

export async function claimExecutionInput({inbox,directory,id,artifact,cancelled=()=>false}) {
  if(!inbox)throw new Error('File-backed execution input is not configured.');
  validateExecutionInputReceipt(artifact);
  const inboxRoot=await fs.realpath(inbox),jobRoot=await fs.realpath(directory);
  const incoming=path.join(inboxRoot,id+'.json'),claimed=path.join(jobRoot,'request.json');
  const source=await fs.lstat(incoming);
  if(!source.isFile()||source.isSymbolicLink())throw new Error('Execution input must be a regular owned file.');
  await fs.rename(incoming,claimed);
  const file=await fs.open(claimed,constants.O_RDONLY|(constants.O_NOFOLLOW??0));
  const hash=createHash('sha256'),decoder=new StrictUTF8InputDecoder(),parts=[];
  let bytes=0;
  try {
    const stat=await file.stat(),entry=await fs.lstat(claimed);
    if(!stat.isFile()||stat.size!==artifact.bytes||entry.isSymbolicLink()||stat.dev!==entry.dev||stat.ino!==entry.ino
        ||await fs.realpath(claimed)!==claimed)throw new Error('Execution input ownership changed.');
    const chunk=Buffer.alloc(65_536);
    while(true) {
      if(cancelled())throw new Error('Execution input preparation was cancelled; its claimed bytes are retained.');
      const read=await file.read(chunk,0,chunk.length,null);
      if(!read.bytesRead)break;
      const current=chunk.subarray(0,read.bytesRead);bytes+=current.length;hash.update(current);
      if(bytes>artifact.bytes)throw new Error('Execution input grew beyond its authenticated receipt.');
      parts.push(decoder.decode(current));
    }
    parts.push(decoder.decode(undefined,true));
    if(bytes!==artifact.bytes||hash.digest('hex')!==artifact.sha256)throw new Error('Execution input integrity mismatch.');
    const body=JSON.parse(parts.join(''));
    if(!body||typeof body!=='object'||Array.isArray(body)||String(body.executionID).toLowerCase()!==id
        ||Object.hasOwn(body,'inputArtifact'))throw new Error('Execution input identity or shape is invalid.');
    return {body,receipt:{fileName:'request.json',bytes,sha256:artifact.sha256,verified:true}};
  } finally {await file.close();}
}
