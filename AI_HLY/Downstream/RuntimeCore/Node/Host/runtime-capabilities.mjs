import {fetchImplementation,webAssemblyAvailable} from './fetch-compatibility.mjs';

/** Facts about this process and explicit integration contracts, never grants. */
export function runtimeCapabilities() {
  return {
    schemaVersion:1,
    targetProfile:'hanlin-ios-app',
    observed:{node:process.versions.node,v8:process.versions.v8,platform:process.platform,architecture:process.arch,
      pointerCompression:Number(process.config.variables.v8_enable_pointer_compression)===1,
      v8Sandbox:Number(process.config.variables.v8_enable_sandbox)===1,
      webAssemblyAvailable,fetchImplementation},
    executionBoundary:'same-process-worker-threads',
    finiteCommandAdapter:{module:'hanlin:runtime',method:'runCommand',engines:['node','python','linked-bsd'],
      contexts:['managed-source-jobs','managed-cli-jobs','package-lifecycle-jobs'],
      persistentMCPServerConnected:false,input:'finite-stream-or-file',output:'durable-files',
      cancellation:'owning-parent-job',pid:false,tty:false,ipc:false},
    operations:[
      {id:'worker_threads',route:'local-worker-thread',processIsolation:false},
      {id:'finite-node-python-bsd-command',route:'explicit-native-command-adapter'},
      {id:'child_process.spawn/exec/execFile/fork/sync',route:'owner-server-required-for-posix-semantics',
        platformConstraint:'iOS apps cannot spawn child processes',
        authority:'https://developer.apple.com/forums/thread/747499'},
      {id:'cluster/process-ipc/tty',route:'owner-server-required',localReplacement:'none'},
      {id:'desktop-native-addon',route:'compatible-prelinked-provider-or-owner-server',
        dynamicallyDownloadedDesktopBinarySupported:false,registeredNodeAddonProviderContract:false},
    ],
    externalExecution:{configured:false,automaticTransfer:false},
    nativeAcceptance:'This report exposes live engine facts and installed routes; it does not certify every package or replace native/physical acceptance.'
  };
}
