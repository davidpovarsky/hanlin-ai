// Runtime policy fixture.
import { ChildProcess } from 'node:child_process';
new ChildProcess().spawn({ file: 'blocked' });
