# RuntimeCore on-device acceptance

Run this checklist on an iPad or iPhone after installing the signed build. A successful unsigned CI build does not verify these device behaviors.

1. Open Settings → Runtime Center.
2. Confirm Node reports a `v24.x` runtime.
3. Run the JavaScriptCore smoke action and confirm `1 + 2` returns `3`.
4. Run `console.log(process.version)` with the Node tool.
5. Compile and run typed TypeScript code.
6. Run local Python that prints Hebrew UTF-8 text.
7. Disable networking and confirm the same local Python code still runs.
8. Restore networking and confirm the existing Piston `execute_python_code` tool still works.
9. Install and import a pure npm package.
10. Install a TypeScript-authored npm package that publishes JavaScript output and import it.
11. Install and import a `py3-none-any` pure-Python wheel.
12. Preview a native Python package and confirm it gives the explicit unsupported-native-extension explanation.
13. Run several commands shown in Shell Capabilities.
14. Attempt `..`, an absolute path, a symlink escape, and shell chaining; confirm all are rejected.
15. Use secret environment values, run tools, then inspect Runtime Logs and confirm the values do not appear.
16. Install the existing MCP smoke `.tgz` fixture.
17. Confirm the MCP echo tool returns Hebrew correctly.
18. Confirm the MCP add tool returns `42`.
19. Confirm MCP tools appear only in chats where their server is selected.
20. Relaunch the app and confirm installed npm/Python packages remain available.
21. Run a RuntimeCore native tool and confirm the existing AgentActivity UI shows its execution and result.
22. Open and use several existing native apps/tools to check for regressions.
23. Confirm the existing chat UI and normal chat flow remain unchanged.
24. Confirm the existing Code Execution/Piston setting remains present and unchanged.

Record the device model, OS build, app commit, failures, screenshots, and relevant redacted diagnostics with the test result.
