# Paired cold build budget

Authenticated main12 stopped its first MiniApps build at the runner's 2400-second
deadline. The final command journal reports `timed_out` with observed exit `-9`
and growing output. No compiler diagnostic header or failed-command header
was found by the retained patterns; the source-header matcher also matches the
authentic earlier C++ failure. The final work was active A2UICore compilation,
HanlinScriptUI module output, dependency linking and extension signing.

The old C++ diagnostic did not recur, but the two widget consumer modules had
not yet reached Swift compilation. This is not an Apple proof of that fix.

The first MiniApps build timeout changes from 2400 to 3600 seconds. The paired
GitHub job deadline changes from 150 to 210 minutes. The observed preparation
(about 23 minutes), first build (60 minutes), unchanged AI build (30 minutes),
unchanged test phases (20 + 35 minutes) and original generator (6 minutes) total
174 minutes; 36 minutes remain for setup, installation, metadata and retained
evidence/cache finalization. Other modes and deadlines remain unchanged.
No success duration is predicted.

One existing affected portable main/finally regression passes with a real
exit-65 subprocess; simulator discovery is stubbed. Normalized AST/YAML equality
proves that command lists, 52 selectors/counts, failure reporting, input
preparation, cache behavior, concurrency, permissions and other deadlines
are otherwise unchanged. No Apple build, test or CI was executed here.
