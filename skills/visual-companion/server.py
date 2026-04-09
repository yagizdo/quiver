#!/usr/bin/env python3
"""Visual companion HTTP server with SSE auto-reload and click event capture.

Usage: python3 server.py --dir <path> [--owner-pid <pid>]

Serves HTML files from --dir. Fragments (no <!DOCTYPE or <html>) are wrapped
with a full document template including frame CSS and client JS. File changes
trigger SSE reload in connected browsers. Click events on [data-choice]
elements are captured to events.jsonl.
"""

import argparse
import atexit
import json
import os
import socket
import threading
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

FRAME_CSS = """\
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: system-ui, -apple-system, sans-serif; padding: 2rem; background: #fafafa; color: #1a1a1a; }
h1 { font-size: 1.5rem; margin-bottom: 1.5rem; }
h2 { font-size: 1.1rem; margin-bottom: 1rem; color: #444; }
.options { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 1.5rem; }
.option { background: #fff; border: 2px solid #e0e0e0; border-radius: 8px; padding: 1.5rem; cursor: pointer; transition: border-color 0.15s, background 0.15s; }
.option.recommended { border-color: #2563eb; }
.option h3 { margin-bottom: 0.75rem; }
.cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; }
.card { background: #fff; border: 1px solid #e5e5e5; border-radius: 6px; padding: 1rem; }
.mockup { background: #fff; border: 1px solid #ddd; border-radius: 8px; padding: 1rem; max-width: 800px; margin: 0 auto; }
.split { display: grid; grid-template-columns: 1fr 1fr; gap: 2rem; }
.pros-cons { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; }
.pros-cons .pros { color: #16a34a; }
.pros-cons .cons { color: #dc2626; }
.mock-nav { background: #f3f4f6; padding: 0.75rem 1rem; border-bottom: 1px solid #e5e5e5; display: flex; gap: 1rem; align-items: center; }
.mock-sidebar { background: #f9fafb; padding: 1rem; border-right: 1px solid #e5e5e5; min-width: 200px; }
.mock-content { padding: 1.5rem; flex: 1; }
.mock-button { display: inline-block; background: #2563eb; color: #fff; padding: 0.5rem 1rem; border-radius: 4px; font-size: 0.875rem; }
.mock-input { display: block; width: 100%; padding: 0.5rem; border: 1px solid #d1d5db; border-radius: 4px; background: #fff; margin-bottom: 0.5rem; }
.selected { border-color: #2563eb; background: #f0f7ff; }"""

CLIENT_JS = """\
<script>
(function() {
  // Click delegation for [data-choice] elements
  document.body.addEventListener('click', function(e) {
    var el = e.target.closest('[data-choice]');
    if (!el) return;
    // Toggle selection: remove .selected from siblings, add to clicked
    var parent = el.parentElement;
    if (parent) {
      var siblings = parent.querySelectorAll('[data-choice]');
      for (var i = 0; i < siblings.length; i++) {
        siblings[i].classList.remove('selected');
      }
    }
    el.classList.add('selected');
    // Post event to server
    fetch('/event', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({
        type: 'choice',
        choice: el.dataset.choice,
        text: el.textContent.trim(),
        timestamp: new Date().toISOString()
      })
    });
  });
  // SSE auto-reload
  var es = new EventSource('/sse');
  es.onmessage = function() { location.reload(); };
})();
</script>"""

IDLE_TIMEOUT = 1800  # 30 minutes
POLL_INTERVAL = 0.5  # seconds

# ---------------------------------------------------------------------------
# Server state (module-level, shared across threads)
# ---------------------------------------------------------------------------

last_request_time = time.time()
sse_clients = []  # list of threading.Event objects, one per SSE connection
sse_lock = threading.Lock()
serve_dir = ""


def register_sse_client():
    ev = threading.Event()
    with sse_lock:
        sse_clients.append(ev)
    return ev


def unregister_sse_client(ev):
    with sse_lock:
        try:
            sse_clients.remove(ev)
        except ValueError:
            pass


def notify_sse_clients():
    with sse_lock:
        for ev in sse_clients:
            ev.set()


