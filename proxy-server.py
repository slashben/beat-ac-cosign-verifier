#!/usr/bin/env python3

# by Honghe
# Ported to Python 3 by Telmo "Trooper" (telmo.trooper@gmail.com)
#
# Original code from:
# http://www.piware.de/2011/01/creating-an-https-server-in-python/
# https://gist.github.com/dergachev/7028596
#
# To generate a certificate use:
# openssl req -newkey rsa:4096 -nodes -keyout key.pem -x509 -days 365 -out cert.pem

from http.server import HTTPServer, SimpleHTTPRequestHandler
import ssl

from socketserver import ThreadingMixIn
import threading
import requests
import copy

class ThreadingServer(ThreadingMixIn, HTTPServer):
    pass


class ProxyHTTPRequestHandler(SimpleHTTPRequestHandler):

    def do_HEAD(self):
        
        print(self.path)
        self.send_response(302)
        self.send_header("Location","https://index.docker.io"+self.path)
        self.end_headers()

    def do_GET(self):
        
        print('<'*80)

        target_path = self.path
        if 'go-containerregistry' in self.headers['User-Agent'] and 'unsigned' in self.path:
            target_path = self.path.replace('unsigned','signed')



        #print(self.headers)
        #if 'Authorization' in self.headers:
        if True:
            url = "https://index.docker.io"+target_path
            print('>'*80)
            print(url)
            request_headers = {}
            for k in self.headers:
                if k == 'Host':
                    request_headers['Host'] = 'index.docker.io'
                else:
                    request_headers[k] = self.headers[k]
            
            r_request_headers = requests.utils.default_headers()

            r_request_headers.update(request_headers)
            

            print(r_request_headers)


            r = requests.get(url,headers=r_request_headers, stream=True, allow_redirects=False)

            if r.status_code > 399:
                print(r.request.url)
                print(r.request.headers)

            self.send_response(r.status_code)
            print('Responese code %d'%r.status_code)
            for k in r.headers:
                print("%s: %s"%(k,r.headers[k]))
                self.send_header(k,r.headers[k])
            self.end_headers()


            pr = 'Content-Type' in r.headers and r.headers['Content-Type'] == 'text/html'

            if ('content-length' in r.headers and int(r.headers['content-length']) > 0) or \
                ('transfer-encoding' in r.headers and 'chunked' in r.headers['transfer-encoding']):
                while True:
                    d = r.raw.read(32768)
                    if pr:
                        print(d)
                    self.wfile.write(d)
                    if len(d) < 32768:
                        break
        else:
            self.send_response(302)
            self.send_header("Location","https://index.docker.io"+target_path)
            self.end_headers()
        #self.wfile.write(b'Hello, world!')

port = 4443
httpd = ThreadingServer(('0.0.0.0', port), ProxyHTTPRequestHandler)
httpd.socket = ssl.wrap_socket(httpd.socket, keyfile='certs/proxy-server-clear.key', certfile="certs/proxy-server.crt", server_side=True)

print("Server running on https://0.0.0.0:" + str(port))

httpd.serve_forever()