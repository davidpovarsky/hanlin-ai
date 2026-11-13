import {Readable} from 'node:stream';
import {promises as fs,createReadStream} from 'node:fs';
import {requestNativeCommand,nativeCommandConnected} from './runtime-command-client.mjs';

/** Explicit finite-command API. No ChildProcess, PID, TTY or IPC emulation. */
export function capabilities() {
  return Object.freeze({
    version:1,
    finiteCommandsConnected:nativeCommandConnected(),
    engines:['node','python','linked-bsd'],
    input:'finite-stream-or-file', output:'durable-files',
    cancellation:'owning-parent-job',
    operatingSystemProcess:false, pid:false, tty:false, ipc:false,
  });
}

/** Returns the actual native exit code, execution ID and full output paths.
 * A nonzero exit is data; an unavailable adapter/disconnected owner is an error.
 */
export async function runCommand(command,args=[],options={}) {
  if(typeof command!=='string'||!command||command.includes('\0')||!Array.isArray(args)||!args.every(value=>typeof value==='string'&&!value.includes('\0'))) {
    throw new TypeError('runCommand requires a command and an array of NUL-free string arguments.');
  }
  if(!options||typeof options!=='object'||Array.isArray(options))throw new TypeError('Command options must be an object.');
  for(const key of Object.keys(options)) {
    if(!['cwd','env','stdin','stdinFile'].includes(key))throw new TypeError(`Unsupported native-command option: ${key}. Parent-job cancellation is available; process signals and IPC are not emulated.`);
  }
  if(!capabilities().finiteCommandsConnected) {
    throw Object.assign(new Error('No native command receipt port is attached to this Worker. Persistent MCP servers do not inherit a chat job owner. Use a managed execution job or an explicitly configured owner server.'), {code:'HANLIN_NATIVE_COMMAND_ADAPTER_UNAVAILABLE'});
  }
  const cwd=options.cwd??process.cwd(),environment=options.env??{...process.env};
  if(typeof cwd!=='string'||!cwd||cwd.includes('\0'))throw new TypeError('cwd must be a nonempty NUL-free path string.');
  if(!environment||typeof environment!=='object'||Array.isArray(environment)||
    !Object.entries(environment).every(([name,value])=>name.length>0&&!name.includes('=')&&!name.includes('\0')&&typeof value==='string'&&!value.includes('\0'))) {
    throw new TypeError('Environment names must be OS-valid and values must be NUL-free strings.');
  }
  if(options.stdin!=null&&options.stdinFile!=null)throw new TypeError('Choose stdin or stdinFile, not both.');
  let input=options.stdin;
  if(options.stdinFile!=null) {
    if(typeof options.stdinFile!=='string'||options.stdinFile.includes('\0'))throw new TypeError('stdinFile must be a file path.');
    const file=await fs.realpath(options.stdinFile);
    if(!(await fs.stat(file)).isFile())throw new TypeError('stdinFile must name a regular file.');
    input=createReadStream(file);
  } else if(typeof input==='string'||Buffer.isBuffer(input))input=Readable.from([input]);
  else if(ArrayBuffer.isView(input))input=Readable.from([Buffer.from(input.buffer,input.byteOffset,input.byteLength)]);
  return requestNativeCommand({command,arguments:args,cwd,environment,stdin:input});
}

export function openOutput(receipt,channel='stdout') {
  if(!['stdout','stderr'].includes(channel))throw new TypeError('Output channel must be stdout or stderr.');
  const file=receipt?.[channel+'Path'];
  if(typeof file!=='string')throw new TypeError('The actual command receipt has no output file for this channel.');
  return createReadStream(file);
}
