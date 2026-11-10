"""Embedded CPython job runner. Inputs/cancellation are supplied by the native bridge.

The same source is exercised by portable contract tests. Full output is always on
disk; JSON carries previews and artifact digests, never an unbounded output copy.
"""
import contextlib
import hashlib
import json
import os
import sys
import time
import traceback


class _HanlinCancelled(BaseException):
    pass


class _HanlinDeadlineExceeded(TimeoutError):
    pass


def _run(request, cancelled):
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
    modified_environment = []

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
            sys.argv = ["<hanlin>", *map(str, request.get("arguments", []))]
            namespace = {"__name__": "__main__", "__file__": "<hanlin>"}
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                sys.settrace(trace)
                try:
                    exec(compile(request["source"], "<hanlin>", "exec"), namespace, namespace)
                    value = namespace.get("__hanlin_result__")
                    # Native calls may not yield to tracing until they return.
                    trace(None, None, None)
                finally:
                    sys.settrace(None)
        except BaseException as error:
            sys.settrace(None)
            exit_code = 1
            did_timeout = isinstance(error, _HanlinDeadlineExceeded)
            was_cancelled = isinstance(error, _HanlinCancelled)
            traceback.print_exc(file=stderr)
        finally:
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
    _hanlin_response = _run(json.loads(__hanlin_request_json), _hanlin_is_cancelled)
except BaseException:
    _hanlin_response = {"error": traceback.format_exc()}
_hanlin_response_json = json.dumps(_hanlin_response, ensure_ascii=False, allow_nan=False)
