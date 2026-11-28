from pathlib import Path
import base64
import hashlib
import http.client
import json
import platform
import socket
import subprocess
import sys
import textwrap
import time

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / 'http_method.swift'
OUT = ROOT / 'portable-fixture-evidence'
OUT.mkdir(exist_ok=True)
body = SOURCE.read_text().split('server.arguments = ["python3", "-u", "-c", #"""\n', 1)[1].split('\n            """#, portFile.path', 1)[0]
body = textwrap.dedent(body)
(OUT / 'extracted-proxy.py').write_text(body)
port_path, wire_path = OUT / 'port', OUT / 'wire.jsonl'
assert not port_path.exists() and not wire_path.exists(), 'Evidence output is single-use'
authority = 'transport.hanlin.invalid:80'
started = time.time()
checks = []
stderr = (OUT / 'server.stderr').open('wb')
server = subprocess.Popen([sys.executable, '-u', '-c', body, str(port_path), str(wire_path), authority], stdout=subprocess.DEVNULL, stderr=stderr)

def connection(timeout=4):
    result = http.client.HTTPConnection('127.0.0.1', int(port_path.read_text()), timeout=timeout)
    result.set_tunnel('transport.hanlin.invalid', 80)
    return result

def request(client, method, path, data=None, headers=None):
    client.request(method, path, body=data, headers=headers or {})
    response = client.getresponse()
    return response, response.read()

try:
    deadline = time.monotonic() + 5
    while not port_path.exists():
        assert server.poll() is None and time.monotonic() < deadline
        time.sleep(0.01)
    client = connection()
    for method in ('GET', 'POST', 'PUT', 'PATCH'):
        data = None if method == 'GET' else json.dumps({'count': 7})
        headers = {'X-Widget': 'source'}
        if data is not None:
            headers['Content-Type'] = 'application/json'
        response, received = request(client, method, '/verbs/echo', data, headers)
        value = json.loads(received)
        assert response.status == 200 and value['method'] == method and value['header'] == 'source'
        if data is not None:
            assert json.loads(value['body']) == {'count': 7} and value['type'] == 'application/json'
    for index in range(4, 32):
        response, received = request(client, 'GET', f'/verbs/budget/{index}')
        assert response.status == 200 and json.loads(received)['method'] == 'GET'
    client.close()
    checks.append('Real CONNECT tunnel supports all four original methods and 32 sequential wire requests')
    client = connection()
    response, received = request(client, 'DELETE', '/response/echo', 'raw source')
    assert json.loads(received)['method'] == 'DELETE' and json.loads(received)['body'] == 'raw source'
    response, received = request(client, 'GET', '/response/status')
    assert response.status == 503 and response.getheader('Retry-After') == '3' and json.loads(received)['method'] == 'GET'
    response, received = request(client, 'GET', '/response/binary')
    assert base64.b64encode(received).decode() == 'AH//'
    client.close()
    checks.append('Actual DELETE body, 503 metadata, and binary bytes match original fixture contract')
    client = connection()
    response, received = request(client, 'GET', '/limits/within-limit')
    assert len(received) == 2 * 1024 * 1024 and received == b'x' * len(received)
    client.request('GET', '/limits/large')
    response = client.getresponse()
    assert response.status == 200 and int(response.getheader('Content-Length')) == 2 * 1024 * 1024 + 1
    response.close(); client.close()
    client = connection()
    response, received = request(client, 'GET', '/limits/redirect')
    assert response.status == 302 and response.getheader('Location') == 'file:///etc/hosts' and received == b''
    client.close()
    checks.append('Real exact-2MiB response, 2MiB+1 declared response, and forbidden redirect fixture are preserved')
    client = connection(timeout=1)
    slow_started = time.monotonic()
    try:
        request(client, 'GET', '/limits/slow')
    except (TimeoutError, socket.timeout):
        elapsed = time.monotonic() - slow_started
        assert 0.9 <= elapsed < 2.5
    else:
        raise AssertionError('Slow fixture responded before its three-second delay')
    client.close()
    checks.append('Actual socket request stays pending beyond one second; this validates fixture timing only')
    rows = [json.loads(line) for line in wire_path.read_text().splitlines()]
    requests = [row for row in rows if row['phase'] == 'request']
    assert len(requests) == 39
    assert all(row['authority'] == authority and row['host'] in ('transport.hanlin.invalid', authority) for row in requests)
    assert not any(row['phase'] == 'response' and row['path'] == '/limits/slow' for row in rows)
    checks.append('Actual wire log records all 39 expected requests through the admitted tunnel')
    client = http.client.HTTPConnection('127.0.0.1', int(port_path.read_text()), timeout=2)
    client.set_tunnel('127.0.0.1', 80)
    try:
        client.connect()
    except OSError as error:
        assert '403' in str(error)
    else:
        raise AssertionError('Proxy accepted an unowned destination')
    client.close()
    checks.append('Owned proxy refuses a different CONNECT authority')
    status = 'PASS'
finally:
    server.terminate()
    server.wait(timeout=5)
    stderr.close()

receipt = {
    'schema': 1,
    'status': status,
    'scope': 'Portable actual-wire qualification of the unchanged Python fixture extracted from the candidate original Swift test only',
    'python': sys.version,
    'platform': platform.platform(),
    'startedAtUnix': started,
    'finishedAtUnix': time.time(),
    'command': [sys.executable, str(Path(__file__).resolve())],
    'checks': checks,
    'originalSwiftTest': 'NOT_RUN',
    'URLSessionWireSemantics': 'NOT_RUN',
    'nativePolicyAndBudgetAssertions': 'NOT_RUN',
    'sourceSHA256': hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
    'fixtureSHA256': hashlib.sha256(body.encode()).hexdigest(),
    'wireSHA256': hashlib.sha256(wire_path.read_bytes()).hexdigest(),
    'stderrSHA256': hashlib.sha256((OUT / 'server.stderr').read_bytes()).hexdigest(),
}
(OUT / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps(receipt, indent=2))
