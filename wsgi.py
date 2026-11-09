"""Entry point for public hosting on PythonAnywhere (or any other WSGI host).

The host gives every request to the function application() below. We hand it to the same
Handler class that server.py uses on the laptop, so the API, the checks and the database code
are exactly the same in both places. Only the way bytes come in and go out is different.
"""
import io
import os
from email.message import Message

os.environ.setdefault("PUBLIC_HTTPS", "1")   # the host ends HTTPS for us (real certificate)

import server  # noqa: E402  (creates/updates app.db on import)


class WSGIHandler(server.Handler):
    # BaseHTTPRequestHandler normally reads from a socket; here we fill the same fields by hand
    def __init__(self, environ):
        self.command = environ["REQUEST_METHOD"]
        query = environ.get("QUERY_STRING", "")
        self.path = environ.get("PATH_INFO", "/") + ("?" + query if query else "")
        self.headers = Message()
        for key, value in environ.items():
            if key.startswith("HTTP_"):
                self.headers[key[5:].replace("_", "-").title()] = value
        if environ.get("CONTENT_TYPE"):
            self.headers["Content-Type"] = environ["CONTENT_TYPE"]
        self.headers["Content-Length"] = environ.get("CONTENT_LENGTH") or "0"
        self.rfile = environ["wsgi.input"]
        self.wfile = io.BytesIO()
        self.status = "500 Internal Server Error"
        self.out_headers = []

    def send_response(self, code, message=None):
        self.status = f"{code} {message or self.responses.get(code, ('',))[0]}"

    def send_header(self, name, value):
        self.out_headers.append((name, str(value)))

    def end_headers(self):
        pass


def application(environ, start_response):
    handler = WSGIHandler(environ)
    if handler.command == "GET":
        handler.do_GET()
    elif handler.command == "POST":
        handler.do_POST()
    else:
        handler.send_json(405, {"error": "method not allowed"})
    start_response(handler.status, handler.out_headers)
    return [handler.wfile.getvalue()]


if __name__ == "__main__":
    # quick local check of this file: python3 wsgi.py, then open http://127.0.0.1:8001
    from wsgiref.simple_server import make_server
    port = int(os.environ.get("PORT", "8001"))
    print(f"WSGI test server: http://127.0.0.1:{port}")
    make_server("127.0.0.1", port, application).serve_forever()
