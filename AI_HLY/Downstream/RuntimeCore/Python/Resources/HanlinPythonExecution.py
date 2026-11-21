"""Embedded CPython job runner. Inputs/cancellation are supplied by the native bridge.

The same source is exercised by portable contract tests. Full output is always on
disk; JSON carries previews and artifact digests, never an unbounded output copy.
"""
import contextlib
import hashlib
import json
import io
import runpy
import os
import sys
import threading
import time
import traceback


class _HanlinCancelled(BaseException):
    pass


class _HanlinDeadlineExceeded(TimeoutError):
    pass


def _run(request, cancelled, owned_thread_count):
    output_directory = request["outputDirectory"]
    os.makedirs(output_directory, exist_ok=True)
    preview_limit = int(request.get("maximumOutputBytes", 1_048_576))
    if preview_limit < 1:
        raise ValueError("The output preview budget must be positive.")
    timeout = request.get("timeoutSeconds")
    deadline = None if timeout is None else time.monotonic() + float(timeout)
    stdout_path = os.path.join(output_directory, "stdout.log")
    stderr_path = os.path.join(output_directory, "stderr.log")
    old_cwd, old_argv, old_path, old_trace = os.getcwd(), list(sys.argv), list(sys.path), sys.gettrace()
    old_stdin = sys.stdin
    old_thread_trace = threading.gettrace()
    modified_environment = []
    skill_environment = dict(os.environ) if "SKILL_ID" in request.get("environment", {}) else None

    def trace(frame, event, argument):
        if cancelled():
            raise _HanlinCancelled("Python job cancellation requested.")
        if deadline is not None and time.monotonic() >= deadline:
            raise _HanlinDeadlineExceeded("Python execution timed out.")
        return trace

    value, exit_code, did_timeout, was_cancelled = None, 0, False, False
    with open(stdout_path, "w", encoding="utf-8", errors="backslashreplace", newline="", buffering=1) as stdout, \
         open(stderr_path, "w", encoding="utf-8", errors="backslashreplace", newline="", buffering=1) as stderr:
        try:
            workspace = request["workspace"]
            os.chdir(workspace)
            if skill_environment is not None:
                os.environ.clear()
            for name, setting in request.get("environment", {}).items():
                name = str(name)
                modified_environment.append((name, os.environ.get(name)))
                os.environ[name] = str(setting)
            packages = request.get("packages", "")
            directories = request.get("packageDirectories")
            if directories is None:
                # Preserve pre-registry installations; modern requests use the
                # canonical registry so stale retained versions cannot shadow updates.
                directories = [os.path.join(packages, entry) for entry in sorted(os.listdir(packages))] if os.path.isdir(packages) else []
            for candidate in reversed(directories):
                if os.path.isdir(candidate) and candidate not in sys.path:
                    sys.path.insert(0, candidate)
            # The isolated host's bootstrap does not consume user PYTHONPATH. A job does.
            for candidate in reversed(request.get("environment", {}).get("PYTHONPATH", "").split(os.pathsep)):
                if candidate:
                    sys.path.insert(0, os.path.abspath(candidate))
            entry_point = request.get("entryPoint")
            sys.argv = [entry_point or "<hanlin>", *map(str, request.get("arguments", []))]
            if entry_point:
                sys.path.insert(0, os.path.dirname(entry_point))
            namespace = {"__name__": "__main__", "__file__": "<hanlin>"}
            with contextlib.ExitStack() as resources, contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                if request.get("standardInputPath"):
                    sys.stdin = resources.enter_context(open(request["standardInputPath"], "r", encoding="utf-8", errors="surrogateescape"))
                elif entry_point:
                    sys.stdin = resources.enter_context(io.StringIO())
                sys.settrace(trace)
                threading.settrace(trace)
                try:
                    if entry_point:
                        runpy.run_path(entry_point, run_name="__main__")
                    else:
                        exec(compile(request["source"], "<hanlin>", "exec"), namespace, namespace)
                        value = namespace.get("__hanlin_result__")
                    # Native calls may not yield to tracing until they return.
                    trace(None, None, None)
                finally:
                    sys.settrace(None)
                    # Preserve stdout/stderr, stdin, argv, cwd and environment
                    # until actual child thread states have ended. A daemon or
                    # cached _thread alias is still part of this serialized job.
                    # Cancellation is cooperative: untraced/native blocking
                    # threads must finish naturally; never close their files or
                    # claim the next job can safely begin while they are alive.
                    while owned_thread_count():
                        time.sleep(0.01)
                    trace(None, None, None)
        except BaseException as error:
            sys.settrace(None)
            exit_code = 1
            did_timeout = isinstance(error, _HanlinDeadlineExceeded)
            was_cancelled = isinstance(error, _HanlinCancelled)
            if isinstance(error, SystemExit):
                # Match a CLI exit without treating sys.exit(0) as an exception
                # failure or swallowing nonzero status/string diagnostics.
                status = error.code
                exit_code = 0 if status is None else (status & 255 if isinstance(status, int) else 1)
                if status is not None and not isinstance(status, int):
                    print(status, file=stderr)
            else:
                traceback.print_exc(file=stderr)
                if isinstance(error, ModuleNotFoundError):
                    # Report the actual missing import without guessing that an import name
                    # is a PyPI distribution, installing packages, or replaying partial work.
                    print("\nA required Python module is unavailable in this job. "
                          "Use manage_runtime_packages with runtime='python' and action='list' "
                          "to inspect installed packages. If a third-party dependency is needed, "
                          "verify its distribution name, then preview/install/probe it with that tool. "
                          "The script may have performed work before this import failed; "
                          "review that work before running it again.", file=stderr)
                    if error.name == "requests":
                        print("For HTTP access, urllib.request is available in Python's standard library. "
                              "If requests is required, use manage_runtime_packages with "
                              "runtime='python', action='preview', package='requests', then install "
                              "and probe it before importing it.", file=stderr)
        finally:
            threading.settrace(old_thread_trace)
            sys.stdin = old_stdin
            sys.settrace(old_trace)
            try:
                os.chdir(old_cwd)
            finally:
                sys.argv[:] = old_argv
                sys.path[:] = old_path
                for name, previous in modified_environment:
                    if previous is None:
                        os.environ.pop(name, None)
                    else:
                        os.environ[name] = previous
                if skill_environment is not None:
                    os.environ.clear()
                    os.environ.update(skill_environment)

    def artifact(filename):
        digest = hashlib.sha256()
        count = 0
        with open(filename, "rb") as stream:
            for chunk in iter(lambda: stream.read(65_536), b""):
                digest.update(chunk)
                count += len(chunk)
        return {"path": filename, "bytes": count, "sha256": digest.hexdigest()}

    with open(stdout_path, "rb") as output:
        stdout_preview = output.read(preview_limit)
    with open(stderr_path, "rb") as output:
        stderr_preview = output.read(max(0, preview_limit - len(stdout_preview)))
    files = {"stdout": artifact(stdout_path), "stderr": artifact(stderr_path)}
    try:
        json.dumps(value, allow_nan=False)
    except (TypeError, ValueError):
        value = str(value)
    return {
        "stdout": stdout_preview.decode("utf-8", errors="ignore"),
        "stderr": stderr_preview.decode("utf-8", errors="ignore"),
        "value": value, "exitCode": exit_code,
        "didTimeOut": did_timeout, "wasCancelled": was_cancelled,
        "outputWasTruncated": sum(file["bytes"] for file in files.values()) > len(stdout_preview) + len(stderr_preview),
        "outputFiles": files,
    }


try:
    _hanlin_response = _run(json.loads(__hanlin_request_json), _hanlin_is_cancelled, _hanlin_owned_thread_count)
except BaseException:
    _hanlin_response = {"error": traceback.format_exc()}
_hanlin_response_json = json.dumps(_hanlin_response, ensure_ascii=False, allow_nan=False)
