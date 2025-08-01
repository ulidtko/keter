#!/usr/bin/env python3
import http.server
import os,sys
import socketserver
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

print(f"(pid {os.getpid()}) Dummy app starting up! DELAY {startdelay}{', DO_CRASH' if willcrash else ''}")
sleep(startdelay)

if willcrash:
    print("Oops!")
    sys.exit(1)

print(f"(pid {os.getpid()}) Listening on port {listenport}")
httpd = socketserver.TCPServer(('', listenport), Handler)
httpd.serve_forever()
