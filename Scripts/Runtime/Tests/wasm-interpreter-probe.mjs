import {randomInt} from 'node:crypto';
import {Worker} from 'node:worker_threads';

// A fixed standards-valid module: imported i32 callback, exported run/grow/trap
// functions and bounded exported linear memory. Reference-engine validation is
// separate from the actual JITless iOS execution required by the native smoke.
const bytes=Uint8Array.from([
  0,97,115,109,1,0,0,0,
  1,9,2,96,1,127,1,127,96,0,0,
  2,14,1,3,101,110,118,6,100,111,117,98,108,101,0,0,
  3,4,3,0,0,1,
  5,4,1,1,1,3,
  7,30,4,3,114,117,110,0,1,4,103,114,111,119,0,2,4,116,114,97,112,0,3,6,109,101,109,111,114,121,2,0,
  10,19,3,6,0,32,0,16,0,11,6,0,32,0,64,0,11,3,0,0,11,
]);

const referenceBytes=Uint8Array.from([
  0,97,115,109,1,0,0,0,
  1,6,1,96,1,111,1,111,
  2,16,1,3,101,110,118,8,105,100,101,110,116,105,116,121,0,0,
  3,2,1,0,
  7,13,1,9,114,111,117,110,100,116,114,105,112,0,1,
  10,8,1,6,0,32,0,16,0,11,
]);

// Exercise the exact reference-array fill instruction that requires compressed
// tagged pointers, including the real out-of-bounds trap. All sections fit in a
// one-byte unsigned LEB length; validate the bytes with the reference engine too.
const section=(id,payload)=>[id,payload.length,...payload];
const arrayBody=offset=>[
  1,1,0x63,0, // one local: nullable reference to array type 0
  0x41,2,0xfb,7,0,0x22,1, // allocate two cells, local.tee 1
  0x41,offset,0x20,0,0x41,2,0xfb,0x10,0, // array.fill with the externref argument
  0x20,1,0x41,1,0xfb,0x0b,0,0x0b, // array.get 1 and return
];
const fillBody=arrayBody(0),trapBody=arrayBody(1);
const arrayBytes=Uint8Array.from([
  0,97,115,109,1,0,0,0,
  ...section(1,[2,0x5e,0x6f,1,0x60,1,0x6f,1,0x6f]),
  ...section(3,[2,1,1]),
  ...section(7,[2,4,102,105,108,108,0,0,4,116,114,97,112,0,1]),
  ...section(10,[2,fillBody.length,...fillBody,trapBody.length,...trapBody]),
]);

