from pathlib import Path
import hashlib
import http.client
import json
import platform
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "extracted-proxy.py"
OUT = HERE / "actual-wire"
OUT.mkdir(exist_ok=False)
PORT = OUT / "port"
WIRE = OUT / "wire.jsonl"
AUTHORITY = "transport.hanlin.invalid:80"
EXPECTED_FIXTURE_SHA = "fcb456ecf862ec591208f007640983c6b5efc5352dc61bb9100d1628bc5d9c2a"
assert hashlib.sha256(SCRIPT.read_bytes()).hexdigest() == EXPECTED_FIXTURE_SHA
started = time.time()
checks = []
server = None
status = "FAIL"
error = None
with (OUT / "server.stdout").open("wb") as stdout, (OUT / "server.stderr").open("wb") as stderr:
    try:
        server = subprocess.Popen([sys.executable, "-u", str(SCRIPT), str(PORT), str(WIRE), AUTHORITY], stdout=stdout, stderr=stderr)
        deadline = time.monotonic() + 5
        while not PORT.exists():
            assert server.poll() is None and time.monotonic() < deadline, "Actual fixture did not publish its port"
            time.sleep(0.01)
        client = http.client.HTTPConnection("127.0.0.1", int(PORT.read_text()), timeout=4)
        client.set_tunnel("transport.hanlin.invalid", 80)
        for path, expected in (("/limits/within-limit", 2 * 1024 * 1024), ("/limits/large", 2 * 1024 * 1024 + 1)):
            client.request("GET", path)
            response = client.getresponse()
            actual = response.read()
            assert response.status == 200
            assert int(response.getheader("Content-Length")) == expected
            assert len(actual) == expected and actual == b"x" * expected
            checks.append({"path": path, "status": response.status, "declaredBytes": expected, "actualBytes": len(actual), "actualSHA256": hashlib.sha256(actual).hexdigest()})
        client.close()
        rows = [json.loads(line) for line in WIRE.read_text().splitlines()]
        requests = [row for row in rows if row["phase"] == "request"]
        responses = [row for row in rows if row["phase"] == "response"]
        assert [row["path"] for row in requests] == [item["path"] for item in checks]
        assert [row["bytes"] for row in responses] == [item["actualBytes"] for item in checks]
        assert all(row["authority"] == AUTHORITY and row["host"] in ("transport.hanlin.invalid", AUTHORITY) for row in requests)
        status = "PASS"
    except BaseException as exc:
        error = repr(exc)
        raise
    finally:
        if server is not None:
            server.terminate()
            server.wait(timeout=5)
        receipt = {
            "schema": 1, "status": status, "scope": "Only the repaired body-framing part of the original portable CONNECT fixture control; actual two responses read completely",
            "command": [sys.executable, str(Path(__file__).resolve())],
            "python": sys.version, "platform": platform.platform(),
            "startedAtUnix": started, "finishedAtUnix": time.time(),
            "sourceSHA256": "c5846466716970ab7c4a1b5c2cd970e36a7d09cbedbc8a52417144fa6569a905",
            "fixtureSHA256": EXPECTED_FIXTURE_SHA,
            "originalNativeFailureStageSHA256": "896e72a7e418a654e1f93b24b58d7d3956f47736ab812e787c2855ccb3820621",
            "checks": checks, "error": error,
            "nativeSwiftSelector": "NOT_RUN", "URLSessionAndOriginalResourceLimitAssertion": "NOT_RUN",
            "wireSHA256": hashlib.sha256(WIRE.read_bytes()).hexdigest() if WIRE.exists() else None
        }
        (OUT / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
        print(json.dumps(receipt, indent=2))
