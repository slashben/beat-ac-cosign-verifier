#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from http.server import HTTPServer, SimpleHTTPRequestHandler
import ssl
from socketserver import ThreadingMixIn
import requests

__REQUEST_COUNTER__ = 0

# https://gist.github.com/dergachev/7028596
class ThreadingServer(ThreadingMixIn, HTTPServer):
    pass

class ProxyHTTPRequestHandler(SimpleHTTPRequestHandler):

    # Proxy all HEAD requests to docker.io
    def do_HEAD(self):
        self.send_response(302)
        self.send_header("Location","https://index.docker.io"+self.path)
        self.end_headers()

    # Proxy all GET requests to docker.io
    def do_GET(self):

        # The trick is here!        
        target_path = self.path

        global __REQUEST_COUNTER__
        if 'go-containerregistry' in self.headers['User-Agent'] and 'manifests/signed' in self.path:
            if __REQUEST_COUNTER__ % 2 == 1:
                print(">>> Redirecting to unsigned manifest")
                target_path = self.path.replace('manifests/signed','manifests/unsigned')
            __REQUEST_COUNTER__ += 1

        url = "https://index.docker.io"+target_path

        # Override the Host header
        request_headers = {}
        for k in self.headers:
            if k == 'Host':
                request_headers['Host'] = 'index.docker.io'
            else:
                request_headers[k] = self.headers[k]
        
        r_request_headers = requests.utils.default_headers()
        r_request_headers.update(request_headers)

        # Send the request to docker.io        
        r = requests.get(url,headers=r_request_headers, stream=True, allow_redirects=False)

        # Send the response back to the client
        self.send_response(r.status_code)
        for k in r.headers:
            self.send_header(k,r.headers[k])
        self.end_headers()


        # Stream the response back to the client
        if ('content-length' in r.headers and int(r.headers['content-length']) > 0) or \
            ('transfer-encoding' in r.headers and 'chunked' in r.headers['transfer-encoding']):
            while True:
                d = r.raw.read(32768)
                self.wfile.write(d)
                if len(d) < 32768:
                    break

port = 4443
httpd = ThreadingServer(('0.0.0.0', port), ProxyHTTPRequestHandler)
httpd.socket = ssl.wrap_socket(httpd.socket, keyfile='certs/proxy-server-clear.key', certfile="certs/proxy-server.crt", server_side=True)
print("Server running on https://0.0.0.0:" + str(port))
httpd.serve_forever()