export async function probeWasmInterpreter({requireJitless=false,requireGC=requireJitless}={}) {
  const noJIT=process.execArgv.includes('--jitless')&&process.execArgv.includes('--wasm-jitless');
  const pointerCompression=Number(process.config.variables.v8_enable_pointer_compression)===1;
  if(requireJitless&&!noJIT)throw new Error('The native interpreter fixture requires explicit --jitless --wasm-jitless flags.');
  if(requireJitless&&!pointerCompression)throw new Error('The pinned DrumBrake interpreter requires the actual compressed-pointer build, not a removed assertion.');
  if(typeof WebAssembly==='undefined')throw new Error('The embedded non-JIT WebAssembly interpreter is unavailable.');
  if(requireGC&&typeof globalThis.gc!=='function')throw new Error('The native GC ownership fixture requires explicit --expose-gc.');
  const nonce=randomInt(1000,1_000_000);let callbacks=0;
  const sharedModule=await WebAssembly.compile(bytes);
  const ownedInstances=Array.from({length:4},(_,index)=>new WebAssembly.Instance(sharedModule,{env:{double:value=>{
    if(typeof globalThis.gc==='function')globalThis.gc();return value*2+index;
  }}}));
  const multipleInstances=ownedInstances.every((owned,index)=>owned.exports.run(nonce)===nonce*2+index);
  const nestedInstance=new WebAssembly.Instance(sharedModule,{env:{double:ownedInstances[3].exports.run}});
  const nestedInstances=nestedInstance.exports.run(nonce)===nonce*2+3;
  const {instance}=await WebAssembly.instantiate(bytes,{env:{double:value=>{callbacks++;return value*2;}}});
  const imported=instance.exports.run(nonce)===nonce*2&&callbacks===1;
  const message=new TextEncoder().encode('שלום WASM '+nonce);
  new Uint8Array(instance.exports.memory.buffer).set(message,41);
  const old=instance.exports.memory.buffer;
  const pages=instance.exports.grow(1);
  const memory=pages===1&&old.byteLength===0&&instance.exports.memory.buffer.byteLength===131072
    &&new TextDecoder().decode(new Uint8Array(instance.exports.memory.buffer,41,message.length))==='שלום WASM '+nonce
    &&instance.exports.grow(2)===-1;
  let trapped=false;
  try{instance.exports.trap();}catch(error){trapped=error instanceof WebAssembly.RuntimeError;}
  let invalidModule=false;
  try{await WebAssembly.compile(Uint8Array.of(0,1,2));}catch(error){invalidModule=error instanceof WebAssembly.CompileError;}
  let gcCycles=0,externref=true;
  const array=await WebAssembly.instantiate(arrayBytes);
  let refArrayFill=true,refArrayBounds=false;
  const references=await WebAssembly.instantiate(referenceBytes,{env:{identity:value=>{
    if(typeof globalThis.gc==='function'){globalThis.gc();gcCycles++;}
    return value;
  }}});
  for(let cycle=0;cycle<8;cycle++){
    const value={nonce,cycle,text:'שלום GC'};
    if(references.instance.exports.roundtrip(value)!==value)externref=false;
    if(array.instance.exports.fill(value)!==value)refArrayFill=false;
  }
  try{array.instance.exports.trap({nonce});}catch(error){refArrayBounds=error instanceof WebAssembly.RuntimeError;}
  const worker=new Worker(`
    (async()=>{
      const {parentPort,workerData}=await import('node:worker_threads');
      const sharedModule=await WebAssembly.compile(Uint8Array.from(workerData.bytes));
      const ownedInstances=Array.from({length:4},(_,index)=>new WebAssembly.Instance(sharedModule,{env:{double:value=>{
        if(typeof globalThis.gc==='function')globalThis.gc();return value*2+index;
      }}}));
      const multipleInstances=ownedInstances.every((owned,index)=>owned.exports.run(workerData.nonce)===workerData.nonce*2+index);
      const nestedInstance=new WebAssembly.Instance(sharedModule,{env:{double:ownedInstances[3].exports.run}});
      const nestedInstances=nestedInstance.exports.run(workerData.nonce)===workerData.nonce*2+3;
      if(!multipleInstances||!nestedInstances)throw Error('Worker per-instance or nested Wasm ownership mismatch');
      let gcCycles=0;
      const array=await WebAssembly.instantiate(Uint8Array.from(workerData.arrayBytes));
      const references=await WebAssembly.instantiate(Uint8Array.from(workerData.referenceBytes),{env:{identity:value=>{
        if(typeof globalThis.gc==='function'){globalThis.gc();gcCycles++;}return value;
      }}});
      for(let cycle=0;cycle<8;cycle++){
        const {instance}=await WebAssembly.instantiate(Uint8Array.from(workerData.bytes),{env:{double:value=>value*2}});
        if(instance.exports.run(workerData.nonce+cycle)!==(workerData.nonce+cycle)*2)throw Error('Worker Wasm import mismatch');
        const value={nonce:workerData.nonce,cycle};
        if(references.instance.exports.roundtrip(value)!==value)throw Error('Worker reference ownership mismatch');
        if(array.instance.exports.fill(value)!==value)throw Error('Worker reference-array fill mismatch');
      }
      let refArrayBounds=false;
      try{array.instance.exports.trap({});}catch(error){refArrayBounds=error instanceof WebAssembly.RuntimeError;}
      if(!refArrayBounds)throw Error('Worker reference-array fill did not trap out of bounds');
      parentPort.postMessage({nonce:workerData.nonce,gcCycles,refArrayFill:true,refArrayBounds,multipleInstances,nestedInstances});
    })().catch(error=>{console.error(error);process.exitCode=1;});
  `,{eval:true,workerData:{bytes:[...bytes],referenceBytes:[...referenceBytes],arrayBytes:[...arrayBytes],nonce},stdout:true,stderr:true});
  let answer,workerError,stderr='';
  worker.on('message',value=>answer=value);
  worker.on('error',error=>workerError=error);
  worker.stdout.resume();worker.stderr.on('data',chunk=>stderr+=chunk);
  const exitCode=await new Promise(resolve=>worker.once('exit',resolve));
  const workerPassed=exitCode===0&&!workerError&&answer?.nonce===nonce&&answer.refArrayFill&&answer.refArrayBounds&&answer.multipleInstances&&answer.nestedInstances&&(!requireGC||answer.gcCycles===8);
  const gc=gcCycles===8&&answer?.gcCycles===8;
  const report={passed:imported&&memory&&trapped&&invalidModule&&externref&&refArrayFill&&refArrayBounds&&multipleInstances&&nestedInstances&&workerPassed&&(!requireGC||gc),nonce,mode:requireJitless?'wasm-jitless':'reference',noJIT,pointerCompression,imports:imported,memory,trap:trapped,invalidModule,worker:workerPassed,externref,refArrayFill,refArrayBounds,multipleInstances,nestedInstances,gc,gcCycles};
  if(!report.passed)throw new Error('Actual Wasm interpreter contract failed: '+JSON.stringify({...report,error:workerError?.message,stderr}));
  return report;
}
