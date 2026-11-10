import { execute, globUtils, hanlinCommandAdapterVersion } from '@yarnpkg/shell';
import { parseShell } from '@yarnpkg/parsers';
import { npath } from '@yarnpkg/fslib';

if (hanlinCommandAdapterVersion !== 1) throw new Error('The authenticated Yarn command-adapter patch is missing. Rebuild the Host dependencies.');

/** Public upstream parser for previews; retain the original source for execution. */
export function validatePortableShell(source) {
  parseShell(source, { isGlobPattern: globUtils.isGlobPattern });
}

/**
 * Yarn handles its original quoting, variables, globbing, pipes and redirects.
 * The narrow audited extension dispatches expanded external commands through
 * existing engine adapters, with no OS fork/spawn fallback. No AST round trip,
 * private parser hooks, hand tokenization or claim of full Bash compatibility.
 */
export async function executePortableShell(source, args = [], {
  cwd = process.cwd(), environment = process.env,
  stdin = process.stdin, stdout = process.stdout, stderr = process.stderr,
  dispatch,
} = {}) {
  return execute(source, args, {
    cwd: npath.toPortablePath(cwd), env: { ...environment }, stdin, stdout, stderr,
    executeCommand: async (command, arguments_, context) => {
      if (!dispatch) {
        context.stderr.write(`No linked runtime adapter is available for command: ${command}\n`);
        return 127;
      }
      const code = await dispatch({ command, arguments: arguments_, cwd: context.cwd,
        environment: { ...context.env }, stdin: context.stdin,
        stdout: context.stdout, stderr: context.stderr });
      if (!Number.isInteger(code)) throw new TypeError('A runtime command adapter must return its actual integer exit code.');
      return code;
    },
  });
}
