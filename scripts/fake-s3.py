#!/usr/bin/env python3
"""Local stand-in for an S3-compatible store and an HTTP upload endpoint, for testing Tenix-ChaeDiew uploads.

It verifies AWS Signature V4 with its own independent implementation (hmac/hashlib), so a passing upload proves the
request Tenix-ChaeDiew built is signed correctly, not just that it agrees with Tenix-ChaeDiew's own signer.

    python3 scripts/fake-s3.py            # prints the port, serves until killed

Endpoints
  PUT  /<bucket>/<key>      SigV4 header-signed upload (path style)
  GET  /<bucket>/<key>?...  presigned download (SigV4 query signing), or 403
  POST /upload              multipart/form-data field "file"; needs "Authorization: Bearer secret-token"; replies {"url": ...}
  GET  /files/<name>        serves what /upload stored
"""
import hashlib, hmac, json, sys, urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer

ACCESS_KEY = "AKIAFAKEFAKEFAKE"
SECRET_KEY = "fakeSecret/KEY+for/testing"
REGION = "us-east-1"
TOKEN = "secret-token"
objects, files = {}, {}


def sign(secret, date_stamp, region, string_to_sign):
    def h(k, m): return hmac.new(k, m.encode(), hashlib.sha256).digest()
    k = h(("AWS4" + secret).encode(), date_stamp)
    k = h(k, region); k = h(k, "s3"); k = h(k, "aws4_request")
    return hmac.new(k, string_to_sign.encode(), hashlib.sha256).hexdigest()


def enc(s, keep_slash=False):
    return urllib.parse.quote(s, safe="/" if keep_slash else "")


def canonical_query(pairs):
    encoded = sorted((enc(k), enc(v)) for k, v in pairs)
    return "&".join(f"{k}={v}" for k, v in encoded)


def expected_signature(method, path, query_pairs, headers, signed_names, payload_hash, amz_date, region):
    canon_headers = "".join(f"{n}:{headers[n].strip()}\n" for n in signed_names)
    canonical = "\n".join([method, enc(path, True), canonical_query(query_pairs), canon_headers,
                           ";".join(signed_names), payload_hash])
    scope = f"{amz_date[:8]}/{region}/s3/aws4_request"
    sts = "\n".join(["AWS4-HMAC-SHA256", amz_date, scope, hashlib.sha256(canonical.encode()).hexdigest()])
    return sign(SECRET_KEY, amz_date[:8], region, sts)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def reply(self, code, body=b"", ctype="text/plain"):
        self.send_response(code); self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)

    def lowered(self):
        return {k.lower(): v for k, v in self.headers.items()}

    def do_PUT(self):
        url = urllib.parse.urlsplit(self.path)
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        h = self.lowered()
        auth = h.get("authorization", "")
        try:
            parts = dict(p.strip().split("=", 1) for p in auth.split(" ", 1)[1].split(","))
            signed = parts["SignedHeaders"].split(";")
            given = parts["Signature"]
            cred = parts["Credential"].split("/")
        except Exception:
            return self.reply(403, b"malformed Authorization")
        if cred[0] != ACCESS_KEY: return self.reply(403, b"unknown access key")
        if h.get("x-amz-content-sha256") != hashlib.sha256(body).hexdigest():
            return self.reply(400, b"payload hash does not match body")
        path = urllib.parse.unquote(url.path)
        want = expected_signature("PUT", path, urllib.parse.parse_qsl(url.query), h, signed,
                                  h["x-amz-content-sha256"], h["x-amz-date"], cred[2])
        if want != given: return self.reply(403, b"SignatureDoesNotMatch")
        objects[path] = (body, h.get("content-type", ""))
        self.reply(200)

    def do_GET(self):
        url = urllib.parse.urlsplit(self.path)
        path = urllib.parse.unquote(url.path)
        if path.startswith("/files/"):
            item = files.get(path)
            return self.reply(200, item) if item else self.reply(404)
        q = dict(urllib.parse.parse_qsl(url.query))
        if "X-Amz-Signature" not in q: return self.reply(403, b"not presigned")
        pairs = [(k, v) for k, v in urllib.parse.parse_qsl(url.query) if k != "X-Amz-Signature"]
        want = expected_signature("GET", path, pairs, {"host": self.headers["Host"]}, ["host"],
                                  "UNSIGNED-PAYLOAD", q["X-Amz-Date"], q["X-Amz-Credential"].split("/")[2])
        if want != q["X-Amz-Signature"]: return self.reply(403, b"SignatureDoesNotMatch (presigned)")
        if path not in objects: return self.reply(404)
        body, ctype = objects[path]
        self.reply(200, body, ctype)

    def do_POST(self):
        if self.path != "/upload": return self.reply(404)
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if self.headers.get("Authorization") != f"Bearer {TOKEN}": return self.reply(401, b"bad token")
        ctype = self.headers.get("Content-Type", "")
        boundary = ctype.split("boundary=")[1].encode()
        part = [p for p in body.split(b"--" + boundary) if b'name="file"' in p][0]
        head, _, data = part.partition(b"\r\n\r\n")
        data = data.rsplit(b"\r\n", 1)[0]
        name = head.split(b'filename="')[1].split(b'"')[0].decode()
        files["/files/" + name] = data
        host = self.headers["Host"]
        self.reply(200, json.dumps({"url": f"http://{host}/files/{name}"}).encode(), "application/json")


if __name__ == "__main__":
    server = HTTPServer(("127.0.0.1", 0), Handler)
    print(server.server_port, flush=True)
    server.serve_forever()