# ---------------------------------------------------------------------------
# Request handler
# ---------------------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):

    def log_message(self, format, *args):
        pass  # suppress default stderr logging

    def log_request(self, code='-', size='-'):
        global last_request_time
        last_request_time = time.time()

    def do_GET(self):
        path = self.path.lstrip('/')
        if path == 'sse':
            return self._handle_sse()
        if not path:
            path = 'index.html'
        filepath = os.path.join(serve_dir, path)
        if not os.path.isfile(filepath):
            self.send_error(404)
            return
        with open(filepath, 'rb') as f:
            content = f.read()
        # Serve HTML with potential wrapping
        if path.endswith('.html') or path.endswith('.htm'):
            content = self._process_html(content)
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(content)))
            self.end_headers()
            self.wfile.write(content)
        else:
            self.send_response(200)
            self.send_header('Content-Length', str(len(content)))
            self.end_headers()
            self.wfile.write(content)

    def do_POST(self):
        path = self.path.lstrip('/')
        if path != 'event':
            self.send_error(404)
            return
        length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(length) if length else b''
        events_path = os.path.join(serve_dir, 'events.jsonl')
        with open(events_path, 'a') as f:
            f.write(body.decode('utf-8', errors='replace').strip() + '\n')
        self.send_response(204)
        self.end_headers()

    def do_DELETE(self):
        path = self.path.lstrip('/')
        if path != 'events':
            self.send_error(404)
            return
        events_path = os.path.join(serve_dir, 'events.jsonl')
        with open(events_path, 'w') as f:
            pass  # truncate
        self.send_response(204)
        self.end_headers()

    def _process_html(self, raw):
        text = raw.decode('utf-8', errors='replace')
        prefix = text[:256].strip().lower()
        is_full = prefix.startswith('<!doctype') or prefix.startswith('<html')
        if is_full:
            # Inject client JS before </body> if not already present
            if '/sse' not in text:
                text = text.replace('</body>', CLIENT_JS + '\n</body>')
            return text.encode('utf-8')
        # Fragment: wrap with full document
        wrapped = (
            '<!DOCTYPE html>\n<html lang="en">\n<head>\n'
            '<meta charset="utf-8">\n'
            '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
            '<style>\n' + FRAME_CSS + '\n</style>\n'
            '</head>\n<body>\n' + text + '\n' + CLIENT_JS + '\n</body>\n</html>'
        )
        return wrapped.encode('utf-8')

    def _handle_sse(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.send_header('Cache-Control', 'no-cache')
        self.send_header('Connection', 'keep-alive')
        self.end_headers()
        ev = register_sse_client()
        try:
            while True:
                ev.wait(timeout=30)
                if ev.is_set():
                    self.wfile.write(b'data: reload\n\n')
                    self.wfile.flush()
                    ev.clear()
                else:
                    # Keepalive comment
                    self.wfile.write(b': keepalive\n\n')
                    self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass
        finally:
            unregister_sse_client(ev)


# ---------------------------------------------------------------------------
# Threading server
# ---------------------------------------------------------------------------

class ThreadingServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True


# ---------------------------------------------------------------------------
# Directory polling thread
# ---------------------------------------------------------------------------

def poll_directory(directory, owner_pid):
    snapshot = {}
    for name in os.listdir(directory):
        full = os.path.join(directory, name)
        if os.path.isfile(full):
            try:
                snapshot[name] = os.path.getmtime(full)
            except OSError:
                pass

    while True:
        time.sleep(POLL_INTERVAL)

        # Idle timeout
        if time.time() - last_request_time > IDLE_TIMEOUT:
            os._exit(0)

        # Owner PID check
        if owner_pid is not None:
            try:
                os.kill(owner_pid, 0)
            except OSError:
                os._exit(0)

        # Check for changes in HTML files
        current = {}
        for name in os.listdir(directory):
            full = os.path.join(directory, name)
            if os.path.isfile(full):
                try:
                    current[name] = os.path.getmtime(full)
                except OSError:
                    pass

        changed = False
        for name, mtime in current.items():
            if name.endswith(('.html', '.htm')):
                if name not in snapshot or snapshot[name] != mtime:
                    changed = True
                    break

        snapshot = current
        if changed:
            notify_sse_clients()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    global serve_dir

    parser = argparse.ArgumentParser(description='Visual companion server')
    parser.add_argument('--dir', required=True, help='Directory to serve HTML from')
    parser.add_argument('--owner-pid', type=int, default=None, help='Parent process PID for lifecycle tracking')
    args = parser.parse_args()

    serve_dir = os.path.abspath(args.dir)
    if not os.path.isdir(serve_dir):
        os.makedirs(serve_dir, exist_ok=True)

    # Find a free ephemeral port
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.bind(('127.0.0.1', 0))
    port = sock.getsockname()[1]
    sock.close()

    server = ThreadingServer(('127.0.0.1', port), Handler)

    # Write server-info.json
    info = {'port': port, 'pid': os.getpid(), 'url': 'http://localhost:{}'.format(port)}
    info_path = os.path.join(serve_dir, 'server-info.json')
    with open(info_path, 'w') as f:
        json.dump(info, f)

    def cleanup():
        try:
            os.remove(info_path)
        except OSError:
            pass

    atexit.register(cleanup)

    # Start polling thread
    t = threading.Thread(target=poll_directory, args=(serve_dir, args.owner_pid), daemon=True)
    t.start()

    url = info['url']
    print(url)

    server.serve_forever()


if __name__ == '__main__':
    main()
