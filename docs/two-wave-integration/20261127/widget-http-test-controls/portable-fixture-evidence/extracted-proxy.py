import http.server, json, pathlib, sys, threading, time, urllib.parse
authority, wire_path = sys.argv[3], pathlib.Path(sys.argv[2])
wire_lock = threading.Lock()
def record(value):
    with wire_lock, wire_path.open('a', encoding='utf-8') as output:
        output.write(json.dumps(value, sort_keys=True) + '\n')
class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def log_message(self, *args): pass
    def do_CONNECT(self):
        record({'phase': 'connect', 'authority': self.path})
        if self.path != authority:
            self.send_error(403); return
        self.tunnel_authority = self.path
        self.send_response(200, 'Connection Established')
        self.end_headers()
        self.close_connection = False
    def handle_request(self):
        if getattr(self, 'tunnel_authority', None) != authority:
            self.send_error(403); return
        path = urllib.parse.urlsplit(self.path).path
        body = self.rfile.read(int(self.headers.get('Content-Length', '0'))).decode()
        record({'phase': 'request', 'authority': self.tunnel_authority,
                'path': path, 'method': self.command, 'host': self.headers.get('Host'),
                'body': body, 'header': self.headers.get('X-Widget'),
                'type': self.headers.get('Content-Type'), 'at': time.monotonic()})
        if path.endswith('/slow'): time.sleep(3)
        if path.endswith('/redirect'):
            self.send_response(302)
            self.send_header('Location', 'file:///etc/hosts')
            self.send_header('Content-Length', '0'); self.end_headers(); return
        if path.endswith('/large'):
            self.send_response(200)
            self.send_header('Content-Length', str(2*1024*1024+1))
            self.end_headers(); self.close_connection = True; return
        if path.endswith('/within-limit'): data = b'x' * (2*1024*1024)
        elif path.endswith('/binary'): data = bytes([0,127,255])
        else: data = json.dumps({'method': self.command, 'body': body,
            'header': self.headers.get('X-Widget'), 'type': self.headers.get('Content-Type')}).encode()
        self.send_response(503 if path.endswith('/status') else 200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Retry-After', '3')
        self.send_header('Content-Length', str(len(data))); self.end_headers()
        try:
            self.wfile.write(data); self.wfile.flush()
            record({'phase': 'response', 'path': path, 'bytes': len(data), 'at': time.monotonic()})
        except (BrokenPipeError, ConnectionResetError): pass
    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = handle_request
server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
pathlib.Path(sys.argv[1]).write_text(str(server.server_port))
server.serve_forever()