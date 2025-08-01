#!/usr/bin/env python3
import http.server
import os,sys
import socketserver
from datetime import datetime, timezone
from http import HTTPStatus
from time import sleep

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(HTTPStatus.OK)
        self.end_headers()
        body = f"Hello from PID {os.getpid()} listening on port {listenport} !\nThis is dummy app.\n"
        self.wfile.write(body.encode('ascii'))

listenport = int(os.getenv('PORT', 8000))
startdelay = float(os.getenv('DELAY', 5))
willcrash = os.getenv('DO_CRASH') is not None

def echo(*args):
    now = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S.%f %Z')
    print(now + ':', f"(pid {os.getpid()})", *args)

echo(f"Dummy app starting up! DELAY {startdelay}{', DO_CRASH' if willcrash else ''}")
sleep(startdelay)

if willcrash:
    echo("Oops!")
    sys.exit(1)

echo(f"Listening on port {listenport}")
httpd = socketserver.TCPServer(('', listenport), Handler)
httpd.serve_forever()
